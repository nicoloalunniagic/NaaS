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
dotnet restore src/NoAsAService.Api.csproj
dotnet run --project src/NoAsAService.Api.csproj
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

## Repository essentials added

- `.gitignore` for .NET and local tooling artifacts
- `.github/workflows/ci.yml` for GitHub Actions

## Documentation

Operational docs are in [docs/README.md](docs/README.md).
