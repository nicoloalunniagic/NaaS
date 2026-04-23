# No-as-a-Service

Tiny ASP.NET Core API on .NET 10 with Docker support.

## What is included

- Minimal HTTP API
- OpenAPI JSON at `/openapi/v1.json`
- Swagger UI at `/docs`
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
- OpenAPI: `http://localhost:8000/openapi/v1.json`
- Swagger UI: `http://localhost:8000/docs`

## Repository essentials

- `.gitignore` for .NET and local tooling artifacts
- `.github/workflows/ci.yml` for GitHub Actions

## Documentation

Operational documentation and the editorial pre-merge checklist are available in [docs/README.md](docs/README.md).

## Azure infrastructure

Azure IaC documentation is available in [infra/azure/README.md](infra/azure/README.md).

Automated Azure deployment is available in [.github/workflows/deploy-azure.yml](.github/workflows/deploy-azure.yml).
