# Infrastruttura Azure per No-as-a-Service

Questa cartella contiene Infrastructure-as-Code per distribuire la web app su Azure usando Bicep.

## Struttura

- `main.bicep`: entry point di orchestrazione
- `foundation.bicep`: risorse condivise/base
- `modules/containerRegistry.bicep`: modulo ACR
- `modules/containerApp.bicep`: modulo Azure Container App
- `modules/blobStorage.bicep`: modulo Storage Account + container blob + RBAC upload
- `modules/appInsights.bicep`: modulo opzionale Application Insights
- `dev.bicepparam`: set parametri ambiente Azure usato dal workflow GitHub (`environment: dev`)

## Standard di modularizzazione Bicep

Usa `main.bicep` solo come orchestratore. Mantieni le definizioni delle risorse Azure all'interno di moduli dedicati.

Principi:

- Un modulo = una capability (registry, runtime app, observability, networking)
- `main.bicep` deve contenere solo parametri, tag condivisi, chiamate ai moduli e wiring
- I moduli devono esporre contratti input/output minimi
- Le differenze tra ambienti devono stare nei file `.bicepparam`, non essere hardcoded nei moduli
- Preferisci modifiche additive nei moduli per ridurre il blast radius del deploy

Convenzioni di naming:

- Nomi file modulo: `camelCase` per capability (esempio `containerApp.bicep`)
- Nomi istanza modulo in `main.bicep`: `mdl<Capability>` (esempio `mdlContainerApp`)
- Output: nomi espliciti e stabili (esempio `containerAppUrl`, `containerRegistryLoginServer`)
- I prefissi dei nomi delle risorse devono arrivare dai parametri (`namePrefix`) ed essere compatibili con l'ambiente

Quando creare un nuovo modulo:

- Il blocco risorse cresce oltre una responsabilita' semplice
- Lo stesso pattern di risorse e' previsto come riutilizzabile
- Il ciclo di vita o la frequenza di modifica differiscono dalle risorse circostanti
- Ownership e review sono divise tra aree del team

Forma consigliata del contratto modulo:

- Input: `location`, `namePrefix`, `tags`, poi parametri specifici della capability
- Output: `id`, `name` e solo endpoint/identificatori consumati all'esterno

## Checklist pull request (infra)

- `main.bicep` orchestra, i moduli implementano
- Nessun valore ambiente-specifico codificato in modo statico nei moduli
- I nomi degli output sono stabili e significativi
- I tag sono applicati in modo coerente
- `dev.bicepparam` resta valido e allineato al workflow GitHub
- Le assunzioni su deployment mode sono documentate quando cambiano

## Cosa viene distribuito

- Azure Container Registry (ACR) Basic (singola regione, nessuna geo-replicazione)
- Azure Log Analytics Workspace
- Azure Container Apps Environment (single-zone, zone redundancy disabilitata per default)
- Azure Container App (ingress pubblico su porta 8000)
- Managed identity user-assigned per il pull delle immagini da ACR
- Assegnazione RBAC: AcrPull su ACR alla managed identity
- Azure Storage Account (Blob) Standard_LRS con container `uploads`
- Assegnazione RBAC: Storage Blob Data Contributor alla managed identity dell'app

## Integrazione upload app -> blob

Il deploy Bicep passa alla Container App le variabili ambiente per lo storage:

- `AZURE_STORAGE_ACCOUNT_NAME`
- `AZURE_STORAGE_CONTAINER_NAME`
- `AZURE_CLIENT_ID`

L'app usa `DefaultAzureCredential` in Azure e la managed identity per autenticarsi su Blob.

## Parametri disponibili

I file `.bicepparam` controllano il comportamento del deploy:

| Parametro                 | Tipo   | Default                    | Descrizione                                                       |
| ------------------------- | ------ | -------------------------- | ----------------------------------------------------------------- |
| `location`                | string | `resourceGroup().location` | Regione Azure (es. `westeurope`)                                  |
| `postgresLocation`        | string | `location`                 | Regione PostgreSQL (es. `francecentral` se `westeurope` bloccata) |
| `namePrefix`              | string | -                          | Prefisso per nomi risorse (3-12 caratteri)                        |
| `containerImage`          | string | -                          | URI immagine container (es. `registry.azurecr.io/app:latest`)     |
| `containerCpu`            | string | `'0.5'`                    | CPU cores: `'0.25'`, `'0.5'`, `'1.0'`, `'2.0'`                    |
| `containerMemory`         | string | `'1.0Gi'`                  | RAM: `'0.5Gi'`, `'1.0Gi'`, `'2.0Gi'`, `'4.0Gi'`                   |
| `minReplicas`             | int    | `1`                        | Replica minime Container App (0-10)                               |
| `maxReplicas`             | int    | `3`                        | Replica massime Container App (1-20)                              |
| `enableZoneRedundancy`    | bool   | `false`                    | Abilita zone redundancy CAE (richiede subnet infrastruttura)      |
| `dbAdministratorLogin`    | string | `'naasadmin'`              | Username admin PostgreSQL                                         |
| `dbAdministratorPassword` | secure | -                          | Password admin PostgreSQL (`DB_ADMIN_PASSWORD`)                   |
| `dbName`                  | string | `'naas'`                   | Nome database applicativo                                         |
| `jwtSigningKey`           | secure | -                          | Chiave usata per firmare i JWT (`JWT_SIGNING_KEY`)                |

## Prerequisiti

- Azure CLI installata
- Login effettuato con `az login`
- Subscription selezionata con `az account set --subscription <SUBSCRIPTION_ID>`

## Deploy infrastruttura

```bash
az deployment group create \
  --resource-group rg-naas-b \
  --parameters infra/bicep/dev.bicepparam
```

## Build e push immagine su ACR

Usa l'output `containerRegistryLoginServer` del deploy.

```bash
az acr login --name <ACR_NAME>

docker build -f docker/Dockerfile -t <ACR_LOGIN_SERVER>/naas:latest .
docker push <ACR_LOGIN_SERVER>/naas:latest
```

Poi riesegui il deploy Bicep con `containerImage` puntato al tag pubblicato.

## Deploy automatizzato con GitHub Actions

File workflow: [.github/workflows/deploy-public.yml](../../.github/workflows/deploy-public.yml)

Il workflow unificato gestisce in un'unica dispatch: provisioning infra, rollout immagine API e pubblicazione SPA.
Al momento del dispatch si sceglie `infra_tool = bicep` (default) o `terraform`.

Il nome prefix e il resource group vengono derivati automaticamente con un suffisso IaC:

- Bicep: prefix `<AZURE_NAME_PREFIX>b`, resource group `<AZURE_RESOURCE_GROUP>-b`
- Terraform: prefix `<AZURE_NAME_PREFIX>t`, resource group `<AZURE_RESOURCE_GROUP>-t`

Variabili repository richieste (non segreti):

- `AZURE_CLIENT_ID`: Client ID dell'applicazione Entra o managed identity user-assigned associata alla credenziale federata
- `AZURE_TENANT_ID`: tenant ID Azure Entra
- `AZURE_SUBSCRIPTION_ID`: subscription Azure di destinazione
- `AZURE_RESOURCE_GROUP`: nome base del resource group (suffisso aggiunto dal workflow)
- `AZURE_LOCATION`: regione Azure default (esempio: westeurope, eastus)
- `AZURE_NAME_PREFIX`: prefisso base per i nomi risorsa Azure (lowercase, 3-11 caratteri; il workflow aggiunge il suffisso IaC)
- `AZURE_CORE_LOCATION` _(opzionale)_: regione alternativa per Container Apps e PostgreSQL — utile quando `AZURE_LOCATION` ha problemi di capacita'
- `AZURE_POSTGRES_LOCATION` _(opzionale)_: regione specifica per PostgreSQL Flexible Server
- `AZURE_STATIC_WEB_APP_LOCATION` _(opzionale)_: regione per Static Web App
- `AZURE_STATIC_WEB_APP_SKU` _(opzionale)_: SKU Static Web App (`Free` default)

RBAC Azure richiesto per l'identita' federata:

- `Contributor` sul resource group di destinazione (per creare RG e fare deploy Bicep)
- `AcrPush` sull'Azure Container Registry di destinazione (per pubblicare immagini)

Serve anche una credenziale federata in Azure Entra ID che si fidi del repository/branch o environment GitHub che esegue il workflow.

Il workflow fa le seguenti operazioni:

- Calcola prefix e resource group effettivi in base all'`infra_tool` scelto
- Esegue login su Azure con OIDC (`azure/login`)
- Crea il resource group se necessario
- Usa `infra/bicep/dev.bicepparam` (Bicep) o variabili TF (Terraform) con `deployStaticWebApp=false`
- Esegue deploy infra core senza SWA (skipbabile con `skip_infra=true`)
- Esegue build e push dell'immagine app su ACR con tag derivato dal commit SHA
- Aggiorna la Container App con la nuova immagine
- Esegue provisioning SWA con lo stesso tool IaC scelto
- Pubblica la SPA compilata sulla Static Web App

## Note di sicurezza

- `adminUserEnabled` e' disabilitato su ACR
- Il pull immagine del container usa managed identity, non password del registry
- I log sono centralizzati in Log Analytics
- Le probe di liveness/readiness puntano a `/`

## Idee di hardening opzionali (non applicate di default)

- Aggiungere custom domain e certificato per la Container App
- Restringere l'ingress con allowlist IP o usare Azure Front Door/WAF
- Spostare i parametri in file ambiente-specifici (dev/test/prod) se il progetto cresce oltre il contesto esercitazione
- Aggiungere vulnerability scanning in CI prima del push
