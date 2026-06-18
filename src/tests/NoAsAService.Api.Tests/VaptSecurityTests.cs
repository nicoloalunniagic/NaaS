using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace NoAsAService.Api.Tests;

/// <summary>
/// Security tests covering each VAPT Lab Mode vulnerability.
/// Each scenario verifies the safe (default) behaviour blocks the attack,
/// and the intentionally-vulnerable behaviour when VAPT mode is on.
/// </summary>
public sealed class VaptSecurityTests
{
    // ── Helpers ────────────────────────────────────────────────────────────

    private static WebApplicationFactory<Program> SafeFactory()
    {
        var dbName = $"naas-testing-{Guid.NewGuid():N}";
        return new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b =>
            {
                b.UseEnvironment("Testing");
                b.UseSetting("ConnectionStrings:InMemoryDbName", dbName);
            });
    }

    private static WebApplicationFactory<Program> VaptFactory()
    {
        var dbName = $"naas-testing-{Guid.NewGuid():N}";
        return new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b =>
            {
                b.UseEnvironment("Testing");
                b.UseSetting("ConnectionStrings:InMemoryDbName", dbName);
                b.UseSetting("ENABLE_VAPT_LAB_MODE", "true");
            });
    }

    private static async Task<HttpClient> AuthenticatedClient(
        WebApplicationFactory<Program> factory, string? usernameOverride = null)
    {
        var client = factory.CreateClient();
        var username = usernameOverride ?? $"vapt-{Guid.NewGuid():N}";
        var password = "DevPassword123456";

        var reg = await client.PostAsJsonAsync("/auth/register", new { username, password });

        // If conflict (user already exists), skip to login
        if (reg.StatusCode != HttpStatusCode.Created && reg.StatusCode != HttpStatusCode.Conflict)
            Assert.Equal(HttpStatusCode.Created, reg.StatusCode);

        var login = await client.PostAsJsonAsync("/auth/login", new { username, password });
        Assert.Equal(HttpStatusCode.OK, login.StatusCode);

        var token = (await login.Content.ReadFromJsonAsync<JsonObject>())!["token"]!.GetValue<string>();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return client;
    }

    // ── 1. SQL Injection ───────────────────────────────────────────────────

    [Fact]
    public async Task SQLi_SafeMode_PayloadTreatedAsLiteralText()
    {
        using var factory = SafeFactory();
        var client = await AuthenticatedClient(factory);

        // Seed a customer whose name does NOT match the payload.
        await client.PostAsJsonAsync("/customers",
            new { name = "Legitimate Corp", email = "a@b.test", codiceFiscale = "LEGITCORP12A01H501Z".Substring(0, 16) });

        // SQLi payload — in safe mode EF parameterises the query so it returns nothing.
        var response = await client.GetAsync("/customers?search=' OR '1'='1' --");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var results = await response.Content.ReadFromJsonAsync<JsonArray>();
        // Safe: the payload is treated as a literal search string, no rows match it.
        Assert.NotNull(results);
        Assert.DoesNotContain(results!, r => r!["name"]!.GetValue<string>() == "Legitimate Corp");
    }

    // NOTE: SQLi vulnerability (raw SQL path) only activates on relational DBs.
    // The in-memory provider used in tests always falls back to the safe EF LINQ
    // path even when ENABLE_VAPT_LAB_MODE=true. Integration tests against a real
    // Postgres instance are needed to exercise the raw SQL injection branch.
    [Fact]
    public async Task SQLi_VaptMode_NonRelationalDb_FallsBackToSafePath()
    {
        using var factory = VaptFactory();
        var client = await AuthenticatedClient(factory);

        await client.PostAsJsonAsync("/customers",
            new { name = "Target Corp", email = "t@b.test", codiceFiscale = "TARGETCORP12A01H" });

        // Even with VAPT mode on, in-memory DB cannot run raw SQL so the safe LINQ
        // path executes — the injection payload matches no customer names.
        var response = await client.GetAsync("/customers?search=' OR '1'='1' --");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var results = await response.Content.ReadFromJsonAsync<JsonArray>();
        Assert.NotNull(results);
        Assert.Empty(results!); // safe path: payload treated as literal text
    }

    // ── 2. IDOR — GET /projects/:id ────────────────────────────────────────

    [Fact]
    public async Task IDOR_GetProject_SafeMode_ForbidsOtherUsersProject()
    {
        using var factory = SafeFactory();

        // User A creates a project.
        var clientA = await AuthenticatedClient(factory);
        var custResp = await clientA.PostAsJsonAsync("/customers",
            new { name = "A Corp", email = "a@a.test", codiceFiscale = "ACORPTEST12A0150" });
        var custId = (await custResp.Content.ReadFromJsonAsync<JsonObject>())!["id"]!.GetValue<int>();
        var projResp = await clientA.PostAsJsonAsync("/projects",
            new { name = "Project Alpha", customerId = custId });
        var projId = (await projResp.Content.ReadFromJsonAsync<JsonObject>())!["id"]!.GetValue<int>();

        // User B tries to read that project.
        var clientB = await AuthenticatedClient(factory);
        var response = await clientB.GetAsync($"/projects/{projId}");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task IDOR_GetProject_VaptMode_ExposesOtherUsersProject()
    {
        using var factory = VaptFactory();

        var clientA = await AuthenticatedClient(factory);
        var custResp = await clientA.PostAsJsonAsync("/customers",
            new { name = "B Corp", email = "b@b.test", codiceFiscale = "BCORPTEST12A0150" });
        var custId = (await custResp.Content.ReadFromJsonAsync<JsonObject>())!["id"]!.GetValue<int>();
        var projResp = await clientA.PostAsJsonAsync("/projects",
            new { name = "Project Beta", customerId = custId });
        var projId = (await projResp.Content.ReadFromJsonAsync<JsonObject>())!["id"]!.GetValue<int>();

        // User B can read User A's project — IDOR vulnerability.
        var clientB = await AuthenticatedClient(factory);
        var response = await clientB.GetAsync($"/projects/{projId}");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    // ── 3. IDOR — PUT /projects/:id ────────────────────────────────────────

    [Fact]
    public async Task IDOR_UpdateProject_SafeMode_ForbidsOtherUsersProject()
    {
        using var factory = SafeFactory();

        var clientA = await AuthenticatedClient(factory);
        var custResp = await clientA.PostAsJsonAsync("/customers",
            new { name = "C Corp", email = "c@c.test", codiceFiscale = "CCORPTEST12A0150" });
        var custId = (await custResp.Content.ReadFromJsonAsync<JsonObject>())!["id"]!.GetValue<int>();
        var projResp = await clientA.PostAsJsonAsync("/projects",
            new { name = "Original Name", customerId = custId });
        var projId = (await projResp.Content.ReadFromJsonAsync<JsonObject>())!["id"]!.GetValue<int>();

        var clientB = await AuthenticatedClient(factory);
        var response = await clientB.PutAsJsonAsync($"/projects/{projId}",
            new { name = "Tampered Name", customerId = custId });

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task IDOR_UpdateProject_VaptMode_AllowsTampering()
    {
        using var factory = VaptFactory();

        var clientA = await AuthenticatedClient(factory);
        var custResp = await clientA.PostAsJsonAsync("/customers",
            new { name = "D Corp", email = "d@d.test", codiceFiscale = "DCORPTEST12A0150" });
        var custId = (await custResp.Content.ReadFromJsonAsync<JsonObject>())!["id"]!.GetValue<int>();
        var projResp = await clientA.PostAsJsonAsync("/projects",
            new { name = "Original Name", customerId = custId });
        var projId = (await projResp.Content.ReadFromJsonAsync<JsonObject>())!["id"]!.GetValue<int>();

        var clientB = await AuthenticatedClient(factory);
        var response = await clientB.PutAsJsonAsync($"/projects/{projId}",
            new { name = "Tampered Name", customerId = custId });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    // ── 4. IDOR — DELETE /projects/:id ─────────────────────────────────────

    [Fact]
    public async Task IDOR_DeleteProject_SafeMode_ForbidsOtherUsersProject()
    {
        using var factory = SafeFactory();

        var clientA = await AuthenticatedClient(factory);
        var custResp = await clientA.PostAsJsonAsync("/customers",
            new { name = "E Corp", email = "e@e.test", codiceFiscale = "ECORPTEST12A0150" });
        var custId = (await custResp.Content.ReadFromJsonAsync<JsonObject>())!["id"]!.GetValue<int>();
        var projResp = await clientA.PostAsJsonAsync("/projects",
            new { name = "Should Not Be Deleted", customerId = custId });
        var projId = (await projResp.Content.ReadFromJsonAsync<JsonObject>())!["id"]!.GetValue<int>();

        var clientB = await AuthenticatedClient(factory);
        var response = await clientB.DeleteAsync($"/projects/{projId}");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task IDOR_DeleteProject_VaptMode_AllowsCrossUserDeletion()
    {
        using var factory = VaptFactory();

        var clientA = await AuthenticatedClient(factory);
        var custResp = await clientA.PostAsJsonAsync("/customers",
            new { name = "F Corp", email = "f@f.test", codiceFiscale = "FCORPTEST12A0150" });
        var custId = (await custResp.Content.ReadFromJsonAsync<JsonObject>())!["id"]!.GetValue<int>();
        var projResp = await clientA.PostAsJsonAsync("/projects",
            new { name = "Will Be Deleted", customerId = custId });
        var projId = (await projResp.Content.ReadFromJsonAsync<JsonObject>())!["id"]!.GetValue<int>();

        var clientB = await AuthenticatedClient(factory);
        var response = await clientB.DeleteAsync($"/projects/{projId}");

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
    }

    // ── 5. Broken Role Check ───────────────────────────────────────────────

    [Fact]
    public async Task BrokenRole_SafeMode_NonAdminForbidden()
    {
        using var factory = SafeFactory();
        // Non-admin user (any username except "admin").
        var client = await AuthenticatedClient(factory);

        var response = await client.GetAsync("/admin/stats");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task BrokenRole_SafeMode_AdminAllowed()
    {
        using var factory = SafeFactory();
        // Use "admin" username to get the admin role claim in JWT token
        var client = await AuthenticatedClient(factory, usernameOverride: "admin");

        var response = await client.GetAsync("/admin/stats");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task BrokenRole_VaptMode_NonAdminCanAccessStats()
    {
        using var factory = VaptFactory();
        // Any authenticated user can reach /admin/stats — role check bypassed.
        var client = await AuthenticatedClient(factory);

        var response = await client.GetAsync("/admin/stats");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    // ── 6. Error Leakage ───────────────────────────────────────────────────

    [Fact]
    public async Task ErrorLeakage_SafeMode_ReturnsGenericMessage()
    {
        using var factory = SafeFactory();
        var client = await AuthenticatedClient(factory);

        var response = await client.GetAsync("/vapt/trigger-error");

        Assert.Equal(HttpStatusCode.InternalServerError, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonObject>();
        Assert.NotNull(body);
        // Safe: no stack trace or exception type exposed.
        Assert.Null(body!["stackTrace"]);
        Assert.Null(body["exceptionType"]);
        Assert.Equal("An unexpected error occurred.", body["message"]!.GetValue<string>());
    }

    [Fact]
    public async Task ErrorLeakage_VaptMode_ExposesStackTrace()
    {
        using var factory = VaptFactory();
        var client = await AuthenticatedClient(factory);

        var response = await client.GetAsync("/vapt/trigger-error");

        Assert.Equal(HttpStatusCode.InternalServerError, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonObject>();
        Assert.NotNull(body);
        // Vulnerability: full technical details are returned.
        Assert.NotNull(body!["stackTrace"]);
        Assert.NotNull(body["exceptionType"]);
        Assert.Contains("L4bP@ssw0rd", body["message"]!.GetValue<string>());
    }
}
