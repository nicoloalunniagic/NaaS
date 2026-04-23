# Riferimento API

> English version: [API Reference](./en/02-api-reference.md)

Base URL locale: http://localhost:8000

## GET /

Restituisce i metadati del servizio.

### Esempio risposta 200

```json
{
  "service": "no-as-a-service",
  "message": "Ask nicely and get creatively rejected."
}
```

## GET /reject

Restituisce un rifiuto casuale.

### Esempio risposta 200

```json
{
  "approved": false,
  "reason": "Denied: Mercury is in retrograde and so is this request."
}
```

## Errori

Con l'implementazione attuale non ci sono input utente, quindi non sono previsti errori di validazione applicativa.
Eventuali errori dipendono principalmente da indisponibilita' di runtime o container.

## OpenAPI

L'app ASP.NET Core espone:

- Swagger UI: /docs
- OpenAPI JSON: /openapi/v1.json
