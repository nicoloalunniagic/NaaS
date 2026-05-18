# ── Data sources ──────────────────────────────────────────────────────────────

data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "target" {
  name = var.resource_group_name
}

# ── Locals ────────────────────────────────────────────────────────────────────

locals {
  location          = coalesce(var.location, data.azurerm_resource_group.target.location)
  postgres_location = coalesce(var.postgres_location, local.location)
  tags              = merge({ app = "no-as-a-service", managedBy = "terraform" }, var.additional_tags)

  acr_pull_role_id           = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/7f951dda-4ed3-4680-a7ca-43fe172d538d"
  blob_role_id               = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe"
  kv_secrets_role_id         = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6"
  kv_secrets_officer_role_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/b86a8fe4-44ce-4948-aee5-eccb2c155cd7"

  postgres_server_name   = "${var.name_prefix}-pg"
  postgres_dns_zone_name = "${local.postgres_server_name}.private.postgres.database.azure.com"

  # Recorded for documentation; not used by TF directly because KV secret
  # seeding is intentionally omitted — see KNOWN LIMITATION below.
  database_connection_string = "Host=${azurerm_postgresql_flexible_server.server.fqdn};Port=5432;Database=${azurerm_postgresql_flexible_server_database.database.name};Username=${var.db_administrator_login};Password=${var.db_administrator_password};SSL Mode=Require;Trust Server Certificate=true"

  static_web_app_default_hostname = var.deploy_static_web_app ? azurerm_static_web_app.swa[0].default_host_name : ""
  cors_allowed_origins            = local.static_web_app_default_hostname != "" ? "https://${local.static_web_app_default_hostname}" : ""
}

# ── User-Assigned Managed Identity ───────────────────────────────────────────

resource "azurerm_user_assigned_identity" "uami" {
  name                = "${var.name_prefix}-uami"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.target.name
  tags                = local.tags
}

# ── Container Registry ────────────────────────────────────────────────────────
# Premium SKU is required for private endpoint support.
# public_network_access_enabled remains true: ACR Tasks agents (az acr build)
# are Azure-managed VMs that cannot use managed-identity context, making the
# AzureServices bypass ineffective. The private endpoint serves in-VNet image
# pulls by the Container App Environment.

resource "azurerm_container_registry" "acr" {
  name                          = "${var.name_prefix}acr"
  location                      = local.location
  resource_group_name           = data.azurerm_resource_group.target.name
  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = true
  tags                          = local.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope              = azurerm_container_registry.acr.id
  role_definition_id = local.acr_pull_role_id
  principal_id       = azurerm_user_assigned_identity.uami.principal_id
}

resource "azurerm_private_endpoint" "acr" {
  name                = "${var.name_prefix}acr-pe"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.target.name
  subnet_id           = azurerm_subnet.spoke_pe.id
  tags                = local.tags

  private_service_connection {
    name                           = "${var.name_prefix}acr-pe-connection"
    private_connection_resource_id = azurerm_container_registry.acr.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "acrDnsZoneGroup"
    private_dns_zone_ids = [azurerm_private_dns_zone.shared["acr"].id]
  }
}

# ── Storage Account ───────────────────────────────────────────────────────────

resource "azurerm_storage_account" "blob" {
  name                     = "${var.name_prefix}blob"
  resource_group_name      = data.azurerm_resource_group.target.name
  location                 = local.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  access_tier              = "Hot"

  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  shared_access_key_enabled       = false
  public_network_access_enabled   = false

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  tags = local.tags
}

resource "azurerm_storage_container" "uploads" {
  name                  = var.blob_container_name
  storage_account_id    = azurerm_storage_account.blob.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "blob_contributor" {
  scope              = azurerm_storage_account.blob.id
  role_definition_id = local.blob_role_id
  principal_id       = azurerm_user_assigned_identity.uami.principal_id
}

resource "azurerm_private_endpoint" "blob" {
  name                = "${var.name_prefix}blob-pe"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.target.name
  subnet_id           = azurerm_subnet.spoke_pe.id
  tags                = local.tags

  private_service_connection {
    name                           = "${var.name_prefix}blob-pe-connection"
    private_connection_resource_id = azurerm_storage_account.blob.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blobDnsZoneGroup"
    private_dns_zone_ids = [azurerm_private_dns_zone.shared["blob"].id]
  }
}

# ── PostgreSQL Flexible Server ────────────────────────────────────────────────
# PostgreSQL Flexible Server uses VNet injection (delegated subnet), NOT a
# private endpoint — the two approaches are mutually exclusive for this service.
# The DNS zone name is server-name-specific and must exist before the server
# resource so the FQDN resolves correctly inside the VNet during provisioning.

resource "azurerm_private_dns_zone" "postgres" {
  name                = local.postgres_dns_zone_name
  resource_group_name = data.azurerm_resource_group.target.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres_hub" {
  name                  = "${local.postgres_server_name}-hub-link"
  resource_group_name   = data.azurerm_resource_group.target.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres_spoke" {
  name                  = "${local.postgres_server_name}-spoke-link"
  resource_group_name   = data.azurerm_resource_group.target.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.spoke.id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_postgresql_flexible_server" "server" {
  name                   = local.postgres_server_name
  resource_group_name    = data.azurerm_resource_group.target.name
  location               = local.postgres_location
  version                = var.postgres_version
  administrator_login    = var.db_administrator_login
  administrator_password = var.db_administrator_password
  sku_name               = var.postgres_sku_name
  storage_mb             = var.postgres_storage_size_gb * 1024

  # VNet injection and public access are mutually exclusive. The azurerm 4.x
  # provider defaults public_network_access_enabled to true, so it must be
  # set explicitly to false when using delegated_subnet_id.
  public_network_access_enabled = false
  delegated_subnet_id           = azurerm_subnet.spoke_postgres.id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  tags = local.tags

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.postgres_hub,
    azurerm_private_dns_zone_virtual_network_link.postgres_spoke,
  ]
}

resource "azurerm_postgresql_flexible_server_database" "database" {
  name      = var.db_name
  server_id = azurerm_postgresql_flexible_server.server.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# ── Key Vault ─────────────────────────────────────────────────────────────────

resource "azurerm_key_vault" "vault" {
  name                          = "${var.name_prefix}-kv"
  location                      = local.location
  resource_group_name           = data.azurerm_resource_group.target.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  soft_delete_retention_days    = 7
  public_network_access_enabled = false

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  tags = local.tags
}

resource "azurerm_role_assignment" "key_vault_secrets_user" {
  scope              = azurerm_key_vault.vault.id
  role_definition_id = local.kv_secrets_role_id
  principal_id       = azurerm_user_assigned_identity.uami.principal_id
}

# Grants the Terraform deploying SP write access to seed secrets.
resource "azurerm_role_assignment" "key_vault_secrets_officer" {
  scope              = azurerm_key_vault.vault.id
  role_definition_id = local.kv_secrets_officer_role_id
  principal_id       = data.azurerm_client_config.current.object_id
}

# KNOWN LIMITATION — Key Vault secret seeding is intentionally omitted.
#
# In Bicep, ARM runs as a trusted Azure service and writes secrets to a private
# Key Vault via the ARM control plane, which is exempt from the
# publicNetworkAccess: Disabled restriction.
#
# Terraform CLI running from a GitHub-hosted runner contacts the Key Vault
# *data plane* (https://<name>.vault.azure.net) over the public internet.
# That endpoint is blocked when public_network_access_enabled = false, and
# there is no Terraform equivalent of the ARM trusted-service data-plane bypass.
#
# To make the Container App functional after deployment, manually seed these
# secrets into Key Vault using a principal that can reach it — for example
# from inside the VNet, via Azure Cloud Shell with VNet integration, or by
# temporarily enabling public access:
#
#   az keyvault secret set --vault-name <name> \
#     --name database-connection-string --value "<value>"
#   az keyvault secret set --vault-name <name> \
#     --name jwt-signing-key --value "<value>"
#
# The expected connection-string value is captured in local.database_connection_string.

resource "azurerm_private_endpoint" "keyvault" {
  name                = "${var.name_prefix}-kv-pe"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.target.name
  subnet_id           = azurerm_subnet.spoke_pe.id
  tags                = local.tags

  private_service_connection {
    name                           = "${var.name_prefix}-kv-pe-connection"
    private_connection_resource_id = azurerm_key_vault.vault.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "kvDnsZoneGroup"
    private_dns_zone_ids = [azurerm_private_dns_zone.shared["keyvault"].id]
  }
}

# ── Log Analytics Workspace ───────────────────────────────────────────────────
# Always created — consumed by both the CAE and the AMPLS (App Insights).
# Unlike the public topology, no external workspace ID is accepted; the
# workspace is always owned by this stack.

resource "azurerm_log_analytics_workspace" "law" {
  name                = "${var.name_prefix}-law"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.target.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# ── Container App Environment ─────────────────────────────────────────────────

resource "azurerm_container_app_environment" "cae" {
  name                           = "${var.name_prefix}-cae"
  location                       = local.location
  resource_group_name            = data.azurerm_resource_group.target.name
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.law.id
  infrastructure_subnet_id       = azurerm_subnet.spoke_cae.id
  internal_load_balancer_enabled = false
  tags                           = local.tags
}

# ── Container App ─────────────────────────────────────────────────────────────
# The secret blocks reference Key Vault URLs; the Container App runtime
# resolves them at startup using the UAMI via the KV private endpoint.
# Because KV secrets are not seeded by Terraform (see KNOWN LIMITATION above),
# the container will fail to start until secrets are manually created in KV.

resource "azurerm_container_app" "api" {
  name                         = "${var.name_prefix}-api"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name          = data.azurerm_resource_group.target.name
  revision_mode                = "Single"
  tags                         = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.uami.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.uami.id
  }

  secret {
    name                = "database-connection-string"
    key_vault_secret_id = "${azurerm_key_vault.vault.vault_uri}secrets/database-connection-string"
    identity            = azurerm_user_assigned_identity.uami.id
  }

  secret {
    name                = "jwt-signing-key"
    key_vault_secret_id = "${azurerm_key_vault.vault.vault_uri}secrets/jwt-signing-key"
    identity            = azurerm_user_assigned_identity.uami.id
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "naas"
      image  = var.container_image
      cpu    = tonumber(var.container_cpu)
      memory = var.container_memory

      env {
        name  = "AZURE_STORAGE_ACCOUNT_NAME"
        value = azurerm_storage_account.blob.name
      }

      env {
        name  = "AZURE_STORAGE_CONTAINER_NAME"
        value = azurerm_storage_container.uploads.name
      }

      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.uami.client_id
      }

      env {
        name  = "CORS_ALLOWED_ORIGINS"
        value = local.cors_allowed_origins
      }

      env {
        name        = "DATABASE_CONNECTION_STRING"
        secret_name = "database-connection-string"
      }

      env {
        name        = "JWT_SIGNING_KEY"
        secret_name = "jwt-signing-key"
      }

      liveness_probe {
        transport        = "HTTP"
        path             = "/"
        port             = 8000
        initial_delay    = 10
        interval_seconds = 30
      }

      readiness_probe {
        transport        = "HTTP"
        path             = "/"
        port             = 8000
        initial_delay    = 10
        interval_seconds = 10
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8000
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  depends_on = [
    azurerm_role_assignment.acr_pull,
    azurerm_role_assignment.blob_contributor,
    azurerm_role_assignment.key_vault_secrets_user,
  ]
}

# ── Application Insights + AMPLS ──────────────────────────────────────────────

resource "azurerm_application_insights" "app" {
  name                = "${var.name_prefix}-appi"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.target.name
  workspace_id        = azurerm_log_analytics_workspace.law.id
  application_type    = "web"
  tags                = local.tags
}

# Azure Monitor Private Link Scope — groups App Insights + LAW under a single
# private endpoint covering all five Azure Monitor DNS zones. Ingestion and
# query traffic is forced through the private endpoint (PrivateOnly).
resource "azurerm_monitor_private_link_scope" "ampls" {
  name                  = "${var.name_prefix}-appi-ampls"
  resource_group_name   = data.azurerm_resource_group.target.name
  ingestion_access_mode = "PrivateOnly"
  query_access_mode     = "PrivateOnly"
  tags                  = local.tags
}

resource "azurerm_monitor_private_link_scoped_service" "app_insights" {
  name                = "${var.name_prefix}-appi-ai-scoped"
  resource_group_name = data.azurerm_resource_group.target.name
  scope_name          = azurerm_monitor_private_link_scope.ampls.name
  linked_resource_id  = azurerm_application_insights.app.id
}

resource "azurerm_monitor_private_link_scoped_service" "law" {
  name                = "${var.name_prefix}-appi-law-scoped"
  resource_group_name = data.azurerm_resource_group.target.name
  scope_name          = azurerm_monitor_private_link_scope.ampls.name
  linked_resource_id  = azurerm_log_analytics_workspace.law.id
}

# All five Azure Monitor DNS zones must be present on a single DNS zone group —
# this is an Azure Monitor requirement, not a Terraform constraint.
resource "azurerm_private_endpoint" "ampls" {
  name                = "${var.name_prefix}-appi-ampls-pe"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.target.name
  subnet_id           = azurerm_subnet.spoke_pe.id
  tags                = local.tags

  depends_on = [
    azurerm_monitor_private_link_scoped_service.appi,
    azurerm_monitor_private_link_scoped_service.law,
  ]

  private_service_connection {
    name                           = "${var.name_prefix}-appi-ampls-pe-connection"
    private_connection_resource_id = azurerm_monitor_private_link_scope.ampls.id
    subresource_names              = ["azuremonitor"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "amplsDnsZoneGroup"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.shared["monitor"].id,
      azurerm_private_dns_zone.shared["oms"].id,
      azurerm_private_dns_zone.shared["ods"].id,
      azurerm_private_dns_zone.shared["agentsvc"].id,
      azurerm_private_dns_zone.shared["blob"].id,
    ]
  }
}

# ── Static Web App ────────────────────────────────────────────────────────────
# SWA is a global service; no VNet integration is required or available.
# For private topology api_base_url is typically empty — the API is VNet-internal.

resource "azurerm_static_web_app" "swa" {
  count = var.deploy_static_web_app ? 1 : 0

  name                = "${var.name_prefix}-web"
  location            = var.static_web_app_location
  resource_group_name = data.azurerm_resource_group.target.name
  sku_tier            = var.static_web_app_sku
  sku_size            = var.static_web_app_sku
  tags                = local.tags

  app_settings = var.api_base_url != "" ? {
    API_BASE_URL = var.api_base_url
  } : {}
}
