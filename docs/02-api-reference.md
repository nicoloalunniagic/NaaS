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

## GET /upload

Restituisce una pagina HTML semplice per selezionare e caricare file.

### Esempio risposta 200

`text/html` con UI drag-and-drop/file picker.

## POST /upload

Carica un file su Blob Storage nel container configurato (default: `uploads`).

### Request

- Content-Type: `multipart/form-data`
- Campo file richiesto: `file`
- Limite: 50 MB per file

### Esempio risposta 200

```json
{
  "status": "uploaded",
  "blobName": "6151a71d455445df9d1d29be08cf76ee-esempio.txt",
  "blobUrl": "http://azurite:10000/devstoreaccount1/uploads/6151a71d455445df9d1d29be08cf76ee-esempio.txt"
}
```

### Possibili errori

- `400 BadRequest`: file mancante/vuoto o oltre limite
- `503 ServiceUnavailable`: storage non configurato

## Errori

Gli endpoint di upload possono restituire errori di validazione (`400`) o di configurazione storage (`503`).
Gli altri endpoint dipendono principalmente dalla disponibilita' runtime/container.

## OpenAPI

L'app ASP.NET Core espone:

- Swagger UI: /docs
- OpenAPI JSON: /openapi/v1.json
