@description('Azure region for virtual networks')
param location string

@description('Prefix used for naming network resources')
param namePrefix string

@description('Tags to apply to all resources')
param tags object = {}

// ── Address spaces ────────────────────────────────────────────────────────────

var hubAddressPrefix     = '10.0.0.0/16'
var spokeAddressPrefix   = '10.1.0.0/16'

var firewallSubnetPrefix = '10.0.1.0/26'
var caeSubnetPrefix      = '10.1.0.0/23'
var peSubnetPrefix       = '10.1.2.0/24'
var postgresSubnetPrefix = '10.1.3.0/24'

// ── Hub VNet ──────────────────────────────────────────────────────────────────

resource hubVnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: '${namePrefix}-hub-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [hubAddressPrefix]
    }
    subnets: [
      {
        // Index 0 — reserved name required by Azure Firewall; resource not deployed
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: firewallSubnetPrefix
        }
      }
    ]
  }
}

// ── Spoke VNet ────────────────────────────────────────────────────────────────

resource spokeVnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: '${namePrefix}-spoke-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [spokeAddressPrefix]
    }
    subnets: [
      {
        // Index 0 — Container App Environment VNet injection
        // Minimum: /27 for workload profiles (default), /23 for legacy consumption-only
        name: 'cae-infra-subnet'
        properties: {
          addressPrefix: caeSubnetPrefix
          delegations: [
            {
              name: 'cae-delegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        // Index 1 — private endpoints for ACR, Storage, Key Vault, AMPLS
        name: 'pe-subnet'
        properties: {
          addressPrefix: peSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        // Index 2 — PostgreSQL Flexible Server delegated subnet (VNet injection)
        name: 'postgres-subnet'
        properties: {
          addressPrefix: postgresSubnetPrefix
          delegations: [
            {
              name: 'postgres-delegation'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
        }
      }
    ]
  }
}

// ── VNet Peering ──────────────────────────────────────────────────────────────

resource hubToSpoke 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-01-01' = {
  parent: hubVnet
  name: 'hub-to-spoke'
  properties: {
    remoteVirtualNetwork: { id: spokeVnet.id }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource spokeToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-01-01' = {
  parent: spokeVnet
  name: 'spoke-to-hub'
  properties: {
    remoteVirtualNetwork: { id: hubVnet.id }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

// ── Private DNS Zones ─────────────────────────────────────────────────────────

var dnsZoneNames = [
  'privatelink.azurecr.io'                                             // 0 — ACR
  'privatelink.blob.${environment().suffixes.storage}'                 // 1 — Storage
  'privatelink.vaultcore.azure.net'                                    // 2 — Key Vault
  'privatelink.monitor.azure.com'             // 3 — Azure Monitor (AMPLS)
  'privatelink.oms.opinsights.azure.com'      // 4 — Log Analytics ingestion
  'privatelink.ods.opinsights.azure.com'      // 5 — Log Analytics agent
  'privatelink.agentsvc.azure-automation.net' // 6 — Monitoring agent service
]

resource dnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for zone in dnsZoneNames: {
  name: zone
  location: 'global'
  tags: tags
}]

// Link every zone to the hub VNet (centralised resolver)
resource hubDnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zone, i) in dnsZoneNames: {
  parent: dnsZones[i]
  name: '${namePrefix}-hub-link'
  location: 'global'
  properties: {
    virtualNetwork: { id: hubVnet.id }
    registrationEnabled: false
  }
  // ARM runtime does not reliably track implicit deps inside for-loop bodies;
  // explicit dependsOn is required even though the linter flags it as redundant.
  #disable-next-line no-unnecessary-dependson
  dependsOn: [hubVnet]
}]

// Link every zone to the spoke VNet — VNet peering does NOT auto-extend
// private DNS resolution, so spoke resources need their own links.
resource spokeDnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zone, i) in dnsZoneNames: {
  parent: dnsZones[i]
  name: '${namePrefix}-spoke-link'
  location: 'global'
  properties: {
    virtualNetwork: { id: spokeVnet.id }
    registrationEnabled: false
  }
  // Same rationale as hubDnsLinks above.
  #disable-next-line no-unnecessary-dependson
  dependsOn: [spokeVnet]
}]

// ── Outputs ───────────────────────────────────────────────────────────────────

output hubVnetId   string = hubVnet.id
output spokeVnetId string = spokeVnet.id

// Subnet IDs — index order must match the subnets array above
output caeInfraSubnetId string = spokeVnet.properties.subnets[0].id
output peSubnetId       string = spokeVnet.properties.subnets[1].id
output postgresSubnetId string = spokeVnet.properties.subnets[2].id

// DNS zone IDs consumed by each module's private endpoint DNS zone group
output acrDnsZoneId      string = dnsZones[0].id
output blobDnsZoneId     string = dnsZones[1].id
output keyVaultDnsZoneId string = dnsZones[2].id

// All four AMPLS zones bundled for the App Insights module
output amplsDnsZoneIds object = {
  monitor:  dnsZones[3].id
  oms:      dnsZones[4].id
  ods:      dnsZones[5].id
  agentsvc: dnsZones[6].id
}
