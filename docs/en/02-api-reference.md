# API Reference

> Italian version: [Riferimento API](../02-api-reference.md)

Local base URL: http://localhost:8000

## Authentication

Customer/project endpoints and `POST /upload` require JWT.

### POST /auth/register

Registers a user.

Request body:

```json
{
	"username": "devuser",
	"password": "DevPassword123456"
}
```

### POST /auth/login

Logs in and returns a JWT token.

Request body:

```json
{
	"username": "devuser",
	"password": "DevPassword123456"
}
```

200 response example:

```json
{
	"token": "<jwt>",
	"expiresAt": "2026-05-05T10:00:00Z",
	"username": "devuser"
}
```

Required header for protected endpoints:

```text
Authorization: Bearer <token>
```

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

## GET /upload

Returns a simple HTML page to select and upload files.

### 200 Response Example

`text/html` with drag-and-drop/file picker UI.

## POST /upload

Uploads a file to Blob Storage in the configured container (default: `uploads`).

### Request

- Content-Type: `multipart/form-data`
- Required file field: `file`
- Limit: 50 MB per file
- Required header: `Authorization: Bearer <token>`

### 200 Response Example

```json
{
	"status": "uploaded",
	"blobName": "6151a71d455445df9d1d29be08cf76ee-example.txt",
	"blobUrl": "http://azurite:10000/devstoreaccount1/uploads/6151a71d455445df9d1d29be08cf76ee-example.txt"
}
```

### Possible errors

- `400 BadRequest`: missing/empty file or file above size limit
- `401 Unauthorized`: missing or invalid JWT token
- `503 ServiceUnavailable`: storage not configured

## Errors

Upload endpoints can return validation errors (`400`) or storage configuration errors (`503`).
Protected endpoints (`/customers`, `/projects`, `POST /upload`) return `401` if JWT is missing or invalid.

## OpenAPI

The ASP.NET Core app exposes:

- Swagger UI: /docs
- OpenAPI JSON: /openapi/v1.json
