# Overview Progetto

> English version: [Project Overview](./en/00-overview.md)

## Obiettivo

No-as-a-Service e' una micro API .NET che restituisce rifiuti casuali, generici, creativi e talvolta esilaranti.

## Stack

- .NET 10 (preview)
- ASP.NET Core Minimal API
- Swagger / OpenAPI
- Docker + Docker Compose

## Struttura minima

```text
webapp/
  src/
    NoAsAService.Api/
      NoAsAService.Api.csproj
      Program.cs
      static/
    tests/
      NoAsAService.Api.Tests/
        NoAsAService.Api.Tests.csproj
  docker/
    Dockerfile
    docker-compose.yml
    Dockerfile.dockerignore
  docs/
```

## Comportamento del servizio

- Endpoint `/` con informazioni di base sul servizio
- Endpoint `/reject` che risponde con `approved=false` e una motivazione casuale
- Documentazione Swagger UI disponibile su `/docs`

## Note importanti

- Il nome `naas` nel compose e' solo il nome del servizio Docker
- La porta esposta e' 8000
