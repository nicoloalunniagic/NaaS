using System.Net;
using System.Net.Http.Json;
using System.Net.Http.Headers;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace NoAsAService.Api.Tests;

public sealed class CustomersAndProjectsTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly WebApplicationFactory<Program> _factory;

    public CustomersAndProjectsTests(WebApplicationFactory<Program> factory)
    {
        _factory = factory.WithWebHostBuilder(b => b.UseEnvironment("Testing"));
    }

    [Fact]
    public async Task CustomerAndProject_FullLifecycle_Works()
    {
        var client = _factory.CreateClient();
        await AuthenticateAsync(client);

        // Create a customer.
        var createCustomer = await client.PostAsJsonAsync("/customers",
            new { name = "Acme Corp", email = "ops@acme.test", codiceFiscale = "RSSMRA85M01H501Z" });
        Assert.Equal(HttpStatusCode.Created, createCustomer.StatusCode);
        var customer = await createCustomer.Content.ReadFromJsonAsync<JsonObject>();
        var customerId = customer!["id"]!.GetValue<int>();

        // List customers contains the new one.
        var list = await client.GetFromJsonAsync<JsonArray>("/customers");
        Assert.NotNull(list);
        Assert.Contains(list!, n => n!["id"]!.GetValue<int>() == customerId);

        // Create a project linked to the customer.
        var createProject = await client.PostAsJsonAsync("/projects",
            new { name = "Website redesign", description = "Phase 1", customerId });
        Assert.Equal(HttpStatusCode.Created, createProject.StatusCode);
        var project = await createProject.Content.ReadFromJsonAsync<JsonObject>();
        var projectId = project!["id"]!.GetValue<int>();
        Assert.Equal(customerId, project["customerId"]!.GetValue<int>());

        // The customer's projects endpoint returns the new project.
        var customerProjects = await client.GetFromJsonAsync<JsonArray>($"/customers/{customerId}/projects");
        Assert.NotNull(customerProjects);
        Assert.Single(customerProjects!);
        Assert.Equal(projectId, customerProjects![0]!["id"]!.GetValue<int>());

        // Deleting the customer cascades to its projects.
        var delete = await client.DeleteAsync($"/customers/{customerId}");
        Assert.Equal(HttpStatusCode.NoContent, delete.StatusCode);

        var orphan = await client.GetAsync($"/projects/{projectId}");
        Assert.Equal(HttpStatusCode.NotFound, orphan.StatusCode);
    }

    [Fact]
    public async Task CreateProject_WithUnknownCustomer_ReturnsBadRequest()
    {
        var client = _factory.CreateClient();
        await AuthenticateAsync(client);

        var response = await client.PostAsJsonAsync("/projects",
            new { name = "Orphan", customerId = 9999 });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task CreateCustomer_WithoutName_ReturnsBadRequest()
    {
        var client = _factory.CreateClient();
        await AuthenticateAsync(client);

        var response = await client.PostAsJsonAsync("/customers", new { name = "" });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    private static async Task AuthenticateAsync(HttpClient client)
    {
        var username = $"testuser-{Guid.NewGuid():N}";
        var password = "DevPassword123456";

        var register = await client.PostAsJsonAsync("/auth/register", new
        {
            username,
            password
        });
        Assert.Equal(HttpStatusCode.Created, register.StatusCode);

        var login = await client.PostAsJsonAsync("/auth/login", new
        {
            username,
            password
        });
        Assert.Equal(HttpStatusCode.OK, login.StatusCode);

        var payload = await login.Content.ReadFromJsonAsync<JsonObject>();
        var token = payload?["token"]?.GetValue<string>();
        Assert.False(string.IsNullOrWhiteSpace(token));

        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
    }
}
