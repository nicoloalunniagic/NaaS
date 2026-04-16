using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace NoAsAService.Api.Tests;

public sealed class ApiEndpointsTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public ApiEndpointsTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.WithWebHostBuilder(b => b.UseEnvironment("Development")).CreateClient();
    }

    [Fact]
    public async Task RootEndpoint_ReturnsServiceMetadata()
    {
        var payload = await _client.GetFromJsonAsync<JsonObject>("/");

        Assert.NotNull(payload);
        Assert.Equal("no-as-a-service", payload["service"]?.GetValue<string>());
        Assert.Equal("Ask nicely and get creatively rejected.", payload["message"]?.GetValue<string>());
    }

    [Fact]
    public async Task RejectEndpoint_ReturnsRandomRejection()
    {
        var payload = await _client.GetFromJsonAsync<JsonObject>("/reject");

        Assert.NotNull(payload);
        Assert.False(payload["approved"]?.GetValue<bool>() ?? true);

        var reason = payload["reason"]?.GetValue<string>();
        Assert.False(string.IsNullOrWhiteSpace(reason));
    }

    [Fact]
    public async Task OpenApiEndpoint_IsAvailable()
    {
        var response = await _client.GetAsync("/openapi/v1.json");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }
}
