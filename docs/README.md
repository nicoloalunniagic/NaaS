# Documentazione - No-as-a-Service

> English version: [English README](./en/README.md)

Questa cartella contiene la documentazione operativa del progetto, implementato in .NET.
Include API base, upload file su Blob Storage e workflow locale con Azurite.

## Lingue disponibili

- Italiano: file nella root di `docs`
- Inglese: cartella `en`

## Indice

1. [Overview progetto](./00-overview.md)
2. [Quickstart Docker](./01-quickstart.md)
3. [Riferimento API](./02-api-reference.md)
4. [Troubleshooting](./03-troubleshooting.md)
5. [VAPT Lab Mode](./04-vapt-lab-mode.md)

## Mirror inglese

1. [English index](./en/README.md)
2. [Project overview](./en/00-overview.md)
3. [Docker quickstart](./en/01-quickstart.md)
4. [API reference](./en/02-api-reference.md)
5. [Troubleshooting](./en/03-troubleshooting.md)
6. [VAPT Lab Mode](./en/04-vapt-lab-mode.md)

## A chi serve

- Sviluppatori che vogliono avviare o modificare il servizio
- Chi deve integrare l'API in un client
- Chi deve fare debug rapido in locale
- Chi deve testare upload file end-to-end su storage locale/emulato

## Checklist editoriale pre-merge

Usa questa checklist per ogni modifica documentale prima di aprire o aggiornare una PR.

1. Correttezza tecnica: comandi, path, porte, endpoint e nomi file sono verificati.
2. Coerenza linguistica: stile impersonale, frasi brevi e terminologia uniforme.
3. Coerenza IT/EN: se un contenuto cambia in italiano, aggiorna anche il mirror inglese.
4. Eseguibilita': ogni comando puo' essere copiato ed eseguito senza modifiche inattese.
5. Struttura: titoli e sezioni seguono il formato del repository (overview, quickstart, API, troubleshooting).
6. Ambito: niente dettagli fuori scope della pagina; usa link verso il documento corretto.
7. Sicurezza: nessun segreto, token o identificatore sensibile nella documentazione.

Checklist rapida di uscita:

- Ho verificato almeno una volta i comandi principali riportati.
- Ho aggiornato i link interni e non ci sono riferimenti obsoleti.
- Ho allineato eventuali modifiche nei file in `docs/en`.
