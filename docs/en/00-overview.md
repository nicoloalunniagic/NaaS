# Project Overview

> Versione italiana: [Overview Progetto](../00-overview.md)

## Goal

No-as-a-Service is a tiny .NET API that returns random, generic, creative, and sometimes hilarious rejection reasons.

## Stack

- .NET 10 (preview)
- ASP.NET Core Minimal API
- Swagger / OpenAPI
- Docker + Docker Compose

## Minimal Structure

```text
webapp/
  src/
    NoAsAService.Api.csproj
    Program.cs
    static/
  docker/
    Dockerfile
    docker-compose.yml
    Dockerfile.dockerignore
  docs/
```

## Service Behavior

- Root endpoint with basic service info
- Reject endpoint returning approved=false and a random reason
- Swagger UI documentation exposed at /docs

## Important Notes

- naas in compose is only the Docker service name
- Exposed port is 8000
