using Azure.Identity;
using Azure.Storage.Blobs;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
using NoAsAService.Api.Data;
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

// CORS: allow the SPA front-end to call the API. Origins come from the
// CORS_ALLOWED_ORIGINS env var (comma-separated). In dev, also allow the
// local Vite dev server.
const string CorsPolicy = "web-spa";
var corsOriginsRaw = builder.Configuration["CORS_ALLOWED_ORIGINS"] ?? string.Empty;
var configuredOrigins = corsOriginsRaw
    .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
var devOrigins = new[] { "http://localhost:5173", "http://localhost:4173" };
var allowedOrigins = configuredOrigins
    .Concat(builder.Environment.IsDevelopment() ? devOrigins : Array.Empty<string>())
    .Distinct()
    .ToArray();

builder.Services.AddCors(options =>
{
    options.AddPolicy(CorsPolicy, policy =>
    {
        if (allowedOrigins.Length > 0)
        {
            policy.WithOrigins(allowedOrigins)
                .AllowAnyHeader()
                .AllowAnyMethod();
        }
    });
});

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

// Register the EF Core DbContext.
// - If DATABASE_CONNECTION_STRING is set, use PostgreSQL (Npgsql).
// - Otherwise fall back to an in-memory database (useful for tests/dev without a DB).
var databaseConnectionString = builder.Configuration["DATABASE_CONNECTION_STRING"];
if (!string.IsNullOrWhiteSpace(databaseConnectionString))
{
    builder.Services.AddDbContext<AppDbContext>(options =>
        options.UseNpgsql(databaseConnectionString, npgsql =>
            npgsql.EnableRetryOnFailure(
                maxRetryCount: 5,
                maxRetryDelay: TimeSpan.FromSeconds(10),
                errorCodesToAdd: null)));
}
else
{
    builder.Services.AddDbContext<AppDbContext>(options =>
        options.UseInMemoryDatabase("naas-dev"));
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

// Ensure the relational schema is created on startup. For a real production
// system you'd use EF Core migrations; EnsureCreated keeps the demo simple.
// Retry a few times so the API tolerates the database not being ready yet
// (e.g. first boot under docker compose, transient DNS resolution).
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    var logger = scope.ServiceProvider.GetRequiredService<ILoggerFactory>().CreateLogger("DbStartup");
    const int maxAttempts = 10;
    for (var attempt = 1; attempt <= maxAttempts; attempt++)
    {
        try
        {
            await db.Database.EnsureCreatedAsync();
            break;
        }
        catch (Exception ex) when (attempt < maxAttempts)
        {
            logger.LogWarning(ex,
                "Database not ready (attempt {Attempt}/{Max}). Retrying...",
                attempt, maxAttempts);
            await Task.Delay(TimeSpan.FromSeconds(Math.Min(2 * attempt, 10)));
        }
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

app.UseCors(CorsPolicy);

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

// ---------------------------------------------------------------------------
// Customers CRUD
// ---------------------------------------------------------------------------
var customers = app.MapGroup("/customers").WithTags("Customers");

customers.MapGet("", async (AppDbContext db) =>
    Results.Ok(await db.Customers.AsNoTracking().ToListAsync()))
    .WithName("ListCustomers");

customers.MapGet("/{id:int}", async (int id, AppDbContext db) =>
{
    var customer = await db.Customers
        .Include(c => c.Projects)
        .AsNoTracking()
        .FirstOrDefaultAsync(c => c.Id == id);
    return customer is null ? Results.NotFound() : Results.Ok(customer);
})
.WithName("GetCustomer");

customers.MapPost("", async (Customer input, AppDbContext db) =>
{
    var validation = ValidateCustomer(input);
    if (validation is not null) return validation;

    var name = input.Name.Trim();
    var email = input.Email?.Trim();
    var cf = input.CodiceFiscale.Trim().ToUpperInvariant();

    if (await db.Customers.AnyAsync(c => c.CodiceFiscale == cf))
        return Results.Conflict(new { status = "error", message = "A customer with this Codice Fiscale already exists." });
    if (await db.Customers.AnyAsync(c => c.Name == name && c.Email == email))
        return Results.Conflict(new { status = "error", message = "A customer with the same name and email already exists." });

    var customer = new Customer { Name = name, Email = email, CodiceFiscale = cf };
    db.Customers.Add(customer);
    await db.SaveChangesAsync();
    return Results.Created($"/customers/{customer.Id}", customer);
})
.WithName("CreateCustomer");

customers.MapPut("/{id:int}", async (int id, Customer input, AppDbContext db) =>
{
    var customer = await db.Customers.FindAsync(id);
    if (customer is null) return Results.NotFound();

    var validation = ValidateCustomer(input);
    if (validation is not null) return validation;

    var name = input.Name.Trim();
    var email = input.Email?.Trim();
    var cf = input.CodiceFiscale.Trim().ToUpperInvariant();

    if (await db.Customers.AnyAsync(c => c.Id != id && c.CodiceFiscale == cf))
        return Results.Conflict(new { status = "error", message = "A customer with this Codice Fiscale already exists." });
    if (await db.Customers.AnyAsync(c => c.Id != id && c.Name == name && c.Email == email))
        return Results.Conflict(new { status = "error", message = "A customer with the same name and email already exists." });

    customer.Name = name;
    customer.Email = email;
    customer.CodiceFiscale = cf;
    await db.SaveChangesAsync();
    return Results.Ok(customer);
})
.WithName("UpdateCustomer");

customers.MapDelete("/{id:int}", async (int id, AppDbContext db) =>
{
    var customer = await db.Customers
        .Include(c => c.Projects)
        .FirstOrDefaultAsync(c => c.Id == id);
    if (customer is null) return Results.NotFound();
    db.Customers.Remove(customer);
    await db.SaveChangesAsync();
    return Results.NoContent();
})
.WithName("DeleteCustomer");

customers.MapGet("/{id:int}/projects", async (int id, AppDbContext db) =>
{
    var exists = await db.Customers.AnyAsync(c => c.Id == id);
    if (!exists) return Results.NotFound();
    var list = await db.Projects.AsNoTracking()
        .Where(p => p.CustomerId == id)
        .ToListAsync();
    return Results.Ok(list);
})
.WithName("ListCustomerProjects");

// ---------------------------------------------------------------------------
// Projects CRUD (each project belongs to one customer)
// ---------------------------------------------------------------------------
var projects = app.MapGroup("/projects").WithTags("Projects");

projects.MapGet("", async (AppDbContext db) =>
    Results.Ok(await db.Projects.AsNoTracking().ToListAsync()))
    .WithName("ListProjects");

projects.MapGet("/{id:int}", async (int id, AppDbContext db) =>
{
    var project = await db.Projects.AsNoTracking().FirstOrDefaultAsync(p => p.Id == id);
    return project is null ? Results.NotFound() : Results.Ok(project);
})
.WithName("GetProject");

projects.MapPost("", async (Project input, AppDbContext db) =>
{
    if (string.IsNullOrWhiteSpace(input.Name))
        return Results.BadRequest(new { status = "error", message = "Name is required." });

    var customerExists = await db.Customers.AnyAsync(c => c.Id == input.CustomerId);
    if (!customerExists)
        return Results.BadRequest(new { status = "error", message = "CustomerId does not match an existing customer." });

    var project = new Project
    {
        Name = input.Name.Trim(),
        Description = input.Description,
        CustomerId = input.CustomerId
    };
    db.Projects.Add(project);
    await db.SaveChangesAsync();
    return Results.Created($"/projects/{project.Id}", project);
})
.WithName("CreateProject");

projects.MapPut("/{id:int}", async (int id, Project input, AppDbContext db) =>
{
    var project = await db.Projects.FindAsync(id);
    if (project is null) return Results.NotFound();
    if (string.IsNullOrWhiteSpace(input.Name))
        return Results.BadRequest(new { status = "error", message = "Name is required." });

    if (input.CustomerId != project.CustomerId)
    {
        var customerExists = await db.Customers.AnyAsync(c => c.Id == input.CustomerId);
        if (!customerExists)
            return Results.BadRequest(new { status = "error", message = "CustomerId does not match an existing customer." });
        project.CustomerId = input.CustomerId;
    }

    project.Name = input.Name.Trim();
    project.Description = input.Description;
    await db.SaveChangesAsync();
    return Results.Ok(project);
})
.WithName("UpdateProject");

projects.MapDelete("/{id:int}", async (int id, AppDbContext db) =>
{
    var project = await db.Projects.FindAsync(id);
    if (project is null) return Results.NotFound();
    db.Projects.Remove(project);
    await db.SaveChangesAsync();
    return Results.NoContent();
})
.WithName("DeleteProject");

app.Run();

static IResult? ValidateCustomer(Customer input)
{
    if (string.IsNullOrWhiteSpace(input.Name))
        return Results.BadRequest(new { status = "error", message = "Name is required." });
    if (string.IsNullOrWhiteSpace(input.CodiceFiscale))
        return Results.BadRequest(new { status = "error", message = "Codice Fiscale is required." });
    var cf = input.CodiceFiscale.Trim();
    if (cf.Length != 16 || !System.Text.RegularExpressions.Regex.IsMatch(cf, "^[A-Za-z0-9]{16}$"))
        return Results.BadRequest(new { status = "error", message = "Codice Fiscale must be 16 alphanumeric characters." });
    return null;
}

public partial class Program
{
}
