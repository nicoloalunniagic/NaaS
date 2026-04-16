# Troubleshooting

> Versione italiana: [Troubleshooting](../03-troubleshooting.md)

## Port 8000 is already in use

Symptom: bind error or port already allocated.

Solutions:

1. Stop the process currently using port 8000
2. Or change port mapping in compose, for example:

```yaml
ports:
  - "8080:8000"
```

## Container does not start

Check logs:

```bash
docker compose -f docker/docker-compose.yml logs -f
```

Also verify:

- Docker Desktop is running
- Build context is correct (context: ..)
- Dockerfile path is correct (docker/Dockerfile)

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
