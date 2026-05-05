using System.Net;
using System.Net.Http.Json;
using System.Text;
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
        _client = factory.WithWebHostBuilder(b => b.UseEnvironment("Testing")).CreateClient();
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

    [Fact]
    public async Task UploadEndpoint_ReturnsBadRequest_WhenNoFileProvided()
    {
        // Send a multipart request with a text field but no file part.
        // The handler will receive file = null and return 400.
        using var content = new MultipartFormDataContent();
        content.Add(new StringContent("dummy"), "other-field");
        var response = await _client.PostAsync("/upload", content);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task UploadEndpoint_ReturnsServiceUnavailable_WhenStorageNotConfigured()
    {
        // In the test environment AZURE_STORAGE_ACCOUNT_NAME is not set,
        // so BlobServiceClient is not registered and the endpoint returns 503.
        using var content = new MultipartFormDataContent();
        using var fileContent = new StreamContent(new MemoryStream(Encoding.UTF8.GetBytes("hello blob")));
        fileContent.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("text/plain");
        content.Add(fileContent, "file", "test.txt");

        var response = await _client.PostAsync("/upload", content);

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
    }
}
