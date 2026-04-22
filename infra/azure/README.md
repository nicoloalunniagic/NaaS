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
az group create --name rg-naas-dev --location westeurope

az deployment group create \
  --resource-group rg-naas-dev \
  --template-file infra/azure/main.bicep \
  --parameters @infra/azure/main.parameters.example.json
```

Or with Bicep parameter file:

```bash
az deployment group create \
  --resource-group rg-naas-prod \
  --parameters infra/azure/prod.bicepparam
```

## Build and push image to ACR

Use the output `containerRegistryLoginServer` from the deployment.

```bash
az acr login --name <ACR_NAME>

docker build -f docker/Dockerfile -t <ACR_LOGIN_SERVER>/naas:latest .
docker push <ACR_LOGIN_SERVER>/naas:latest
```

Then redeploy Bicep with `containerImage` pointing to your pushed tag.

## GitHub Actions automated deploy

Workflow file: [.github/workflows/deploy-azure.yml](../../.github/workflows/deploy-azure.yml)

The workflow uses GitHub OIDC federation via `azure/login@v2` to authenticate to Azure from `ubuntu-latest`.

Required repository variables (not secrets):

- `AZURE_CLIENT_ID`: Client ID of the Entra application or user-assigned managed identity bound to the federated credential
- `AZURE_TENANT_ID`: Azure Entra tenant ID
- `AZURE_SUBSCRIPTION_ID`: Target Azure subscription
- `AZURE_RESOURCE_GROUP`: Target resource group name
- `AZURE_LOCATION`: Azure region (e.g., westeurope, eastus)
- `AZURE_NAME_PREFIX`: Prefix for Azure resources (lowercase, 3-12 chars)

Required Azure RBAC for the federated identity:

- `Contributor` on the target resource group (to create RG and deploy Bicep)
- `AcrPush` on the target Azure Container Registry (to push images)

You also need a federated credential in Azure Entra ID that trusts the GitHub repository/branch or environment running this workflow.

The workflow does the following:

- Logs in to Azure with OIDC (`azure/login`)
- Creates the resource group if needed
- Deploys `infra/azure/prod.bicepparam` with a temporary bootstrap image
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
