# Azure Infrastructure for No-as-a-Service

This folder contains Infrastructure-as-Code to deploy the web app on Azure using Bicep.

## Structure

- `main.bicep`: orchestration entry point
- `foundation.bicep`: shared/base resources
- `modules/containerRegistry.bicep`: ACR module
- `modules/containerApp.bicep`: Azure Container App module
- `modules/blobStorage.bicep`: Storage Account + blob container + upload RBAC module
- `modules/appInsights.bicep`: optional Application Insights module
- `dev.bicepparam`: Azure environment parameter set used by the GitHub workflow (`environment: dev`)

## Bicep modularisation standards

Use `main.bicep` as the orchestrator only. Keep Azure resource definitions inside dedicated modules.

Principles:

- One module = one capability (registry, app runtime, observability, networking)
- `main.bicep` must contain only parameters, shared tags, module calls, and wiring
- Modules must expose minimal input/output contracts
- Environment differences must live in `.bicepparam` files, not be hardcoded in modules
- Prefer additive changes in modules to reduce the deploy blast radius

Naming conventions:

- Module file names: `camelCase` per capability (e.g. `containerApp.bicep`)
- Module instance names in `main.bicep`: `mdl<Capability>` (e.g. `mdlContainerApp`)
- Outputs: explicit and stable names (e.g. `containerAppUrl`, `containerRegistryLoginServer`)
- Resource name prefixes must come from parameters (`namePrefix`) and be environment-compatible

When to create a new module:

- The resource block grows beyond a single responsibility
- The same resource pattern is expected to be reused
- The lifecycle or change frequency differs from surrounding resources
- Ownership and review are split across team areas

Recommended module contract shape:

- Inputs: `location`, `namePrefix`, `tags`, then capability-specific parameters
- Outputs: `id`, `name`, and only the endpoints/identifiers consumed externally

## Pull request checklist (infra)

- `main.bicep` orchestrates, modules implement
- No environment-specific values statically coded in modules
- Output names are stable and meaningful
- Tags are applied consistently
- `dev.bicepparam` remains valid and aligned with the GitHub workflow
- Deployment mode assumptions are documented when they change

## What is deployed

- Azure Container Registry (ACR) Basic (single region, no geo-replication)
- Azure Log Analytics Workspace
- Azure Container Apps Environment (single-zone, zone redundancy disabled by default)
- Azure Container App (public ingress on port 8000)
- User-assigned managed identity for ACR image pull
- RBAC assignment: AcrPull on ACR to the managed identity
- Azure Storage Account (Blob) Standard_LRS with `uploads` container
- RBAC assignment: Storage Blob Data Contributor to the app managed identity

## App upload → blob integration

The Bicep deploy passes storage environment variables to the Container App:

- `AZURE_STORAGE_ACCOUNT_NAME`
- `AZURE_STORAGE_CONTAINER_NAME`
- `AZURE_CLIENT_ID`

The app uses `DefaultAzureCredential` in Azure and the managed identity to authenticate against Blob.

## Available parameters

The `.bicepparam` files control the deploy behaviour:

| Parameter                 | Type   | Default                    | Description                                                             |
| ------------------------- | ------ | -------------------------- | ----------------------------------------------------------------------- |
| `location`                | string | `resourceGroup().location` | Azure region (e.g. `westeurope`)                                        |
| `postgresLocation`        | string | `location`                 | PostgreSQL region (e.g. `francecentral` if `westeurope` is unavailable) |
| `namePrefix`              | string | -                          | Name prefix for Azure resources (3–12 characters)                       |
| `containerImage`          | string | -                          | Container image URI (e.g. `registry.azurecr.io/app:latest`)             |
| `containerCpu`            | string | `'0.5'`                    | CPU cores: `'0.25'`, `'0.5'`, `'1.0'`, `'2.0'`                          |
| `containerMemory`         | string | `'1.0Gi'`                  | RAM: `'0.5Gi'`, `'1.0Gi'`, `'2.0Gi'`, `'4.0Gi'`                         |
| `minReplicas`             | int    | `1`                        | Minimum Container App replicas (0–10)                                   |
| `maxReplicas`             | int    | `3`                        | Maximum Container App replicas (1–20)                                   |
| `enableZoneRedundancy`    | bool   | `false`                    | Enables CAE zone redundancy (requires infrastructure subnet)            |
| `dbAdministratorLogin`    | string | `'naasadmin'`              | PostgreSQL admin username                                               |
| `dbAdministratorPassword` | secure | -                          | PostgreSQL admin password (`DB_ADMIN_PASSWORD`)                         |
| `dbName`                  | string | `'naas'`                   | Application database name                                               |
| `jwtSigningKey`           | secure | -                          | Key used to sign JWTs (`JWT_SIGNING_KEY`)                               |

## Prerequisites

- Azure CLI installed
- Logged in with `az login`
- Subscription selected with `az account set --subscription <SUBSCRIPTION_ID>`

## Deploy infrastructure

```bash
az deployment group create \
  --resource-group rg-naas-b \
  --parameters infra/public/bicep/dev.bicepparam
```

## Build and push image to ACR

Use the `containerRegistryLoginServer` output from the deploy.

```bash
az acr login --name <ACR_NAME>

docker build -f docker/Dockerfile -t <ACR_LOGIN_SERVER>/naas:latest .
docker push <ACR_LOGIN_SERVER>/naas:latest
```

Then re-run the Bicep deploy with `containerImage` pointing at the published tag.

## Automated deploy with GitHub Actions

Workflow file: [.github/workflows/deploy.yml](../../../.github/workflows/deploy.yml)

The unified workflow handles in a single dispatch: infra provisioning, API image rollout, and SPA publish.
At dispatch time you choose `infra_tool = bicep` (default) or `terraform`.

The name prefix and resource group are derived automatically with an IaC suffix:

- Bicep: prefix `<AZURE_NAME_PREFIX>b`, resource group `<AZURE_RESOURCE_GROUP>-b`
- Terraform: prefix `<AZURE_NAME_PREFIX>t`, resource group `<AZURE_RESOURCE_GROUP>-t`

Required repository variables (not secrets):

- `AZURE_CLIENT_ID`: client ID of the Entra application or user-assigned managed identity associated with the federated credential
- `AZURE_TENANT_ID`: Azure Entra tenant ID
- `AZURE_SUBSCRIPTION_ID`: target Azure subscription
- `AZURE_RESOURCE_GROUP`: base resource group name (suffix added by the workflow)
- `AZURE_LOCATION`: default Azure region (e.g. westeurope, eastus)
- `AZURE_NAME_PREFIX`: base prefix for Azure resource names (lowercase, 3–11 characters; the workflow appends the IaC suffix)
- `AZURE_CORE_LOCATION` _(optional)_: alternate region for Container Apps and PostgreSQL — useful when `AZURE_LOCATION` has capacity issues
- `AZURE_POSTGRES_LOCATION` _(optional)_: specific region for PostgreSQL Flexible Server
- `AZURE_STATIC_WEB_APP_LOCATION` _(optional)_: region for the Static Web App
- `AZURE_STATIC_WEB_APP_SKU` _(optional)_: Static Web App SKU (`Free` default)

Azure RBAC required for the federated identity:

- `Contributor` on the target resource group (to create the RG and run Bicep deploys)
- `AcrPush` on the target Azure Container Registry (to publish images)

A federated credential in Azure Entra ID that trusts the GitHub repository/branch or environment running the workflow is also required.

The workflow performs the following operations:

- Computes the effective prefix and resource group based on the chosen `infra_tool`
- Logs in to Azure with OIDC (`azure/login`)
- Creates the resource group if necessary
- Uses `infra/public/bicep/dev.bicepparam` (Bicep) or TF variables (Terraform) with `deployStaticWebApp=false`
- Deploys core infra without SWA (skippable with `skip_infra=true`)
- Builds and pushes the app image to ACR with a tag derived from the commit SHA
- Updates the Container App with the new image
- Provisions the SWA with the same chosen IaC tool
- Publishes the compiled SPA to the Static Web App

## Security notes

- `adminUserEnabled` is disabled on ACR
- Container image pull uses managed identity, not registry password
- I log sono centralizzati in Log Analytics
- Le probe di liveness/readiness puntano a `/`

## Idee di hardening opzionali (non applicate di default)

- Aggiungere custom domain e certificato per la Container App
- Restringere l'ingress con allowlist IP o usare Azure Front Door/WAF
- Spostare i parametri in file ambiente-specifici (dev/test/prod) se il progetto cresce oltre il contesto esercitazione
- Aggiungere vulnerability scanning in CI prima del push
