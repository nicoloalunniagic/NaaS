# Overview Progetto

> English version: [Project Overview](./en/00-overview.md)

## Obiettivo

No-as-a-Service e' una micro API .NET che restituisce rifiuti casuali, generici, creativi e talvolta esilaranti.

## Stack

- .NET 10 (preview)
- ASP.NET Core Minimal API
- Swagger / OpenAPI
- JWT authentication (register/login)
- Azure Blob Storage (upload file)
- Docker + Docker Compose
- React + TypeScript (Vite) — SPA front-end

## Struttura minima

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

## Comportamento del servizio

- Endpoint `/` con informazioni di base sul servizio
- Endpoint `/reject` che risponde con `approved=false` e una motivazione casuale
- Endpoint `/auth/register` per registrare utenti
- Endpoint `/auth/login` per ottenere JWT
- Endpoint `GET /upload` che espone una pagina HTML per selezione file multipli
- Endpoint `POST /upload` che carica file su Blob Storage (limite 50 MB per file, JWT obbligatorio)
- Endpoint `/customers` e `/projects` protetti da JWT
- Documentazione Swagger UI disponibile su `/docs`

## Note importanti

- Il nome `naas` nel compose e' solo il nome del servizio Docker
- Il compose avvia anche `azurite` per emulare Blob Storage in locale
- Il compose avvia anche `postgres` (`postgres:16-alpine`) per database locale
- La porta esposta e' 8000
