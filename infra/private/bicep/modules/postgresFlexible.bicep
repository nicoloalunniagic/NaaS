@description('Name of the PostgreSQL Flexible Server')
param name string

@description('Region for the server')
param location string

@description('Tags')
param tags object = {}

@description('Administrator login name')
param administratorLogin string = 'naasadmin'

@description('Administrator login password (use a secure parameter / Key Vault reference)')
@secure()
param administratorLoginPassword string

@description('Database name to create on the server')
param databaseName string = 'naas'

@description('SKU name (Burstable cheapest)')
param skuName string = 'Standard_B1ms'

@description('SKU tier')
@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param skuTier string = 'Burstable'

@description('PostgreSQL major version')
@allowed([
  '14'
  '15'
  '16'
])
param postgresVersion string = '16'

@description('Storage in GB')
param storageSizeGB int = 32

@description('Resource ID of the delegated subnet for PostgreSQL VNet injection')
param delegatedSubnetId string

@description('Resource ID of the hub VNet — needed to link the postgres private DNS zone')
param hubVnetId string

@description('Resource ID of the spoke VNet — needed to link the postgres private DNS zone')
param spokeVnetId string

// PostgreSQL Flexible Server VNet injection requires a server-specific DNS zone.
// The zone name includes the server name, so it is created here rather than in network.bicep.
var postgresDnsZoneName = '${name}.private.postgres.database.azure.com'

resource postgresDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: postgresDnsZoneName
  location: 'global'
  tags: tags
}

resource postgresDnsZoneHubLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: postgresDnsZone
  name: '${name}-hub-link'
  location: 'global'
  properties: {
    virtualNetwork: { id: hubVnetId }
    registrationEnabled: false
  }
}

resource postgresDnsZoneSpokeLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: postgresDnsZone
  name: '${name}-spoke-link'
  location: 'global'
  properties: {
    virtualNetwork: { id: spokeVnetId }
    registrationEnabled: false
  }
}

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    version: postgresVersion
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    storage: {
      storageSizeGB: storageSizeGB
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    network: {
      // VNet injection — all traffic stays inside the spoke; public access implicitly disabled
      delegatedSubnetResourceId: delegatedSubnetId
      privateDnsZoneArmResourceId: postgresDnsZone.id
    }
  }
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: server
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

output serverName string = server.name
output fullyQualifiedDomainName string = server.properties.fullyQualifiedDomainName
output databaseName string = database.name
output administratorLogin string = administratorLogin

@description('Npgsql connection string. Marked secure so it is not echoed in deployment outputs.')
@secure()
output connectionString string = 'Host=${server.properties.fullyQualifiedDomainName};Port=5432;Database=${database.name};Username=${administratorLogin};Password=${administratorLoginPassword};SSL Mode=Require;Trust Server Certificate=true'
