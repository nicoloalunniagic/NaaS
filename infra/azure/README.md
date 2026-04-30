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

| Parametro              | Tipo   | Default                    | Descrizione                                                   |
| ---------------------- | ------ | -------------------------- | ------------------------------------------------------------- |
| `location`             | string | `resourceGroup().location` | Regione Azure (es. `westeurope`)                              |
| `namePrefix`           | string | -                          | Prefisso per nomi risorse (3-12 caratteri)                    |
| `containerImage`       | string | -                          | URI immagine container (es. `registry.azurecr.io/app:latest`) |
| `containerCpu`         | string | `'0.5'`                    | CPU cores: `'0.25'`, `'0.5'`, `'1.0'`, `'2.0'`                |
| `containerMemory`      | string | `'1.0Gi'`                  | RAM: `'0.5Gi'`, `'1.0Gi'`, `'2.0Gi'`, `'4.0Gi'`               |
| `minReplicas`          | int    | `1`                        | Replica minime Container App (0-10)                           |
| `maxReplicas`          | int    | `3`                        | Replica massime Container App (1-20)                          |
| `deployAppInsights`    | bool   | `false`                    | Abilita Application Insights (aggiuntivo)                     |
| `enableZoneRedundancy` | bool   | `false`                    | Abilita zone redundancy CAE (richiede subnet infrastruttura)  |
| `jwtSigningKey`        | secure | -                          | Chiave usata per firmare i JWT (`JWT_SIGNING_KEY`)            |

## Prerequisiti

- Azure CLI installata
- Login effettuato con `az login`
- Subscription selezionata con `az account set --subscription <SUBSCRIPTION_ID>`

## Deploy infrastruttura

```bash
az deployment group create \
  --resource-group rg-naas-dev \
  --parameters infra/azure/dev.bicepparam
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

File workflow: [.github/workflows/deploy-azure.yml](../../.github/workflows/deploy-azure.yml)

Il workflow usa la federazione OIDC di GitHub tramite `azure/login@v2` per autenticarsi su Azure da `ubuntu-latest`.

Variabili repository richieste (non segreti):

- `AZURE_CLIENT_ID`: Client ID dell'applicazione Entra o managed identity user-assigned associata alla credenziale federata
- `AZURE_TENANT_ID`: tenant ID Azure Entra
- `AZURE_SUBSCRIPTION_ID`: subscription Azure di destinazione
- `AZURE_RESOURCE_GROUP`: nome del resource group di destinazione
- `AZURE_LOCATION`: regione Azure (esempio: westeurope, eastus)
- `AZURE_NAME_PREFIX`: prefisso per i nomi risorsa Azure (lowercase, 3-12 caratteri)

RBAC Azure richiesto per l'identita' federata:

- `Contributor` sul resource group di destinazione (per creare RG e fare deploy Bicep)
- `AcrPush` sull'Azure Container Registry di destinazione (per pubblicare immagini)

Serve anche una credenziale federata in Azure Entra ID che si fidi del repository/branch o environment GitHub che esegue il workflow.

Il workflow fa le seguenti operazioni:

- Esegue login su Azure con OIDC (`azure/login`)
- Crea il resource group se necessario
- Usa sempre `infra/azure/dev.bicepparam` (allineato all'environment GitHub `dev`)
- Esegue deploy con un'immagine bootstrap temporanea
- Esegue build e push dell'immagine app su ACR con tag derivato dal commit SHA
- Riesegue il deploy Bicep con l'immagine pubblicata

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
