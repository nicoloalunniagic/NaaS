using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Xunit;

namespace NoAsAService.Api.Tests;

/// <summary>
/// VAPT Lab security tests.
/// Each test exercises one vulnerability in both safe mode (ENABLE_VAPT_LAB_MODE=false)
/// and VAPT mode (ENABLE_VAPT_LAB_MODE=true) and asserts the expected difference.
///
/// Vulnerabilities covered:
///   1. Error Leakage         — /vapt/trigger-error
///   2. IDOR / Broken Access  — GET /projects/{id}
///   3. Broken Role Check     — GET /admin/stats
///   4. SQL Injection         — GET /customers?search= (relational DB only; InMemoryDB falls back to safe LINQ)
/// </summary>
public sealed class VaptLabTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly WebApplicationFactory<Program> _baseFactory;

    public VaptLabTests(WebApplicationFactory<Program> factory)
    {
        _baseFactory = factory;
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private WebApplicationFactory<Program> SafeFactory() =>
        _baseFactory.WithWebHostBuilder(b =>
        {
            b.UseEnvironment("Testing");
            // UseSetting propagates into host settings which are merged into
            // app.Configuration before vaptLabMode is read (after Build()).
            b.UseSetting("ENABLE_VAPT_LAB_MODE", "false");
        });

    private WebApplicationFactory<Program> VaptFactory() =>
        _baseFactory.WithWebHostBuilder(b =>
        {
            b.UseEnvironment("Testing");
            b.UseSetting("ENABLE_VAPT_LAB_MODE", "true");
        });

    private static async Task<string> RegisterAndLoginAsync(HttpClient client, string? username = null)
    {
        var user = username ?? $"vaptuser-{Guid.NewGuid():N}";
        const string password = "VaptLabPassword123!";

        var reg = await client.PostAsJsonAsync("/auth/register", new { username = user, password });
        Assert.Equal(HttpStatusCode.Created, reg.StatusCode);

        var login = await client.PostAsJsonAsync("/auth/login", new { username = user, password });
        Assert.Equal(HttpStatusCode.OK, login.StatusCode);

        var payload = await login.Content.ReadFromJsonAsync<JsonObject>();
        var token = payload!["token"]!.GetValue<string>();
        Assert.False(string.IsNullOrWhiteSpace(token));
        return token!;
    }

    private static async Task<(int customerId, int projectId)> CreateCustomerAndProjectAsync(
        HttpClient client, string suffix)
    {
        var cf = $"VPTL{suffix.PadLeft(12, '0').Substring(0, 12)}";
        var createCust = await client.PostAsJsonAsync("/customers", new
        {
            name = $"VAPT Corp {suffix}",
            email = $"lab{suffix}@vapt.test",
            codiceFiscale = cf
        });
        Assert.Equal(HttpStatusCode.Created, createCust.StatusCode);
        var cust = await createCust.Content.ReadFromJsonAsync<JsonObject>();
        var customerId = cust!["id"]!.GetValue<int>();

        var createProj = await client.PostAsJsonAsync("/projects", new
        {
            name = $"Secret Project {suffix}",
            customerId
        });
        Assert.Equal(HttpStatusCode.Created, createProj.StatusCode);
        var proj = await createProj.Content.ReadFromJsonAsync<JsonObject>();
        var projectId = proj!["id"]!.GetValue<int>();

        return (customerId, projectId);
    }

    // ── 1. Error Leakage ─────────────────────────────────────────────────────

    [Fact]
    public async Task ErrorLeakage_SafeMode_ReturnsGenericMessageWithoutDetails()
    {
        using var factory = SafeFactory();
        var client = factory.CreateClient();
        var token = await RegisterAndLoginAsync(client);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        var response = await client.GetAsync("/vapt/trigger-error");

        Assert.Equal(HttpStatusCode.InternalServerError, response.StatusCode);

        var body = await response.Content.ReadAsStringAsync();
        // Safe mode: no technical details
        Assert.DoesNotContain("stackTrace", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("exceptionType", body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("InvalidOperationException", body, StringComparison.OrdinalIgnoreCase);
        // Returns generic message
        Assert.Contains("error", body, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task ErrorLeakage_VaptMode_ExposesStackTraceAndExceptionType()
    {
        using var factory = VaptFactory();
        var client = factory.CreateClient();
        var token = await RegisterAndLoginAsync(client);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        var response = await client.GetAsync("/vapt/trigger-error");

        Assert.Equal(HttpStatusCode.InternalServerError, response.StatusCode);

        var body = await response.Content.ReadAsStringAsync();
        // VAPT mode: full technical details exposed — this is the vulnerability
        Assert.Contains("stackTrace", body, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("exceptionType", body, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("InvalidOperationException", body, StringComparison.OrdinalIgnoreCase);
    }

    // ── 2. IDOR / Broken Access Control ──────────────────────────────────────

    [Fact]
    public async Task IDOR_SafeMode_ForbidsAccessToAnotherUsersProject()
    {
        using var factory = SafeFactory();

        // User A: register, create a project
        var clientA = factory.CreateClient();
        var tokenA = await RegisterAndLoginAsync(clientA);
        clientA.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", tokenA);

        var suffix = Guid.NewGuid().ToString("N")[..8];
        var (_, projectId) = await CreateCustomerAndProjectAsync(clientA, suffix);

        // User B: register with a different account, try to access User A's project
        var clientB = factory.CreateClient();
        var tokenB = await RegisterAndLoginAsync(clientB);
        clientB.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", tokenB);

        var response = await clientB.GetAsync($"/projects/{projectId}");

        // Safe mode: ownership check enforced → Forbidden
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task IDOR_VaptMode_AllowsAccessToAnyProject()
    {
        using var factory = VaptFactory();

        // User A: register, create a project
        var clientA = factory.CreateClient();
        var tokenA = await RegisterAndLoginAsync(clientA);
        clientA.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", tokenA);

        var suffix = Guid.NewGuid().ToString("N")[..8];
        var (_, projectId) = await CreateCustomerAndProjectAsync(clientA, suffix);

        // User B: register with a different account, try to access User A's project
        var clientB = factory.CreateClient();
        var tokenB = await RegisterAndLoginAsync(clientB);
        clientB.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", tokenB);

        var response = await clientB.GetAsync($"/projects/{projectId}");

        // VAPT mode: no ownership check → OK (the vulnerability)
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task IDOR_SafeMode_OwnerCanAccessOwnProject()
    {
        using var factory = SafeFactory();
        var client = factory.CreateClient();
        var token = await RegisterAndLoginAsync(client);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        var suffix = Guid.NewGuid().ToString("N")[..8];
        var (_, projectId) = await CreateCustomerAndProjectAsync(client, suffix);

        // Owner should always be able to access their own project
        var response = await client.GetAsync($"/projects/{projectId}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    // ── 3. Broken Role Check ─────────────────────────────────────────────────

    [Fact]
    public async Task BrokenRoleCheck_SafeMode_ForbidsNonAdminAccessToAdminStats()
    {
        using var factory = SafeFactory();
        var client = factory.CreateClient();
        // Regular (non-admin) user
        var token = await RegisterAndLoginAsync(client);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        var response = await client.GetAsync("/admin/stats");

        // Safe mode: role check enforced → Forbidden
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task BrokenRoleCheck_SafeMode_AdminUserCanAccessAdminStats()
    {
        using var factory = SafeFactory();
        var client = factory.CreateClient();
        // Username "admin" receives an admin role claim in the JWT
        var token = await RegisterAndLoginAsync(client, "admin");
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        var response = await client.GetAsync("/admin/stats");

        // Admin role is present → OK
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonObject>();
        Assert.NotNull(body!["customerCount"]);
    }

    [Fact]
    public async Task BrokenRoleCheck_VaptMode_NonAdminCanAccessAdminStats()
    {
        using var factory = VaptFactory();
        var client = factory.CreateClient();
        // Regular (non-admin) user
        var token = await RegisterAndLoginAsync(client);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        var response = await client.GetAsync("/admin/stats");

        // VAPT mode: role check bypassed → OK (the vulnerability)
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadAsStringAsync();
        Assert.Contains("vapt_note", body, StringComparison.OrdinalIgnoreCase);
    }

    // ── 4. SQL Injection endpoint availability ────────────────────────────────
    // NOTE: Actual SQL injection can only be exercised against a real PostgreSQL
    // instance (InMemoryDatabase does not support raw SQL and falls back to the
    // safe LINQ path). These tests verify the endpoint responds correctly in
    // both modes. For full injection PoC use Postman against a dev Postgres DB
    // — see docs/en/vapt-lab-mode.md.

    [Fact]
    public async Task SqlInjection_SafeMode_SearchEndpointFiltersCorrectly()
    {
        using var factory = SafeFactory();
        var client = factory.CreateClient();
        var token = await RegisterAndLoginAsync(client);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        var suffix = Guid.NewGuid().ToString("N")[..8];
        // Create a customer so there's something to search
        await client.PostAsJsonAsync("/customers", new
        {
            name = $"SearchCorp {suffix}",
            email = $"s{suffix}@vapt.test",
            codiceFiscale = $"SRCH{suffix.PadLeft(12, '0').Substring(0, 12)}"
        });

        var response = await client.GetAsync($"/customers?search=SearchCorp");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonArray>();
        Assert.NotNull(body);
        // The created customer should appear in results
        Assert.Contains(body!, n => n!["name"]!.GetValue<string>().StartsWith("SearchCorp"));
    }

    [Fact]
    public async Task SqlInjection_VaptMode_SearchEndpointStillResponds()
    {
        using var factory = VaptFactory();
        var client = factory.CreateClient();
        var token = await RegisterAndLoginAsync(client);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        // In InMemoryDB the VAPT path falls back to safe LINQ; endpoint must still respond.
        var response = await client.GetAsync("/customers?search=test");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    // ── 5. Root endpoint exposes vaptLabMode flag ─────────────────────────────

    [Fact]
    public async Task Root_SafeMode_ReportsVaptLabModeFalse()
    {
        using var factory = SafeFactory();
        var client = factory.CreateClient();

        var payload = await client.GetFromJsonAsync<JsonObject>("/");
        Assert.False(payload!["vaptLabMode"]!.GetValue<bool>());
    }

    [Fact]
    public async Task Root_VaptMode_ReportsVaptLabModeTrue()
    {
        using var factory = VaptFactory();
        var client = factory.CreateClient();

        var payload = await client.GetFromJsonAsync<JsonObject>("/");
        Assert.True(payload!["vaptLabMode"]!.GetValue<bool>());
    }
}
