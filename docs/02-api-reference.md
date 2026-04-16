# Riferimento API

> English version: [API Reference](./en/02-api-reference.md)

Base URL locale: http://localhost:8000

## GET /

Ritorna metadati del servizio.

### Esempio risposta 200

```json
{
  "service": "no-as-a-service",
  "message": "Ask nicely and get creatively rejected."
}
```

## GET /reject

Ritorna un rifiuto casuale.

### Esempio risposta 200

```json
{
  "approved": false,
  "reason": "Denied: Mercury is in retrograde and so is this request."
}
```

## Errori

Con l'implementazione attuale non ci sono input utente, quindi non sono previsti errori di validazione applicativa.
Eventuali errori dipendono principalmente da runtime/container non disponibili.

## OpenAPI

L'app ASP.NET Core espone:

- Swagger UI: /docs
- OpenAPI JSON: /openapi/v1.json
