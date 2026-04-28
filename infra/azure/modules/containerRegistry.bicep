param name string
param location string
param tags object = {}
param acrPullPrincipalId string // UAMI principal ID per AcrPull

@description('Log Analytics workspace resource ID for diagnostics')
param logAnalyticsWorkspaceId string = ''

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Premium'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Disabled'
    zoneRedundancy: 'Enabled'
  }
}

resource softDeletePolicy 'Microsoft.ContainerRegistry/registries/deletedRepositories@2023-07-01' = {
  parent: registry
  name: 'default'
  properties: {
    deleteUntaggedManifestsAfterDays: 30
  }
}

resource retentionPolicy 'Microsoft.ContainerRegistry/registries/policies@2023-07-01' = {
  parent: registry
  name: 'default'
  properties: {
    status: 'enabled'
    days: 30
  }
}

resource geoReplication 'Microsoft.ContainerRegistry/registries/replications@2023-07-01' = {
  parent: registry
  name: 'easteurope'
  location: 'easteurope'
  properties: {}
}

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, acrPullPrincipalId, 'AcrPullRole')
  scope: registry
  properties: {
    principalId: acrPullPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  }
}

resource registryDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: '${name}-diag'
  scope: registry
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'ContainerRegistryRepositoryEvents'
        enabled: true
      }
      {
        category: 'ContainerRegistryLoginEvents'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output id string = registry.id
output name string = registry.name
output loginServer string = registry.properties.loginServer
