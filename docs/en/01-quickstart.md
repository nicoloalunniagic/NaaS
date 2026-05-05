# Docker Quickstart

> Italian version: [Quickstart Docker](../01-quickstart.md)

## Prerequisites

- Docker Desktop installed and running
- Port 8000 available
- Port 10000 available (Azurite Blob endpoint)
- .NET 10 SDK (preview), only if you want to run the project outside Docker

## Quick Start

From the webapp folder:

```bash
docker compose -f docker/docker-compose.yml up --build
```

## Useful Endpoints

- Home: <http://localhost:8000/>
- Reject: <http://localhost:8000/reject>
- Upload UI: <http://localhost:8000/upload>
- Auth register (POST): <http://localhost:8000/auth/register>
- Auth login (POST): <http://localhost:8000/auth/login>
- Swagger UI: <http://localhost:8000/docs>
- OpenAPI JSON: <http://localhost:8000/openapi/v1.json>
- React web app: <http://localhost:5173>

## Web app access

With Docker Compose running:

1. Open <http://localhost:5173>
2. Register a user or login
3. Let the UI store/use JWT automatically
4. Access customers and projects

## Quick local upload test

With Docker Compose running, you can test file upload to Azurite:

```bash
curl -X POST -F "file=@./README.md" http://localhost:8000/upload
```

Expected response: JSON with `status=uploaded`, `blobName`, `blobUrl`.

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
