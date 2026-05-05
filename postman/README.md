# Postman Desktop Import

This folder contains only files directly importable by Postman Desktop/Web:

- `No-as-a-Service.postman_collection.json`
- `Local.postman_environment.json`

Import options:

1. Import the whole `postman` folder.
2. Or import the two JSON files individually.

After import, select the `Local` environment and run `Auth -> Login`.
The login test script automatically stores the JWT in `authToken`.
