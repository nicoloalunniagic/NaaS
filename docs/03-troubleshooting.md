# Troubleshooting

> English version: [Troubleshooting](./en/03-troubleshooting.md)

## La porta 8000 e' occupata

Sintomo: errore di bind o porta gia' in uso.

Soluzioni:

1. Ferma il processo che usa la porta 8000
2. Oppure cambia mapping porte nel compose, ad esempio:

```yaml
ports:
  - '8080:8000'
```

Nota: con Azurite attivo serve anche la porta `10000`.

## Il container non parte

Controlla i log:

```bash
docker compose -f docker/docker-compose.yml logs -f
```

Verifica anche:

- Docker Desktop avviato
- Build context corretto (context: ..)
- Dockerfile path corretto (docker/Dockerfile)

## Errore "No valid combination of account information found"

Sintomo: il container API va in crash all'avvio con `System.FormatException` dal client Blob.

Cause comuni:

- `AZURE_STORAGE_CONNECTION_STRING` malformata
- account/key usati in `naas` non allineati con `AZURITE_ACCOUNTS`

Verifica rapida:

```bash
docker compose -f docker/docker-compose.yml ps
docker compose -f docker/docker-compose.yml logs azurite
```

## Upload risponde 503 Storage is not configured

Verifica che sia impostata una tra:

- `AZURE_STORAGE_CONNECTION_STRING` (locale/Azurite)
- `AZURE_STORAGE_ACCOUNT_NAME` (Azure reale con managed identity)

In locale con Docker Compose e' usata la connection string verso Azurite.

## Endpoint clienti/progetti rispondono 401

Causa tipica: token JWT mancante o non valido.

Verifica:

1. Esegui login su `/auth/login`
2. Includi header `Authorization: Bearer <token>`
3. Verifica che `JWT_SIGNING_KEY` sia coerente tra deploy e runtime

## Errore su JWT_SIGNING_KEY mancante in deploy Azure

Se `dev.bicepparam` usa `readEnvironmentVariable('JWT_SIGNING_KEY')`, il deploy fallisce se variabile non e' disponibile nel processo che compila Bicep.

Con GitHub Actions imposta secret environment `dev`:

- `JWT_SIGNING_KEY`
- `DB_ADMIN_PASSWORD`

## Modifiche al codice non visibili

Con la configurazione attuale il codice viene copiato nell'immagine durante la build.
Dopo modifiche a `src`, ricostruisci:

```bash
docker compose -f docker/docker-compose.yml up --build
```

## Il comando dotnet non esiste in locale

Installa .NET 10 SDK (preview) se vuoi eseguire l'app fuori da Docker.
Se usi solo Docker, non e' necessario averlo installato sulla macchina host.

## Errore durante restore o publish

Se aggiungi o aggiorni dipendenze NuGet, ricostruisci immagine senza cache:

```bash
docker compose -f docker/docker-compose.yml build --no-cache
```
