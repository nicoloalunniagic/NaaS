@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Location for PostgreSQL Flexible Server (some subscriptions are restricted in westeurope).')
param postgresLocation string = location

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

@description('Enable zone redundancy for Container Apps managed environment (requires infrastructure subnet)')
param enableZoneRedundancy bool = false

@description('Region for the Static Web App. SWA SKUs only available in a subset of regions.')
param staticWebAppLocation string = 'westeurope'

@description('SKU for the Static Web App')
@allowed([
  'Free'
  'Standard'
])
param staticWebAppSku string = 'Free'

@description('Controls whether the Static Web App resource is deployed by this template.')
param deployStaticWebApp bool = true

@description('Administrator login for the PostgreSQL Flexible Server')
param dbAdministratorLogin string = 'naasadmin'

@description('Administrator password for the PostgreSQL Flexible Server. Provide via secure parameter.')
@secure()
param dbAdministratorPassword string

@description('JWT signing key used to sign authentication tokens. Use a long random value.')
@secure()
param jwtSigningKey string

@description('Database name to create on the PostgreSQL server')
param dbName string = 'naas'

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
  }
}

module postgres './modules/postgresFlexible.bicep' = {
  name: 'postgres'
  params: {
    name: '${namePrefix}-pg'
    location: postgresLocation
    tags: tags
    administratorLogin: dbAdministratorLogin
    administratorLoginPassword: dbAdministratorPassword
    databaseName: dbName
  }
}

module keyVault './modules/keyVault.bicep' = {
  name: 'keyVault'
  params: {
    name: '${namePrefix}-kv'
    location: location
    tags: tags
    consumerPrincipalId: userAssignedIdentity.properties.principalId
    secrets: {
      'database-connection-string': postgres.outputs.connectionString
      'jwt-signing-key': jwtSigningKey
    }
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
    secrets: [
      {
        name: 'database-connection-string'
        keyVaultUrl: '${keyVault.outputs.uri}secrets/database-connection-string'
        identity: userAssignedIdentity.id
      }
      {
        name: 'jwt-signing-key'
        keyVaultUrl: '${keyVault.outputs.uri}secrets/jwt-signing-key'
        identity: userAssignedIdentity.id
      }
    ]
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
      {
        name: 'CORS_ALLOWED_ORIGINS'
        value: deployStaticWebApp ? staticWebApp!.outputs.url : ''
      }
      {
        name: 'DATABASE_CONNECTION_STRING'
        secretRef: 'database-connection-string'
      }
      {
        name: 'JWT_SIGNING_KEY'
        secretRef: 'jwt-signing-key'
      }
    ]
  }

}

module staticWebApp './modules/staticWebApp.bicep' = if (deployStaticWebApp) {
  name: 'staticWebApp'
  params: {
    name: '${namePrefix}-web'
    location: staticWebAppLocation
    tags: tags
    sku: staticWebAppSku
  }
}



output containerRegistryName string = containerRegistry.outputs.name
output containerRegistryLoginServer string = containerRegistry.outputs.loginServer
output managedEnvironmentName string = foundation.outputs.managedEnvironmentName
output containerAppName string = containerApp.outputs.name
output containerAppUrl string = containerApp.outputs.url

output storageAccountName string = blobStorage.outputs.storageAccountName
output blobContainerName string = blobStorage.outputs.blobContainerName

output staticWebAppName string = deployStaticWebApp ? staticWebApp!.outputs.name : ''
output staticWebAppUrl string = deployStaticWebApp ? staticWebApp!.outputs.url : ''

output postgresServerName string = postgres.outputs.serverName
output postgresFqdn string = postgres.outputs.fullyQualifiedDomainName
output postgresDatabaseName string = postgres.outputs.databaseName

output keyVaultName string = keyVault.outputs.name
output keyVaultUri string = keyVault.outputs.uri
