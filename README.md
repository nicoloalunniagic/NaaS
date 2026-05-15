# No-as-a-Service

Tiny ASP.NET Core API on .NET 10 with Docker support.

## What is included

- Minimal HTTP API
- JWT authentication (`/auth/register`, `/auth/login`)
- File upload page at `/upload` (simple web UI)
- Blob upload endpoint at `POST /upload` (JWT required)
- Relational database (PostgreSQL) with `customers` and `projects` tables (1 customer → N projects), exposed via CRUD endpoints
- OpenAPI JSON at `/openapi/v1.json`
- Swagger UI at `/docs`
- Local Blob Storage emulation with Azurite in Docker Compose
- Local PostgreSQL database in Docker Compose
- React + TypeScript front-end (Vite) for managing customers and projects
- Docker build and compose setup
- GitHub Actions CI for restore, test, and Docker build

## Quick start

### Run locally

```bash
dotnet restore src/NoAsAService.Api/NoAsAService.Api.csproj
dotnet run --project src/NoAsAService.Api/NoAsAService.Api.csproj
```

### Run tests

```bash
dotnet test src/tests/NoAsAService.Api.Tests/NoAsAService.Api.Tests.csproj -c Release
```

Integration tests run the app in a dedicated `Testing` environment that uses
an in-memory database and test-safe JWT defaults.

### Run with Docker

```bash
docker compose -f docker/docker-compose.yml up --build
```

## Useful endpoints

- Home: `http://localhost:8000/`
- Reject: `http://localhost:8000/reject`
- Upload UI (public page): `http://localhost:8000/upload`
- Upload endpoint: `POST http://localhost:8000/upload` (JWT required)
- Auth register: `POST http://localhost:8000/auth/register`
- Auth login: `POST http://localhost:8000/auth/login`
- Customers CRUD: `http://localhost:8000/customers` (JWT required)
- Projects CRUD: `http://localhost:8000/projects` (JWT required)
- Customer projects: `http://localhost:8000/customers/{id}/projects` (JWT required)
- OpenAPI: `http://localhost:8000/openapi/v1.json`
- Swagger UI: `http://localhost:8000/docs`

## Database

The API uses Entity Framework Core with three entities:

- `User` (id, username, normalizedUsername, passwordHash, createdAt)
- `Customer` (id, name, email, codiceFiscale, createdAt)
- `Project` (id, name, description, createdAt, customerId)

The relation is 1-to-N (one customer, many projects) with cascade delete on the customer.
Customers, projects, and `POST /upload` are protected endpoints: call `/auth/login` first and send `Authorization: Bearer <token>`.

Configuration is done via the `DATABASE_CONNECTION_STRING` environment variable
(Npgsql / PostgreSQL connection string). When the variable is not set, the API
falls back to an in-memory provider so it can run without external dependencies
(useful for tests and quick local runs).

For relational databases, schema lifecycle is managed with EF Core migrations
(`Database.Migrate`) at startup.

When using `docker compose`, a PostgreSQL 16 instance is started automatically
and wired to the API via `DATABASE_CONNECTION_STRING`.

### Startup reliability knobs

The API retries relational database startup migrations if the database is not
ready yet.

- `DB_STARTUP_MAX_RETRIES`: number of startup retry attempts (default `10`,
  allowed range `1..30`).

Example (PowerShell):

```powershell
$env:DB_STARTUP_MAX_RETRIES='20'
dotnet run --project src/NoAsAService.Api/NoAsAService.Api.csproj
```

### Local run presets

Use one of these presets depending on your local setup.

#### Preset A: local Docker dependencies (Postgres + Azurite)

```powershell
$env:ASPNETCORE_ENVIRONMENT='Development'
$env:JWT_SIGNING_KEY='dev-local-signing-key-change-for-real-env'
$env:DATABASE_CONNECTION_STRING='Host=localhost;Port=5432;Database=naas;Username=naas;Password=naas'
$env:AZURE_STORAGE_CONNECTION_STRING='DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA=;BlobEndpoint=http://127.0.0.1:10000/devstoreaccount1;'
dotnet run --no-launch-profile --project src/NoAsAService.Api/NoAsAService.Api.csproj
```

#### Preset B: no external dependencies (in-memory DB, upload disabled)

```powershell
$env:ASPNETCORE_ENVIRONMENT='Development'
$env:JWT_SIGNING_KEY='dev-local-signing-key-change-for-real-env'
$env:DATABASE_CONNECTION_STRING=''
$env:AZURE_STORAGE_CONNECTION_STRING=''
dotnet run --no-launch-profile --project src/NoAsAService.Api/NoAsAService.Api.csproj
```

With Preset B, `POST /upload` returns `503` by design because blob storage is
not configured.

## Front-end (React + TypeScript)

A Vite-based SPA in [src/web](src/web/package.json) provides full CRUD for customers and
projects against the API.

The SPA requires authentication before accessing customers/projects.

### Run locally

```bash
cd src/web
npm install
npm run dev
```

The dev server is on `http://localhost:5173` and proxies API calls to the
local API on `http://localhost:8000` (override with `VITE_DEV_API_PROXY`).

When running everything with Docker Compose, the SPA is exposed at
`http://localhost:5173` and the proxy is automatically pointed at the
`naas` service.

### Production build

```bash
cd src/web
VITE_API_BASE_URL=https://<your-api-host> npm run build
```

The static output is written to `src/web/dist` and can be deployed to Azure
Static Web Apps.

### Deploy to Azure Static Web Apps

Both IaC stacks provision a Static Web App resource. The Container App is
configured with `CORS_ALLOWED_ORIGINS` pointing at the SWA URL so the SPA
can call the API directly.

The unified workflow [.github/workflows/deploy-public.yml](.github/workflows/deploy-public.yml)
handles infrastructure provisioning, API image rollout, and SPA publish in
one dispatch. It builds the SPA with `VITE_API_BASE_URL` set to the
deployed API URL and pushes the artifact to the Static Web App.

Required repository / environment variables:

- `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` (OIDC)
- `AZURE_RESOURCE_GROUP` — base resource group name (suffixed with `-b` for Bicep, `-t` for Terraform)
- `AZURE_NAME_PREFIX` — base name prefix (suffixed with `b` or `t` to scope resources per IaC tool)
- `AZURE_LOCATION` — default Azure region
- `AZURE_CORE_LOCATION` — optional override for Container Apps / PostgreSQL region (useful when a region has capacity constraints)
- `AZURE_STATIC_WEB_APP_LOCATION` — optional override for the Static Web App region
- `AZURE_STATIC_WEB_APP_SKU` — optional; defaults to `Free`

The workflow discovers Static Web App and Container App resources directly
from the resource group; no explicit resource name variable is required.

## Repository essentials

- `.gitignore` for .NET and local tooling artifacts
- `.github/workflows/ci.yml` for GitHub Actions

## Documentation

Operational documentation and the editorial pre-merge checklist are available in [docs/README.md](docs/README.md).

## Azure infrastructure

Azure IaC documentation is available in [infra/public/bicep/README.md](infra/public/bicep/README.md) (Bicep) and [infra/public/terraform/](infra/public/terraform/) (Terraform).

Automated Azure deployment is available via the single unified workflow [.github/workflows/deploy.yml](.github/workflows/deploy.yml).
Choose `bicep` or `terraform` as the `infra_tool` input at dispatch time. Each tool provisions its resources in a dedicated resource group and with its own name prefix suffix to avoid collisions.

The stack provisions a PostgreSQL Flexible Server and an Azure Key Vault.
The database connection string is stored as a secret named
`database-connection-string` in the vault. The JWT key is stored as
`jwt-signing-key`. The Container App references both through Key Vault secret
references (using the User-Assigned Managed Identity with the _Key Vault
Secrets User_ role) and exposes them to the application as
`DATABASE_CONNECTION_STRING` and `JWT_SIGNING_KEY`.

The deployment reads `DB_ADMIN_PASSWORD` and `JWT_SIGNING_KEY` from GitHub
environment secrets.
