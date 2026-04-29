using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using NoAsAService.Api.Data;
using Xunit;

namespace NoAsAService.Api.Tests;

public sealed class CustomersAndProjectsTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly WebApplicationFactory<Program> _factory;
    private readonly string _dbName = $"naas-tests-{Guid.NewGuid()}";
    private readonly InMemoryDatabaseRoot _dbRoot = new();

    public CustomersAndProjectsTests(WebApplicationFactory<Program> factory)
    {
        // Replace the registered DbContext with an isolated in-memory database that
        // shares a single InMemoryDatabaseRoot across all DbContext instances.
        _factory = factory.WithWebHostBuilder(b =>
        {
            b.UseEnvironment("Development");
            b.ConfigureServices(services =>
            {
                services.RemoveAll(typeof(DbContextOptions<AppDbContext>));
                services.RemoveAll(typeof(DbContextOptions));
                services.AddDbContext<AppDbContext>(o =>
                    o.UseInMemoryDatabase(_dbName, _dbRoot));
            });
        });
    }

    [Fact]
    public async Task CustomerAndProject_FullLifecycle_Works()
    {
        var client = _factory.CreateClient();

        // Create a customer.
        var createCustomer = await client.PostAsJsonAsync("/customers",
            new { name = "Acme Corp", email = "ops@acme.test" });
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

        var response = await client.PostAsJsonAsync("/projects",
            new { name = "Orphan", customerId = 9999 });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task CreateCustomer_WithoutName_ReturnsBadRequest()
    {
        var client = _factory.CreateClient();

        var response = await client.PostAsJsonAsync("/customers", new { name = "" });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }
}
