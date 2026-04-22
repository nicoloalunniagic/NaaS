# Overview Progetto

> English version: [Project Overview](./en/00-overview.md)

## Obiettivo

No-as-a-Service è una micro API .NET che restituisce rifiuti casuali, generici, creativi e talvolta esilaranti.

## Stack

- .NET 10 (preview)
- ASP.NET Core Minimal API
- Swagger / OpenAPI
- Docker + Docker Compose

## Struttura minima

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

## Comportamento del servizio

- Endpoint root con informazioni base del servizio
- Endpoint reject che risponde con approved=false e una reason casuale
- Documentazione Swagger UI disponibile su /docs

## Note importanti

- Il nome naas nel compose e solo il nome del servizio Docker
- La porta esposta e 8000
