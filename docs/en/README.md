# Documentation - No-as-a-Service

> Italian version: [README in Italian](../README.md)

This folder contains the English mirror of the project documentation for the current .NET implementation.

## Index

1. [Project Overview](./00-overview.md)
2. [Docker Quickstart](./01-quickstart.md)
3. [API Reference](./02-api-reference.md)
4. [Troubleshooting](./03-troubleshooting.md)

## Target Audience

- Developers who want to run or modify the service
- People integrating the API into a client
- Anyone doing quick local debugging

## Pre-merge editorial checklist

Use this checklist for every documentation change before opening or updating a PR.

1. Technical accuracy: commands, paths, ports, endpoints, and file names are verified.
2. Language consistency: neutral tone, short sentences, and consistent terminology.
3. IT/EN parity: when Italian content changes, update the English mirror as well.
4. Executability: each command can be copied and run without unexpected edits.
5. Structure: headings and sections follow repository conventions (overview, quickstart, API, troubleshooting).
6. Scope: avoid off-topic details and link to the appropriate document.
7. Security: no secrets, tokens, or sensitive identifiers in docs.

Quick exit checks:

- Main commands were sanity-checked at least once.
- Internal links were updated and no stale references remain.
- Matching updates were applied in the corresponding `docs` or `docs/en` files.
