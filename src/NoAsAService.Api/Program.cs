using Azure.Identity;
using Azure.Storage.Blobs;
using Azure;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using NoAsAService.Api.Data;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using System.Text.Json.Serialization;
using System.Threading.RateLimiting;

var builder = WebApplication.CreateBuilder(args);

// ── VAPT Lab Mode ──────────────────────────────────────────────────────────
// NOTE: vaptLabMode is read from app.Configuration *after* builder.Build() so
// that WebApplicationFactory test-time configuration is fully applied before
// the flag is evaluated. Reading it from builder.Configuration here would
// capture the value before the DeferredHostBuilder resolves test overrides.
// ──────────────────────────────────────────────────────────────────────────

builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.ReferenceHandler = ReferenceHandler.IgnoreCycles;
});

builder.Services.AddRateLimiter(options =>
{
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 120,
                Window = TimeSpan.FromMinutes(1)
            }));
    options.RejectionStatusCode = 429;
});

builder.Services.AddEndpointsApiExplorer();

var jwtIssuer = builder.Configuration["JWT_ISSUER"] ?? "naas-api";
var jwtAudience = builder.Configuration["JWT_AUDIENCE"] ?? "naas-web";
var jwtSigningKey = builder.Configuration["JWT_SIGNING_KEY"];

if (string.IsNullOrWhiteSpace(jwtSigningKey))
{
    if (builder.Environment.IsDevelopment() || builder.Environment.IsEnvironment("Testing"))
    {
        jwtSigningKey = "dev-only-super-secret-key-change-me-at-once";
    }
    else
    {
        throw new InvalidOperationException("JWT_SIGNING_KEY is required outside development.");
    }
}

var signingKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSigningKey));

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateIssuerSigningKey = true,
            ValidateLifetime = true,
            ValidIssuer = jwtIssuer,
            ValidAudience = jwtAudience,
            IssuerSigningKey = signingKey,
            ClockSkew = TimeSpan.FromSeconds(30)
        };
    });

builder.Services.AddAuthorization();
builder.Services.AddSingleton<IPasswordHasher<User>, PasswordHasher<User>>();

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
if (builder.Environment.IsEnvironment("Testing"))
{
    builder.Services.AddDbContext<AppDbContext>(options =>
        options.UseInMemoryDatabase("naas-testing"));
}
else if (!string.IsNullOrWhiteSpace(databaseConnectionString))
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

    options.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        In = ParameterLocation.Header,
        Description = "Insert JWT token as: Bearer {token}"
    });

    options.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference
                {
                    Type = ReferenceType.SecurityScheme,
                    Id = "Bearer"
                }
            },
            Array.Empty<string>()
        }
    });
});

var app = builder.Build();

// ── VAPT Lab Mode ──────────────────────────────────────────────────────────
// Read AFTER Build() so test factories (WebApplicationFactory + UseSetting)
// are fully applied. Set ENABLE_VAPT_LAB_MODE=true ONLY in isolated lab
// environments — never in production or with real data.
var vaptLabMode = app.Configuration.GetValue<bool>("ENABLE_VAPT_LAB_MODE");
// ──────────────────────────────────────────────────────────────────────────

// ── VAPT Lab Mode startup banner ───────────────────────────────────────────
var startupLogger = app.Services.GetRequiredService<ILoggerFactory>().CreateLogger("VaptLab");
if (vaptLabMode)
{
    startupLogger.LogWarning("═══════════════════════════════════════════════════════════════");
    startupLogger.LogWarning("  ██╗   ██╗ █████╗ ██████╗ ████████╗    ██╗      █████╗ ██████╗ ");
    startupLogger.LogWarning("  VAPT LAB MODE ENABLED — intentionally vulnerable             ");
    startupLogger.LogWarning("  DO NOT use in production or with real data!                  ");
    startupLogger.LogWarning("  Set ENABLE_VAPT_LAB_MODE=false to restore safe behaviour.   ");
    startupLogger.LogWarning("═══════════════════════════════════════════════════════════════");
}
// ──────────────────────────────────────────────────────────────────────────

// In development (Azurite) the container won't be pre-created by Bicep, so ensure it exists.
if (app.Environment.IsDevelopment())
{
    var blobSvc = app.Services.GetService<BlobServiceClient>();
    if (blobSvc is not null)
    {
        var logger = app.Services.GetRequiredService<ILoggerFactory>().CreateLogger("BlobStartup");
        var container = blobSvc.GetBlobContainerClient(
            app.Configuration["AZURE_STORAGE_CONTAINER_NAME"] ?? "uploads");
        try
        {
            await container.CreateIfNotExistsAsync();
        }
        catch (Exception ex) when (IsStorageUnavailable(ex))
        {
            logger.LogWarning(
                "Blob storage is configured but unreachable. API will continue to start; upload endpoints may return 503 until storage becomes available. Reason: {Reason}",
                GetRootExceptionMessage(ex));
            logger.LogDebug(ex, "Blob startup connectivity diagnostics.");
        }
    }
}

// Ensure database schema is ready on startup.
// - Relational providers use EF Core migrations.
// - In-memory provider uses EnsureCreated.
// Retry a few times so the API tolerates the database not being ready yet
// (e.g. first boot under docker compose, transient DNS resolution).
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    var logger = scope.ServiceProvider.GetRequiredService<ILoggerFactory>().CreateLogger("DbStartup");
    var maxAttempts = Math.Clamp(app.Configuration.GetValue("DB_STARTUP_MAX_RETRIES", 10), 1, 30);
    for (var attempt = 1; attempt <= maxAttempts; attempt++)
    {
        try
        {
            if (db.Database.IsRelational())
            {
                // One-time bridge: old environments created tables via EnsureCreated.
                // If core tables already exist and migration history is empty, mark
                // the initial migration as applied to prevent duplicate CREATE TABLE.
                await db.Database.ExecuteSqlRawAsync(@"
                    CREATE TABLE IF NOT EXISTS ""__EFMigrationsHistory"" (
                        ""MigrationId"" character varying(150) NOT NULL,
                        ""ProductVersion"" character varying(32) NOT NULL,
                        CONSTRAINT ""PK___EFMigrationsHistory"" PRIMARY KEY (""MigrationId"")
                    );
                ");

                await db.Database.ExecuteSqlRawAsync(@"
                    INSERT INTO ""__EFMigrationsHistory"" (""MigrationId"", ""ProductVersion"")
                    SELECT '20260505120428_InitialSchema', '10.0.0'
                    WHERE EXISTS (
                        SELECT 1 FROM information_schema.tables
                        WHERE table_schema = 'public' AND table_name = 'customers'
                    )
                    AND EXISTS (
                        SELECT 1 FROM information_schema.tables
                        WHERE table_schema = 'public' AND table_name = 'projects'
                    )
                    AND EXISTS (
                        SELECT 1 FROM information_schema.tables
                        WHERE table_schema = 'public' AND table_name = 'users'
                    )
                    AND NOT EXISTS (
                        SELECT 1 FROM ""__EFMigrationsHistory""
                        WHERE ""MigrationId"" = '20260505120428_InitialSchema'
                    );
                ");

                await db.Database.MigrateAsync();
            }
            else
            {
                await db.Database.EnsureCreatedAsync();
            }
            break;
        }
        catch (Exception ex) when (attempt < maxAttempts)
        {
            logger.LogWarning(
                "Database not ready (attempt {Attempt}/{Max}). Retrying... Reason: {Reason}",
                attempt, maxAttempts, GetRootExceptionMessage(ex));
            logger.LogDebug(ex, "Database startup retry diagnostics.");
            await Task.Delay(TimeSpan.FromSeconds(Math.Min(2 * attempt, 10)));
        }
    }
}

app.UseCors(CorsPolicy);

// ── VAPT Lab: Error Leakage middleware ────────────────────────────────────
// INTENTIONAL VAPT LAB VULNERABILITY (when vaptLabMode=true):
//   Full exception details (message, type, stack trace) are returned to the
//   client, allowing information disclosure attacks.
// Safe behaviour: only a generic message is returned.
app.Use(async (context, next) =>
{
    try
    {
        await next(context);
    }
    catch (Exception ex)
    {
        context.Response.StatusCode = 500;
        context.Response.ContentType = "application/json";
        if (vaptLabMode)
        {
            // INTENTIONAL VAPT LAB VULNERABILITY: Error Leakage
            await context.Response.WriteAsJsonAsync(new
            {
                status = "error",
                message = ex.Message,
                exceptionType = ex.GetType().FullName,
                stackTrace = ex.StackTrace,
                vapt_note = "VAPT LAB MODE: technical details exposed intentionally"
            });
        }
        else
        {
            // Safe: generic message only — no internal details disclosed
            await context.Response.WriteAsJsonAsync(new
            {
                status = "error",
                message = "An unexpected error occurred."
            });
        }
    }
});
// ──────────────────────────────────────────────────────────────────────────

app.UseAuthentication();
app.UseAuthorization();

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
    message = "Ask nicely and get creatively rejected.",
    vaptLabMode
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

var auth = app.MapGroup("/auth").WithTags("Auth");

auth.MapPost("/register", async (RegisterRequest input, AppDbContext db, IPasswordHasher<User> hasher) =>
{
    var validationError = ValidateCredentials(input.Username, input.Password);
    if (validationError is not null)
        return Results.BadRequest(new { status = "error", message = validationError });

    var username = input.Username.Trim();
    var normalized = username.ToUpperInvariant();

    if (await db.Users.AnyAsync(u => u.NormalizedUsername == normalized))
        return Results.Conflict(new { status = "error", message = "Username already exists." });

    var user = new User
    {
        Username = username,
        NormalizedUsername = normalized
    };
    user.PasswordHash = hasher.HashPassword(user, input.Password);

    db.Users.Add(user);
    await db.SaveChangesAsync();

    return Results.Created($"/auth/users/{user.Id}", new
    {
        id = user.Id,
        username = user.Username,
        createdAt = user.CreatedAt
    });
})
.WithName("RegisterUser");

auth.MapPost("/login", async (LoginRequest input, AppDbContext db, IPasswordHasher<User> hasher) =>
{
    var username = input.Username.Trim();
    if (string.IsNullOrWhiteSpace(username) || string.IsNullOrWhiteSpace(input.Password))
        return Results.BadRequest(new { status = "error", message = "Username and password are required." });

    var normalized = username.ToUpperInvariant();
    var user = await db.Users.FirstOrDefaultAsync(u => u.NormalizedUsername == normalized);
    if (user is null)
        return Results.Unauthorized();

    var verifyResult = hasher.VerifyHashedPassword(user, user.PasswordHash, input.Password);
    if (verifyResult == PasswordVerificationResult.Failed)
        return Results.Unauthorized();

    if (verifyResult == PasswordVerificationResult.SuccessRehashNeeded)
    {
        user.PasswordHash = hasher.HashPassword(user, input.Password);
        await db.SaveChangesAsync();
    }

    var expiresAt = DateTime.UtcNow.AddHours(8);
    var token = CreateJwtToken(user, signingKey, jwtIssuer, jwtAudience, expiresAt);

    return Results.Ok(new
    {
        token,
        expiresAt,
        username = user.Username
    });
})
.WithName("LoginUser");

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

    try
    {
        await using var stream = file.OpenReadStream();
        await containerClient.UploadBlobAsync(blobName, stream, ct);
    }
    catch (Exception ex) when (IsStorageUnavailable(ex))
    {
        return Results.Problem("Storage service is unavailable.", statusCode: 503);
    }

    var blobUri = containerClient.GetBlobClient(blobName).Uri;

    return Results.Ok(new
    {
        status = "uploaded",
        blobName,
        blobUrl = blobUri.ToString()
    });
})
.RequireAuthorization()
.WithName("UploadFile")
.DisableAntiforgery();

// ---------------------------------------------------------------------------
// Customers CRUD
// ---------------------------------------------------------------------------
var customers = app.MapGroup("/customers").WithTags("Customers");
customers.RequireAuthorization();

customers.MapGet("", async (string? search, AppDbContext db) =>
{
    // When no search term is given, always return all customers (safe).
    if (string.IsNullOrWhiteSpace(search))
        return Results.Ok(await db.Customers.AsNoTracking().ToListAsync());

    if (vaptLabMode && db.Database.IsRelational())
    {
        // INTENTIONAL VAPT LAB VULNERABILITY: SQL Injection via string concatenation.
        // The `search` value is embedded directly in raw SQL — no parameterisation.
        // Example payload: ' OR '1'='1' --
        // In safe mode the query below is replaced by a parameterised EF LINQ query.
        var rawSql =
            $"""SELECT "Id","Name","Email","CodiceFiscale","CreatedAt" FROM customers WHERE "Name" ILIKE '%{search}%'""";
        return Results.Ok(await db.Customers.FromSqlRaw(rawSql).AsNoTracking().ToListAsync());
    }

    // Safe: EF Core generates a parameterised LIKE query automatically.
    return Results.Ok(await db.Customers
        .Where(c => c.Name.Contains(search))
        .AsNoTracking()
        .ToListAsync());
})
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
projects.RequireAuthorization();

projects.MapGet("", async (AppDbContext db) =>
    Results.Ok(await db.Projects.AsNoTracking().ToListAsync()))
    .WithName("ListProjects");

projects.MapGet("/{id:int}", async (int id, AppDbContext db, HttpContext httpContext) =>
{
    var project = await db.Projects.AsNoTracking().FirstOrDefaultAsync(p => p.Id == id);
    if (project is null) return Results.NotFound();

    if (!vaptLabMode)
    {
        // Safe: verify the requesting user owns this project.
        var currentUserId = httpContext.User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        if (project.OwnerUserId?.ToString() != currentUserId)
            return Results.Forbid();
    }
    // INTENTIONAL VAPT LAB VULNERABILITY (IDOR): in VAPT mode, ownership is not
    // verified — any authenticated user can enumerate projects by guessing IDs.

    return Results.Ok(project);
})
.WithName("GetProject");

projects.MapPost("", async (Project input, AppDbContext db, HttpContext httpContext) =>
{
    if (string.IsNullOrWhiteSpace(input.Name))
        return Results.BadRequest(new { status = "error", message = "Name is required." });

    var customerExists = await db.Customers.AnyAsync(c => c.Id == input.CustomerId);
    if (!customerExists)
        return Results.BadRequest(new { status = "error", message = "CustomerId does not match an existing customer." });

    var currentUserId = httpContext.User.FindFirst(ClaimTypes.NameIdentifier)?.Value;

    var project = new Project
    {
        Name = input.Name.Trim(),
        Description = input.Description,
        CustomerId = input.CustomerId,
        OwnerUserId = int.TryParse(currentUserId, out var uid) ? uid : null
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

// ── VAPT Lab: Broken Role Check ───────────────────────────────────────────
// INTENTIONAL VAPT LAB VULNERABILITY (when vaptLabMode=true):
//   The /admin/stats endpoint skips the role check — any authenticated user
//   can access it. In safe mode only users with the "admin" role claim can.
//   To get an admin JWT, register a user with the username "admin".
var admin = app.MapGroup("/admin").WithTags("Admin").RequireAuthorization();

admin.MapGet("/stats", async (AppDbContext db, HttpContext httpContext) =>
{
    if (!vaptLabMode)
    {
        // Safe: require the "admin" role claim embedded in the JWT.
        var role = httpContext.User.FindFirst(ClaimTypes.Role)?.Value;
        if (role != "admin")
            return Results.Forbid();
    }
    // INTENTIONAL VAPT LAB VULNERABILITY: in VAPT mode only authentication
    // is enforced (by RequireAuthorization()), the role check is bypassed.

    var customerCount = await db.Customers.CountAsync();
    var projectCount = await db.Projects.CountAsync();
    var userCount = await db.Users.CountAsync();

    return Results.Ok(new
    {
        customerCount,
        projectCount,
        userCount,
        vapt_note = vaptLabMode
            ? "VAPT LAB MODE: role check was bypassed — non-admin accessed this endpoint"
            : null
    });
})
.WithName("AdminStats");
// ──────────────────────────────────────────────────────────────────────────

// ── VAPT Lab: error trigger (error leakage demo) ──────────────────────────
// This endpoint always throws so the error-leakage middleware can be
// observed. In safe mode it returns a generic 500; in VAPT mode it returns
// full stack trace + exception type.
app.MapGet("/vapt/trigger-error", () =>
{
    throw new InvalidOperationException(
        "Simulated internal error for VAPT demonstration. " +
        "Sensitive data: DB_CONN=Server=db.internal;User=app_user;Password=L4bP@ssw0rd!");
})
.RequireAuthorization()
.WithName("VaptTriggerError")
.WithTags("VAPT Lab");
// ──────────────────────────────────────────────────────────────────────────

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

static string? ValidateCredentials(string username, string password)
{
    var user = username.Trim();
    if (string.IsNullOrWhiteSpace(user))
        return "Username is required.";
    if (user.Length < 3 || user.Length > 64)
        return "Username must be between 3 and 64 characters.";
    if (!System.Text.RegularExpressions.Regex.IsMatch(user, "^[A-Za-z0-9._-]+$"))
        return "Username can contain only letters, numbers, dot, underscore and hyphen.";
    if (string.IsNullOrWhiteSpace(password))
        return "Password is required.";
    if (password.Length < 12)
        return "Password must be at least 12 characters long.";
    return null;
}

static string CreateJwtToken(User user, SecurityKey signingKey, string issuer, string audience, DateTime expiresAt)
{
    var creds = new SigningCredentials(signingKey, SecurityAlgorithms.HmacSha256);
    var claims = new List<Claim>
    {
        new Claim(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
        new Claim(JwtRegisteredClaimNames.UniqueName, user.Username),
        new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
        new Claim(ClaimTypes.Name, user.Username)
    };

    // The reserved "admin" username receives an admin role claim in the JWT.
    // Use this account to test the broken-role-check VAPT scenario.
    if (user.NormalizedUsername == "ADMIN")
        claims.Add(new Claim(ClaimTypes.Role, "admin"));

    var token = new JwtSecurityToken(
        issuer: issuer,
        audience: audience,
        claims: claims,
        expires: expiresAt,
        signingCredentials: creds);

    return new JwtSecurityTokenHandler().WriteToken(token);
}

static bool IsStorageUnavailable(Exception ex)
{
    if (ex is RequestFailedException || ex is HttpRequestException)
        return true;

    if (ex is AggregateException agg)
    {
        foreach (var inner in agg.Flatten().InnerExceptions)
        {
            if (IsStorageUnavailable(inner))
                return true;
        }
    }

    return false;
}

static string GetRootExceptionMessage(Exception ex)
{
    if (ex is AggregateException agg)
    {
        var flattened = agg.Flatten();
        if (flattened.InnerExceptions.Count > 0)
            return GetRootExceptionMessage(flattened.InnerExceptions[0]);
    }

    var current = ex;
    while (current.InnerException is not null)
    {
        current = current.InnerException;
    }

    return current.Message;
}

public record RegisterRequest(string Username, string Password);
public record LoginRequest(string Username, string Password);

public partial class Program
{
}
