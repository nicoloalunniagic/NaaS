# Postman Desktop Import

This folder contains files directly importable by Postman Desktop/Web:

- `No-as-a-Service.postman_collection.json`
- `Local.postman_environment.json`
- `Dev.postman_environment.json`
- `LocalDotnet.postman_environment.json`

Import options:

1. Import the whole `postman` folder.
2. Or import the JSON files individually.

After import:

1. Select `Local` for localhost usage, or `Dev` for deployed Azure usage.
2. For `dotnet run` without Docker, select `LocalDotnet` (base URL `http://localhost:5000`).
3. In `Dev`, set `baseUrl` to your real API URL (replace `https://<dev-api-url>`).
4. Run `Auth -> Login`; if needed it auto-registers the configured user, then stores JWT into `authToken` automatically.
5. Run protected requests (`/customers`, `/projects`, `POST /upload`) only after login.
