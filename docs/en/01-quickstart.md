# Docker Quickstart

> Italian version: [Quickstart Docker](../01-quickstart.md)

## Prerequisites

- Docker Desktop installed and running
- Port 8000 available
- .NET 10 SDK (preview), only if you want to run the project outside Docker

## Quick Start

From the webapp folder:

```bash
docker compose -f docker/docker-compose.yml up --build
```

## Useful Endpoints

- Home: <http://localhost:8000/>
- Reject: <http://localhost:8000/reject>
- Swagger UI: <http://localhost:8000/docs>
- OpenAPI JSON: <http://localhost:8000/openapi/v1.json>

## Stop

In the shell where Compose is running:

```bash
Ctrl+C
```

Or from another shell:

```bash
docker compose -f docker/docker-compose.yml down
```

## Manual Build/Run without Compose

From the webapp folder:

```bash
docker build -f docker/Dockerfile -t naas .
docker run --rm -p 8000:8000 naas
```

## Run Locally without Docker

From the webapp folder:

```bash
dotnet run --project src/NoAsAService.Api/NoAsAService.Api.csproj
```
