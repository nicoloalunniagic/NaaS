param location string
param namePrefix string
param tags object = {}
param enableZoneRedundancy bool = false

resource managedEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${namePrefix}-cae'
  location: location
  tags: tags
  properties: {
    zoneRedundant: enableZoneRedundancy
  }
}



output managedEnvironmentId string = managedEnvironment.id
output managedEnvironmentName string = managedEnvironment.name
