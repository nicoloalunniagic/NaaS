param name string
param location string
param tags object = {}
param workspaceResourceId string

@description('Resource ID of the subnet where the AMPLS private endpoint will be placed')
param peSubnetId string

@description('Object with resource IDs of the four AMPLS private DNS zones: monitor, oms, ods, agentsvc')
param amplsDnsZoneIds object

@description('Resource ID of the blob private DNS zone — AMPLS PE requires all five monitor zones including blob')
param blobDnsZoneId string

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: name
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspaceResourceId
    IngestionMode: 'LogAnalytics'
  }
}

// Azure Monitor Private Link Scope — groups App Insights + Log Analytics
// under a single private endpoint that covers all five monitor DNS zones.
resource ampls 'Microsoft.Insights/privateLinkScopes@2021-07-01-preview' = {
  name: '${name}-ampls'
  location: 'global'
  tags: tags
  properties: {
    accessModeSettings: {
      ingestionAccessMode: 'PrivateOnly'
      queryAccessMode: 'PrivateOnly'
    }
  }
}

resource amplsAppInsights 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  parent: ampls
  name: '${name}-ai-scoped'
  properties: {
    linkedResourceId: appInsights.id
  }
}

resource amplsWorkspace 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  parent: ampls
  name: '${name}-law-scoped'
  properties: {
    linkedResourceId: workspaceResourceId
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: '${name}-ampls-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${name}-ampls-pe-connection'
        properties: {
          privateLinkServiceId: ampls.id
          groupIds: ['azuremonitor']
        }
      }
    ]
  }
}

// AMPLS requires all five DNS zone configs on a single PE zone group.
resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: privateEndpoint
  name: 'amplsDnsZoneGroup'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'monitor'
        properties: { privateDnsZoneId: amplsDnsZoneIds.monitor }
      }
      {
        name: 'oms'
        properties: { privateDnsZoneId: amplsDnsZoneIds.oms }
      }
      {
        name: 'ods'
        properties: { privateDnsZoneId: amplsDnsZoneIds.ods }
      }
      {
        name: 'agentsvc'
        properties: { privateDnsZoneId: amplsDnsZoneIds.agentsvc }
      }
      {
        name: 'blob'
        properties: { privateDnsZoneId: blobDnsZoneId }
      }
    ]
  }
}

output id string = appInsights.id
output name string = appInsights.name
