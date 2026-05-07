# Troubleshooting

> Italian version: [Troubleshooting](../03-troubleshooting.md)

## Port 8000 is already in use

Symptom: bind error or port already allocated.

Solutions:

1. Stop the process currently using port 8000
2. Or change port mapping in compose, for example:

```yaml
ports:
  - '8080:8000'
```

Note: with Azurite enabled, port `10000` must also be available.

## Container does not start

Check logs:

```bash
docker compose -f docker/docker-compose.yml logs -f
```

Also verify:

- Docker Desktop is running
- Build context is correct (context: ..)
- Dockerfile path is correct (docker/Dockerfile)

## Error "No valid combination of account information found"

Symptom: API container crashes on startup with `System.FormatException` from the Blob client.

Common causes:

- malformed `AZURE_STORAGE_CONNECTION_STRING`
- account/key mismatch between `naas` and `AZURITE_ACCOUNTS`

Quick check:

```bash
docker compose -f docker/docker-compose.yml ps
docker compose -f docker/docker-compose.yml logs azurite
```

## Upload returns 503 Storage is not configured

Verify at least one of these is configured:

- `AZURE_STORAGE_CONNECTION_STRING` (local/Azurite)
- `AZURE_STORAGE_ACCOUNT_NAME` (real Azure with managed identity)

In local Docker Compose, the Azurite connection string is used.

## Customers/projects endpoints return 401

Typical cause: missing or invalid JWT token.

Note: `POST /upload` is also protected and returns `401` without a valid bearer token.

Check:

1. Login via `/auth/login`
2. Send `Authorization: Bearer <token>`
3. Ensure `JWT_SIGNING_KEY` is consistent between deployment and runtime

## Test error: external PostgreSQL connection or DNS failure

Symptom: `dotnet test` shows connection failures to external DB hosts
(for example Azure PostgreSQL hostnames).

Typical cause: development environment variables or user-secrets leaking into
the test runtime.

Check:

1. Run tests without forcing `ASPNETCORE_ENVIRONMENT=Development`
2. Ensure tests run in `Testing` environment
3. Remove `DATABASE_CONNECTION_STRING` overrides in the test runner

Note: in `Testing`, the API uses an in-memory DB and should not contact PostgreSQL.

## Relational schema changes are not applied

The app applies EF Core migrations (`Database.Migrate`) at startup.

Check:

1. Migrations exist in `src/NoAsAService.Api/Data/Migrations`
2. Database user has required DDL permissions
3. `DATABASE_CONNECTION_STRING` points to the expected database

## Azure deploy fails with missing JWT_SIGNING_KEY

If `dev.bicepparam` uses `readEnvironmentVariable('JWT_SIGNING_KEY')`, deployment fails when the variable is not available in the Bicep process environment.

For GitHub Actions, set environment `dev` secrets:

- `JWT_SIGNING_KEY`
- `DB_ADMIN_PASSWORD`

## Code changes are not visible

With the current setup, source code is copied into the image at build time.
After changing src, rebuild:

```bash
docker compose -f docker/docker-compose.yml up --build
```

## dotnet command is missing locally

Install the .NET 10 SDK (preview) if you want to run the app outside Docker.
If you use Docker only, you do not need it on the host machine.

## Restore or publish fails

If you add or update NuGet packages, rebuild the image without cache:

```bash
docker compose -f docker/docker-compose.yml build --no-cache
```
