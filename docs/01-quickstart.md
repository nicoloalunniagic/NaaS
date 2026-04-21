# Quickstart Docker

> English version: [Docker Quickstart](./en/01-quickstart.md)

## Prerequisiti

- Docker Desktop installato e in esecuzione
- Porta 8000 libera
- SDK .NET 10 (preview) installato solo se vuoi eseguire il progetto fuori da Docker

## Avvio rapido

Dalla cartella webapp:

```bash
docker compose -f docker/docker-compose.yml up --build
```

## Endpoint utili

- Home: http://localhost:8000/
- Reject: http://localhost:8000/reject
- Swagger UI: http://localhost:8000/docs
- OpenAPI JSON: http://localhost:8000/openapi/v1.json

## Stop

Nella shell dove gira Compose:

```bash
Ctrl+C
```

Oppure da un'altra shell:

```bash
docker compose -f docker/docker-compose.yml down
```

## Build/Run manuale senza Compose

Dalla cartella webapp:

```bash
docker build -f docker/Dockerfile -t noaas .
docker run --rm -p 8000:8000 noaas
```

## Esecuzione locale senza Docker

Dalla cartella webapp:

```bash
dotnet run --project src/NoAsAService.Api/NoAsAService.Api.csproj
```
