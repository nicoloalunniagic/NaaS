# No-as-a-Service

Tiny ASP.NET Core API on .NET 10 with Docker support.

## What is included

- Minimal HTTP API
- File upload page at `/upload` (simple web UI)
- Blob upload endpoint at `POST /upload`
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

### Run with Docker

```bash
docker compose -f docker/docker-compose.yml up --build
```

## Useful endpoints

- Home: `http://localhost:8000/`
- Reject: `http://localhost:8000/reject`
- Upload UI: `http://localhost:8000/upload`
- Customers CRUD: `http://localhost:8000/customers`
- Projects CRUD: `http://localhost:8000/projects`
- Customer projects: `http://localhost:8000/customers/{id}/projects`
- OpenAPI: `http://localhost:8000/openapi/v1.json`
- Swagger UI: `http://localhost:8000/docs`

## Database

The API uses Entity Framework Core with two entities:

- `Customer` (id, name, email, createdAt)
- `Project` (id, name, description, createdAt, customerId)

The relation is 1-to-N (one customer, many projects) with cascade delete on the customer.

Configuration is done via the `DATABASE_CONNECTION_STRING` environment variable
(Npgsql / PostgreSQL connection string). When the variable is not set, the API
falls back to an in-memory provider so it can run without external dependencies
(useful for tests and quick local runs).

When using `docker compose`, a PostgreSQL 17 instance is started automatically
and wired to the API via `DATABASE_CONNECTION_STRING`.

## Front-end (React + TypeScript)

A Vite-based SPA in [src/web](src/web) provides full CRUD for customers and
projects against the API.

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

The Bicep stack provisions a Static Web App resource
([infra/azure/modules/staticWebApp.bicep](infra/azure/modules/staticWebApp.bicep))
and the Container App is configured with `CORS_ALLOWED_ORIGINS` pointing
at the SWA URL so the SPA can call the API directly.

The workflow [.github/workflows/deploy-web.yml](.github/workflows/deploy-web.yml)
builds the SPA with `VITE_API_BASE_URL` set to the deployed API URL and
pushes the artifact to the Static Web App. It expects the following
repository / environment variables:

- `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` (OIDC)
- `AZURE_RESOURCE_GROUP`
- `AZURE_STATIC_WEB_APP_NAME` — the SWA resource name (e.g. `<prefix>-web`)

## Repository essentials

- `.gitignore` for .NET and local tooling artifacts
- `.github/workflows/ci.yml` for GitHub Actions

## Documentation

Operational documentation and the editorial pre-merge checklist are available in [docs/README.md](docs/README.md).

## Azure infrastructure

Azure IaC documentation is available in [infra/azure/README.md](infra/azure/README.md).

Automated Azure deployment is available in [.github/workflows/deploy-azure.yml](.github/workflows/deploy-azure.yml).

The stack provisions a PostgreSQL Flexible Server and an Azure Key Vault.
The database connection string is stored as a secret named
`database-connection-string` in the vault. The Container App references it
through a Key Vault secret reference (using the User-Assigned Managed Identity
with the _Key Vault Secrets User_ role) and exposes it to the application as
the `DATABASE_CONNECTION_STRING` environment variable.

The Postgres administrator password is provided to the deployment via the
`DB_ADMIN_PASSWORD` environment variable, which the workflow reads from the
`DB_ADMIN_PASSWORD` GitHub secret.
