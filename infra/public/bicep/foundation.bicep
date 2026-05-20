param location string
param namePrefix string
param tags object = {}
param enableZoneRedundancy bool = false

@description('Resource ID of the Log Analytics workspace for CAE diagnostics.')
param logAnalyticsWorkspaceId string

resource managedEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${namePrefix}-cae'
  location: location
  tags: tags
  properties: {
    zoneRedundant: enableZoneRedundancy
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: reference(logAnalyticsWorkspaceId, '2022-10-01').customerId
        sharedKey: listKeys(logAnalyticsWorkspaceId, '2022-10-01').primarySharedKey
      }
    }
  }
}



output managedEnvironmentId string = managedEnvironment.id
output managedEnvironmentName string = managedEnvironment.name
