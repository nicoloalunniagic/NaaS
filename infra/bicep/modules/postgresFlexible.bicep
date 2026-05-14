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
      publicNetworkAccess: 'Enabled'
    }
  }
}

// Allow access from any Azure-hosted service (sufficient for Container Apps
// without VNet integration). For production, prefer private endpoints.
resource allowAzureServices 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: server
  name: 'AllowAllAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
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
