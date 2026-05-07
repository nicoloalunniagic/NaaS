# Quickstart Docker

> English version: [Docker Quickstart](./en/01-quickstart.md)

## Prerequisiti

- Docker Desktop installato e in esecuzione
- Porta 8000 libera
- Porta 10000 libera (Azurite Blob endpoint)
- SDK .NET 10 (preview) installato, solo se vuoi eseguire il progetto fuori da Docker

## Avvio rapido

Dalla cartella webapp:

```bash
docker compose -f docker/docker-compose.yml up --build
```

## Endpoint utili

- Home: <http://localhost:8000/>
- Reject: <http://localhost:8000/reject>
- Upload UI (pagina pubblica): <http://localhost:8000/upload>
- Upload endpoint (POST, JWT richiesto): <http://localhost:8000/upload>
- Auth register (POST): <http://localhost:8000/auth/register>
- Auth login (POST): <http://localhost:8000/auth/login>
- Swagger UI: <http://localhost:8000/docs>
- OpenAPI JSON: <http://localhost:8000/openapi/v1.json>
- Web app React: <http://localhost:5173>

## Accesso web app

Con Docker Compose attivo:

1. Apri <http://localhost:5173>
2. Registra utente o fai login
3. Usa il token JWT generato automaticamente dalla UI
4. Accedi a clienti e progetti

## Test rapido upload locale

Con lo stack Docker attivo, `POST /upload` richiede JWT. Esegui login e poi invia il file:

```bash
curl -X POST http://localhost:8000/auth/register \
	-H "Content-Type: application/json" \
	-d '{"username":"devuser","password":"DevPassword123456"}'

TOKEN=$(curl -sS -X POST http://localhost:8000/auth/login \
	-H "Content-Type: application/json" \
	-d '{"username":"devuser","password":"DevPassword123456"}' \
	| sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

curl -X POST -F "file=@./README.md" \
	-H "Authorization: Bearer $TOKEN" \
	http://localhost:8000/upload
```

Risposta attesa: JSON con `status=uploaded`, `blobName`, `blobUrl`.

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
docker build -f docker/Dockerfile -t naas .
docker run --rm -p 8000:8000 naas
```

## Esecuzione locale senza Docker

Dalla cartella webapp:

```bash
dotnet run --project src/NoAsAService.Api/NoAsAService.Api.csproj
```
