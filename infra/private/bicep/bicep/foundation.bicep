param location string
param namePrefix string
param tags object = {}
param enableZoneRedundancy bool = false

@description('Resource ID of the subnet delegated to the Container App Environment (cae-infra-subnet)')
param infrastructureSubnetId string

resource managedEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${namePrefix}-cae'
  location: location
  tags: tags
  properties: {
    zoneRedundant: enableZoneRedundancy
    vnetConfiguration: {
      infrastructureSubnetId: infrastructureSubnetId
      internal: false
    }
  }
}

output managedEnvironmentId string = managedEnvironment.id
output managedEnvironmentName string = managedEnvironment.name
