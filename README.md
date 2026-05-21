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
- GitHub Actions CI: docs link check, build and test, Bicep validation, and Terraform validation

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

The unified workflow [.github/workflows/deploy.yml](.github/workflows/deploy.yml)
handles infrastructure provisioning, API image rollout, and SPA publish in
one dispatch. It builds the SPA with `VITE_API_BASE_URL` set to the
deployed API URL and pushes the artifact to the Static Web App.

The workflow discovers Static Web App and Container App resources directly
from the resource group; no explicit resource name variable is required.
See the [Azure infrastructure](#azure-infrastructure) section for the full
variable reference.

## Repository essentials

- `.gitignore` for .NET and local tooling artifacts
- `.github/workflows/ci.yml` — four jobs: docs link check, build and test, Bicep validation (`bicep-validate`), and Terraform validation (`terraform-validate`, covers both topologies)

## Documentation

Operational documentation and the editorial pre-merge checklist are available in [docs/README.md](docs/README.md).

## Azure infrastructure

Two network topologies are available: **public** (open endpoints) and **private** (hub-and-spoke VNet with private endpoints).

Infrastructure detail by topology:

- Public topology — [infra/public/bicep/README.md](infra/public/bicep/README.md)
- Private topology — [infra/private/bicep/README.md](infra/private/bicep/README.md)

Terraform mirrors the Bicep topology in each case; see the Bicep README for the canonical infrastructure description.

Automated deployment is available via the single unified workflow [.github/workflows/deploy.yml](.github/workflows/deploy.yml).

### Workflow inputs

| Input        | Values                 | Default                                            |
| ------------ | ---------------------- | -------------------------------------------------- |
| `topology`   | `public` \| `private`  | `public`                                           |
| `infra_tool` | `bicep` \| `terraform` | `bicep`                                            |
| `skip_infra` | `true` \| `false`      | `false` — fast path: skip infra, update image only |
| `skip_smoke` | `true` \| `false`      | `false`                                            |

Each topology+tool combination deploys into a dedicated resource group. The group name is `AZURE_RESOURCE_GROUP` suffixed with `-pb` (public Bicep), `-pt` (public Terraform), `-xb` (private Bicep), or `-xt` (private Terraform).

### Required repository / environment variables

**Required:**

- `AZURE_CLIENT_ID` — service principal client ID for OIDC
- `AZURE_TENANT_ID` — Azure AD tenant ID
- `AZURE_SUBSCRIPTION_ID` — target subscription
- `AZURE_RESOURCE_GROUP` — base resource group name (see suffix logic above)
- `AZURE_NAME_PREFIX` — base name prefix (keep short; combined with run number and a two-char topology+tool code, total effective prefix must stay ≤ 12 chars)
- `AZURE_PRIMARY_LOCATION` — Azure region for Container Apps and PostgreSQL
- `AZURE_SWA_LOCATION` — Azure region for the Static Web App

**Optional (workflow falls back to defaults if unset):**

- `AZURE_POSTGRES_LOCATION` — override PostgreSQL region (defaults to `AZURE_PRIMARY_LOCATION`)
- `AZURE_STATIC_WEB_APP_LOCATION` — override SWA region (defaults to `AZURE_SWA_LOCATION`)
- `AZURE_STATIC_WEB_APP_SKU` — SWA SKU (defaults to `Free`)

**Secrets (set in GitHub environment secrets, not variables):**

- `DB_ADMIN_PASSWORD`
- `JWT_SIGNING_KEY`

### Secret handling

The stack provisions a PostgreSQL Flexible Server and an Azure Key Vault. Bicep (both topologies) and public Terraform seed `database-connection-string` and `jwt-signing-key` into Key Vault and reference them via Container App Key Vault secret references using the User-Assigned Managed Identity. Private Terraform cannot seed secrets because the Key Vault data plane is unreachable from GitHub-hosted runners when public network access is disabled; in that topology the Container App receives secret values directly.
