# Project Overview

> Italian version: [Overview Progetto](../00-overview.md)

## Goal

No-as-a-Service is a tiny .NET API that returns random, generic, creative, and sometimes hilarious rejection reasons.

## Stack

- .NET 10 (preview)
- ASP.NET Core Minimal API
- Swagger / OpenAPI
- JWT authentication (register/login)
- Azure Blob Storage (file upload)
- Docker + Docker Compose
- React + TypeScript (Vite) — front-end SPA

## Minimal Structure

```text
src/
  NoAsAService.Api/
    NoAsAService.Api.csproj
    Program.cs
    static/
  tests/
    NoAsAService.Api.Tests/
      NoAsAService.Api.Tests.csproj
  web/
    package.json
    vite.config.ts
    src/
docker/
  Dockerfile
  docker-compose.yml
  Dockerfile.dockerignore
docs/
```

## Service Behavior

- Root endpoint with basic service information
- Reject endpoint that returns approved=false and a random reason
- `/auth/register` endpoint to register users
- `/auth/login` endpoint to issue JWT tokens
- `GET /upload` endpoint serving an HTML page to select one or more files
- `POST /upload` endpoint uploading files to Blob Storage (50 MB per file limit, JWT required)
- `/customers` and `/projects` endpoints protected by JWT
- Swagger UI documentation exposed at /docs

## Important Notes

- naas in compose is only the Docker service name
- Compose also runs `azurite` to emulate Blob Storage locally
- Compose also runs `postgres` (`postgres:16-alpine`) for local database
- Exposed port is 8000
