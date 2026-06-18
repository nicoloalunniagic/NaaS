# ── Address prefixes ──────────────────────────────────────────────────────────

locals {
  hub_address_prefix     = "10.0.0.0/16"
  spoke_address_prefix   = "10.1.0.0/16"
  firewall_subnet_prefix = "10.0.1.0/26"
  cae_subnet_prefix      = "10.1.0.0/23"
  pe_subnet_prefix       = "10.1.2.0/24"
  postgres_subnet_prefix = "10.1.3.0/24"
  appgw_subnet_prefix    = "10.1.4.0/24"

  # Private DNS zones shared across ACR, Storage, Key Vault, and Azure Monitor.
  # Keys are stable short identifiers used to reference zone IDs elsewhere in
  # the stack (e.g. azurerm_private_dns_zone.shared["acr"].id).
  # The blob suffix is hardcoded to core.windows.net (Azure public cloud).
  # Bicep uses environment().suffixes.storage; Terraform has no equivalent.
  shared_dns_zones = {
    acr      = "privatelink.azurecr.io"
    blob     = "privatelink.blob.core.windows.net"
    keyvault = "privatelink.vaultcore.azure.net"
    monitor  = "privatelink.monitor.azure.com"
    oms      = "privatelink.oms.opinsights.azure.com"
    ods      = "privatelink.ods.opinsights.azure.com"
    agentsvc = "privatelink.agentsvc.azure-automation.net"
  }
}

# ── Hub VNet ──────────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "hub" {
  name                = "${var.name_prefix}-hub-vnet"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.target.name
  address_space       = [local.hub_address_prefix]
  tags                = local.tags
}

# Reserved by name — Azure Firewall is not deployed in this topology, but the
# subnet preserves the address range and satisfies Azure's naming requirement
# should a firewall be added later.
resource "azurerm_subnet" "hub_firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = data.azurerm_resource_group.target.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [local.firewall_subnet_prefix]
}

# ── Spoke VNet ────────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "spoke" {
  name                = "${var.name_prefix}-spoke-vnet"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.target.name
  address_space       = [local.spoke_address_prefix]
  tags                = local.tags
}

# Container App Environment VNet injection.
# Minimum /23 for the consumption profile (default workload profile).
# Delegation is required before the CAE resource can reference this subnet.
resource "azurerm_subnet" "spoke_cae" {
  name                 = "cae-infra-subnet"
  resource_group_name  = data.azurerm_resource_group.target.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [local.cae_subnet_prefix]

  delegation {
    name = "cae-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Private endpoints for ACR, Storage, Key Vault, and AMPLS.
# privateEndpointNetworkPolicies must be Disabled to allow PE placement.
resource "azurerm_subnet" "spoke_pe" {
  name                              = "pe-subnet"
  resource_group_name               = data.azurerm_resource_group.target.name
  virtual_network_name              = azurerm_virtual_network.spoke.name
  address_prefixes                  = [local.pe_subnet_prefix]
  private_endpoint_network_policies = "Disabled"
}

# PostgreSQL Flexible Server delegated subnet (VNet injection).
# Postgres Flexible uses VNet injection — NOT a private endpoint.
# These two approaches are mutually exclusive for this service.
resource "azurerm_subnet" "spoke_postgres" {
  name                 = "postgres-subnet"
  resource_group_name  = data.azurerm_resource_group.target.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [local.postgres_subnet_prefix]

  delegation {
    name = "postgres-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Application Gateway WAF dedicated subnet.
resource "azurerm_subnet" "spoke_appgw" {
  name                 = "appgw-subnet"
  resource_group_name  = data.azurerm_resource_group.target.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [local.appgw_subnet_prefix]
}

# ── VNet Peering ──────────────────────────────────────────────────────────────

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "hub-to-spoke"
  resource_group_name          = data.azurerm_resource_group.target.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "spoke-to-hub"
  resource_group_name          = data.azurerm_resource_group.target.name
  virtual_network_name         = azurerm_virtual_network.spoke.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# ── Private DNS Zones ─────────────────────────────────────────────────────────

resource "azurerm_private_dns_zone" "shared" {
  for_each            = local.shared_dns_zones
  name                = each.value
  resource_group_name = data.azurerm_resource_group.target.name
  tags                = local.tags
}

# Link every shared zone to the hub VNet (centralised DNS resolver).
#
# depends_on the two peering resources mirrors the Bicep dependsOn anchor
# that prevents the race condition where DNS links are created before both
# VNets are fully provisioned. Errors 3 and 4 in the Bicep deployment run
# were caused by this exact race; the fix is the same in Terraform.
resource "azurerm_private_dns_zone_virtual_network_link" "shared_hub" {
  for_each              = local.shared_dns_zones
  name                  = "${var.name_prefix}-${each.key}-hub-link"
  resource_group_name   = data.azurerm_resource_group.target.name
  private_dns_zone_name = azurerm_private_dns_zone.shared[each.key].name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
  tags                  = local.tags

  depends_on = [
    azurerm_virtual_network_peering.hub_to_spoke,
    azurerm_virtual_network_peering.spoke_to_hub,
  ]
}

# VNet peering does NOT auto-extend private DNS resolution to the peer.
# The spoke must have its own link to every zone so that resources in the
# spoke (Container App, PostgreSQL, etc.) can resolve private endpoints.
resource "azurerm_private_dns_zone_virtual_network_link" "shared_spoke" {
  for_each              = local.shared_dns_zones
  name                  = "${var.name_prefix}-${each.key}-spoke-link"
  resource_group_name   = data.azurerm_resource_group.target.name
  private_dns_zone_name = azurerm_private_dns_zone.shared[each.key].name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
  tags                  = local.tags

  depends_on = [
    azurerm_virtual_network_peering.hub_to_spoke,
    azurerm_virtual_network_peering.spoke_to_hub,
  ]
}
