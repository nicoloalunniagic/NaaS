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

app.MapGet("/reject", () => Results.Ok(new
{
    approved = false,
    reason = rejectionReasons[Random.Shared.Next(rejectionReasons.Length)]
}))
.WithName("GetRandomRejection");

app.Run();

public partial class Program
{
}
