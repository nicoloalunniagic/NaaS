# Troubleshooting

> English version: [Troubleshooting](./en/03-troubleshooting.md)

## La porta 8000 e occupata

Sintomo: errore bind o porta gia in uso.

Soluzioni:

1. Ferma il processo che usa la porta 8000
2. Oppure cambia mapping porte nel compose, ad esempio:

```yaml
ports:
  - "8080:8000"
```

## Il container non parte

Controlla i log:

```bash
docker compose -f docker/docker-compose.yml logs -f
```

Verifica anche:

- Docker Desktop avviato
- Build context corretto (context: ..)
- Dockerfile path corretto (docker/Dockerfile)

## Modifiche al codice non visibili

Con la configurazione attuale il codice viene copiato in build image.
Dopo modifiche a src, ricostruisci:

```bash
docker compose -f docker/docker-compose.yml up --build
```

## Il comando dotnet non esiste in locale

Installa .NET 10 SDK (preview) se vuoi eseguire l'app fuori da Docker.
Se usi solo Docker, non e necessario averlo installato sulla macchina host.

## Errore durante restore o publish

Se aggiungi o aggiorni dipendenze NuGet, ricostruisci immagine senza cache:

```bash
docker compose -f docker/docker-compose.yml build --no-cache
```
