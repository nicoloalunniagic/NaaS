# Postman Desktop Import

This folder contains files directly importable by Postman Desktop/Web:

- `No-as-a-Service.postman_collection.json`
- `Local.postman_environment.json`
- `Dev.postman_environment.json`

Import options:

1. Import the whole `postman` folder.
2. Or import the JSON files individually.

After import:

1. Select `Local` for localhost usage, or `Dev` for deployed Azure usage.
2. In `Dev`, set `baseUrl` to your real API URL (replace `https://<dev-api-url>`).
3. Run `Auth -> Login`; the login test script stores JWT into `authToken` automatically.
