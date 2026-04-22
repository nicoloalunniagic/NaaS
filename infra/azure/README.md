# Azure infrastructure for No-as-a-Service

This folder contains Infrastructure-as-Code for deploying the webapp on Azure using Bicep.

## Structure

- `main.bicep`: orchestration entry point
- `foundation.bicep`: shared/base resources
- `modules/containerRegistry.bicep`: ACR module
- `modules/containerApp.bicep`: Azure Container App module
- `modules/appInsights.bicep`: optional Application Insights module
- `prod.bicepparam`: production parameter set

## What gets deployed

- Azure Container Registry (ACR) Basic
- Azure Log Analytics Workspace
- Azure Container Apps Environment
- Azure Container App (public ingress on port 8000)
- User-assigned managed identity for pulling images from ACR
- RBAC assignment: AcrPull on ACR to the managed identity

## Prerequisites

- Azure CLI installed
- Logged in with `az login`
- Subscription selected with `az account set --subscription <SUBSCRIPTION_ID>`

## Deploy infrastructure

```bash
az group create --name rg-noaas-dev --location westeurope

az deployment group create \
  --resource-group rg-noaas-dev \
  --template-file infra/azure/main.bicep \
  --parameters @infra/azure/main.parameters.example.json
```

Or with Bicep parameter file:

```bash
az deployment group create \
  --resource-group rg-noaas-prod \
  --parameters infra/azure/prod.bicepparam
```

## Build and push image to ACR

Use the output `containerRegistryLoginServer` from the deployment.

```bash
az acr login --name <ACR_NAME>

docker build -f docker/Dockerfile -t <ACR_LOGIN_SERVER>/noaas:latest .
docker push <ACR_LOGIN_SERVER>/noaas:latest
```

Then redeploy Bicep with `containerImage` pointing to your pushed tag.

## GitHub Actions automated deploy

Workflow file: [.github/workflows/deploy-azure.yml](../../.github/workflows/deploy-azure.yml)

The workflow uses Azure Managed Identity (OIDC workload identity federation) to authenticate to Azure. It runs on a GitHub-hosted runner or self-hosted runner with Azure Managed Identity support.

Required repository variables (not secrets):

- `MI_CLIENT_ID`: Client ID of the Managed Identity
- `AZURE_SUBSCRIPTION_ID`: Target Azure subscription
- `AZURE_RESOURCE_GROUP`: Target resource group name
- `AZURE_LOCATION`: Azure region (e.g., westeurope, eastus)
- `AZURE_NAME_PREFIX`: Prefix for Azure resources (lowercase, 3-12 chars)

Required Azure RBAC for the Managed Identity:

- `Contributor` on the target resource group (to create RG and deploy Bicep)
- `AcrPush` on the target Azure Container Registry (to push images)

Optional: if the runner is not already assigned the Managed Identity, set up workload identity federation by storing OIDC issuer/subject in Azure AD and adjusting login to use `azure/login@v2`.

The workflow does the following:

- Logs in to Azure with OIDC (`azure/login`)
- Creates the resource group if needed
- Deploys Bicep with a temporary bootstrap image
- Builds and pushes your app image to ACR with tag from commit SHA
- Redeploys Bicep with the pushed image

## Security notes

- `adminUserEnabled` is disabled on ACR
- Container image pull uses managed identity, not registry passwords
- Logs are centralized in Log Analytics
- Liveness/readiness probes target `/`

## Optional hardening ideas (not applied by default)

- Add custom domain and certificate for the Container App
- Restrict ingress with IP allowlist or front it with Azure Front Door/WAF
- Move parameters to environment-specific parameter files (dev/test/prod)
- Add vulnerability scanning in CI before push
