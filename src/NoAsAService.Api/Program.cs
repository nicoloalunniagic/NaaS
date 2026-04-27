using Azure.Identity;
using Azure.Storage.Blobs;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.OpenApi.Models;
using System.Threading.RateLimiting;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddRateLimiter(options =>
{
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 30,
                Window = TimeSpan.FromMinutes(1)
            }));
    options.RejectionStatusCode = 429;
});

builder.Services.AddEndpointsApiExplorer();

// Register BlobServiceClient:
// - If AZURE_STORAGE_CONNECTION_STRING is set (local dev / Azurite), use it directly.
// - Otherwise use the managed identity via DefaultAzureCredential (production).
var storageConnectionString = builder.Configuration["AZURE_STORAGE_CONNECTION_STRING"];
var storageAccountName = builder.Configuration["AZURE_STORAGE_ACCOUNT_NAME"];

if (!string.IsNullOrWhiteSpace(storageConnectionString))
{
    builder.Services.AddSingleton(_ => new BlobServiceClient(storageConnectionString));
}
else if (!string.IsNullOrWhiteSpace(storageAccountName))
{
    builder.Services.AddSingleton(_ => new BlobServiceClient(
        new Uri($"https://{storageAccountName}.blob.core.windows.net"),
        new DefaultAzureCredential()));
}

builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "No-as-a-Service",
        Version = "v1",
        Description = "A tiny API that always says no, but with style."
    });
});

var app = builder.Build();

// In development (Azurite) the container won't be pre-created by Bicep, so ensure it exists.
if (app.Environment.IsDevelopment())
{
    var blobSvc = app.Services.GetService<BlobServiceClient>();
    if (blobSvc is not null)
    {
        var container = blobSvc.GetBlobContainerClient(
            app.Configuration["AZURE_STORAGE_CONTAINER_NAME"] ?? "uploads");
        await container.CreateIfNotExistsAsync();
    }
}

app.Use(async (context, next) =>
{
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    context.Response.Headers["X-Frame-Options"] = "DENY";
    context.Response.Headers["Referrer-Policy"] = "no-referrer";
    await next(context);
});

app.UseRateLimiter();

var rejectionReasons = new[]
{
    "No, because the office plant has not approved it yet.",
    "Denied: Mercury is in retrograde and so is this request.",
    "Nope. Our rubber duck looked disappointed.",
    "Rejected by the Committee of Unnecessary Meetings.",
    "Hard no. The snack budget cannot sustain this decision.",
    "No. We asked the Magic 8-Ball and it rolled off the table.",
    "Denied. This violates at least three unwritten rules.",
    "No, because the Wi-Fi spirit is not aligned today.",
    "Request rejected. The intern's cat voted against it.",
    "No. Even the loading spinner gave up.",
    "Denied: your request is too reasonable for this timeline.",
    "Negative. The project horoscope said 'avoid bold moves'."
};

app.UseSwagger(options =>
{
    options.RouteTemplate = "openapi/{documentName}.json";
});

app.UseSwaggerUI(options =>
{
    options.RoutePrefix = "docs";
    options.SwaggerEndpoint("/openapi/v1.json", "No-as-a-Service v1");
    options.DocumentTitle = "No-as-a-Service Docs";
});

app.MapGet("/", () => Results.Ok(new
{
    service = "no-as-a-service",
    message = "Ask nicely and get creatively rejected."
}))
.WithName("GetServiceInfo");

app.MapGet("/favicon.ico", (IWebHostEnvironment environment) =>
{
    var faviconPath = Path.Combine(environment.ContentRootPath, "static", "favicon.jpg");
    return Results.File(faviconPath, "image/jpeg");
})
.ExcludeFromDescription();

app.MapGet("/upload", (IWebHostEnvironment environment) =>
{
    var htmlPath = Path.Combine(environment.ContentRootPath, "static", "upload.html");
    return Results.File(htmlPath, "text/html");
})
.ExcludeFromDescription();

app.MapGet("/reject", () => Results.Ok(new
{
    approved = false,
    reason = rejectionReasons[Random.Shared.Next(rejectionReasons.Length)]
}))
.WithName("GetRandomRejection");

const long MaxFileSizeBytes = 50 * 1024 * 1024; // 50 MB
var uploadContainerName = app.Configuration["AZURE_STORAGE_CONTAINER_NAME"] ?? "uploads";

app.MapPost("/upload", async (IFormFile? file, [FromServices] BlobServiceClient? blobClient, CancellationToken ct) =>
{
    if (file is null || file.Length == 0)
        return Results.BadRequest(new { status = "error", message = "No file provided." });

    if (file.Length > MaxFileSizeBytes)
        return Results.BadRequest(new { status = "error", message = "File exceeds the 50 MB size limit." });

    if (blobClient is null)
        return Results.Problem("Storage is not configured.", statusCode: 503);

    var containerClient = blobClient.GetBlobContainerClient(uploadContainerName);
    var safeName = Path.GetFileName(file.FileName);
    var blobName = $"{Guid.NewGuid():N}-{safeName}";

    await using var stream = file.OpenReadStream();
    await containerClient.UploadBlobAsync(blobName, stream, ct);

    var blobUri = containerClient.GetBlobClient(blobName).Uri;

    return Results.Ok(new
    {
        status = "uploaded",
        blobName,
        blobUrl = blobUri.ToString()
    });
})
.WithName("UploadFile")
.DisableAntiforgery();

app.Run();

public partial class Program
{
}
