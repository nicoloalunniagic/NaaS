param location string
param namePrefix string
param tags object = {}
param deployAppInsights bool = false
param enableZoneRedundancy bool = false

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${namePrefix}-law'
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

module appInsights './modules/appInsights.bicep' = if (deployAppInsights) {
  name: 'appInsights'
  params: {
    name: '${namePrefix}-appi'
    location: location
    tags: tags
    workspaceResourceId: logAnalytics.id
  }
}

resource managedEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${namePrefix}-cae'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    zoneRedundant: enableZoneRedundancy
  }
}



output logAnalyticsWorkspaceName string = logAnalytics.name
output managedEnvironmentId string = managedEnvironment.id
output managedEnvironmentName string = managedEnvironment.name
output appInsightsName string = deployAppInsights ? '${namePrefix}-appi' : ''
