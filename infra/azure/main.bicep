@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Prefix used for Azure resource names. Use only lowercase letters and digits.')
@minLength(3)
@maxLength(12)
param namePrefix string

@description('Container image to deploy in Azure Container Apps, for example myregistry.azurecr.io/naas:latest')
param containerImage string

@description('CPU cores allocated to the container app')
@allowed([
  '0.25'
  '0.5'
  '1.0'
  '2.0'
])
param containerCpu string = '0.5'

@description('Memory allocated to the container app')
@allowed([
  '0.5Gi'
  '1.0Gi'
  '2.0Gi'
  '4.0Gi'
])
param containerMemory string = '1.0Gi'

@description('Minimum number of replicas for the container app')
@minValue(0)
@maxValue(10)
param minReplicas int = 1

@description('Maximum number of replicas for the container app')
@minValue(1)
@maxValue(20)
param maxReplicas int = 3

@description('Deploy Application Insights in addition to Log Analytics')
param deployAppInsights bool = false

@description('Enable zone redundancy for Container Apps managed environment (requires infrastructure subnet)')
param enableZoneRedundancy bool = false

var tags = {
  app: 'no-as-a-service'
  managedBy: 'bicep'
}

module foundation './foundation.bicep' = {
  name: 'foundation'
  params: {
    location: location
    namePrefix: namePrefix
    tags: tags
    deployAppInsights: deployAppInsights
    enableZoneRedundancy: enableZoneRedundancy
  }
}

module containerRegistry './modules/containerRegistry.bicep' = {
  name: 'containerRegistry'
  params: {
    name: '${namePrefix}acr'
    location: location
    tags: tags
    acrPullPrincipalId: userAssignedIdentity.properties.principalId
    logAnalyticsWorkspaceId: foundation.outputs.logAnalyticsWorkspaceId
  }
}

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${namePrefix}-uami'
  location: location
  tags: tags
}

module blobStorage './modules/blobStorage.bicep' = {
  name: 'blobStorage'
  params: {
    name: '${namePrefix}blob'
    location: location
    tags: tags
    storageContributorPrincipalId: userAssignedIdentity.properties.principalId
    logAnalyticsWorkspaceId: foundation.outputs.logAnalyticsWorkspaceId
  }
}

module containerApp './modules/containerApp.bicep' = {
  name: 'containerApp'
  params: {
    name: '${namePrefix}-api'
    location: location
    tags: tags
    managedEnvironmentId: foundation.outputs.managedEnvironmentId
    containerImage: containerImage
    containerCpu: containerCpu
    containerMemory: containerMemory
    minReplicas: minReplicas
    maxReplicas: maxReplicas
    acrLoginServer: containerRegistry.outputs.loginServer
    userAssignedIdentityId: userAssignedIdentity.id
    env: [
      {
        name: 'AZURE_STORAGE_ACCOUNT_NAME'
        value: blobStorage.outputs.storageAccountName
      }
      {
        name: 'AZURE_STORAGE_CONTAINER_NAME'
        value: blobStorage.outputs.blobContainerName
      }
      {
        name: 'AZURE_CLIENT_ID'
        value: userAssignedIdentity.properties.clientId
      }
    ]
  }

}



output containerRegistryName string = containerRegistry.outputs.name
output containerRegistryLoginServer string = containerRegistry.outputs.loginServer
output managedEnvironmentName string = foundation.outputs.managedEnvironmentName
output containerAppName string = containerApp.outputs.name
output containerAppUrl string = containerApp.outputs.url
output appInsightsName string = foundation.outputs.appInsightsName
output storageAccountName string = blobStorage.outputs.storageAccountName
output blobContainerName string = blobStorage.outputs.blobContainerName
