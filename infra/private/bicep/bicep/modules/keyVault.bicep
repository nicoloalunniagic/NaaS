@description('Key Vault name (must be globally unique, 3-24 chars, alphanumeric + dashes)')
param name string

@description('Region')
param location string

@description('Tags')
param tags object = {}

@description('Principal ID (object ID) granted the Key Vault Secrets User role on this vault. Typically the User-Assigned Managed Identity used by the Container App.')
param consumerPrincipalId string

@description('Secrets to seed into the vault. Each item: { name: string, value: string }')
@secure()
param secrets object = {}

@description('Resource ID of the subnet where the private endpoint will be placed')
param peSubnetId string

@description('Resource ID of the privatelink.vaultcore.azure.net private DNS zone')
param privateDnsZoneId string

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'standard'
      family: 'A'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

// Built-in role: Key Vault Secrets User (read-only on secret values).
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource secretsUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: vault
  name: guid(vault.id, consumerPrincipalId, keyVaultSecretsUserRoleId)
  properties: {
    principalId: consumerPrincipalId
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      keyVaultSecretsUserRoleId
    )
    principalType: 'ServicePrincipal'
  }
}

@batchSize(1)
resource seededSecrets 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = [for secretName in items(secrets): {
  parent: vault
  name: secretName.key
  properties: {
    value: secretName.value
  }
}]

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: '${name}-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${name}-pe-connection'
        properties: {
          privateLinkServiceId: vault.id
          groupIds: ['vault']
        }
      }
    ]
  }
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: privateEndpoint
  name: 'kvDnsZoneGroup'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-vaultcore-azure-net'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

output name string = vault.name
output uri string = vault.properties.vaultUri
output id string = vault.id
