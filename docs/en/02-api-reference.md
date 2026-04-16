# API Reference

> Versione italiana: [Riferimento API](../02-api-reference.md)

Local base URL: http://localhost:8000

## GET /

Returns service metadata.

### 200 Response Example

```json
{
  "service": "no-as-a-service",
  "message": "Ask nicely and get creatively rejected."
}
```

## GET /reject

Returns a random rejection reason.

### 200 Response Example

```json
{
  "approved": false,
  "reason": "Denied: Mercury is in retrograde and so is this request."
}
```

## Errors

With the current implementation there is no user input, so application-level validation errors are not expected.
Any errors are mostly related to runtime/container availability.

## OpenAPI

The ASP.NET Core app exposes:

- Swagger UI: /docs
- OpenAPI JSON: /openapi/v1.json
