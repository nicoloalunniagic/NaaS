data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "target" {
  name = var.resource_group_name
}

locals {
  location                   = coalesce(var.location, data.azurerm_resource_group.target.location)
  postgres_location          = coalesce(var.postgres_location, local.location)
  tags                       = merge({ app = "no-as-a-service", managedBy = "terraform" }, var.additional_tags)
  acr_pull_role_id           = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/7f951dda-4ed3-4680-a7ca-43fe172d538d"
  blob_role_id               = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe"
  kv_secrets_role_id         = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6"
  kv_secrets_officer_role_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/b86a8fe4-44ce-4948-aee5-eccb2c155cd7"

  database_connection_string = "Host=${azurerm_postgresql_flexible_server.server.fqdn};Port=5432;Database=${azurerm_postgresql_flexible_server_database.database.name};Username=${var.db_administrator_login};Password=${var.db_administrator_password};SSL Mode=Require;Trust Server Certificate=true"

  key_vault_seed_secrets = {
    "database-connection-string" = local.database_connection_string
    "jwt-signing-key"            = var.jwt_signing_key
  }

  static_web_app_default_hostname = var.deploy_static_web_app ? azurerm_static_web_app.swa[0].default_host_name : ""
  cors_allowed_origins            = local.static_web_app_default_hostname != "" ? "https://${local.static_web_app_default_hostname}" : ""
}

resource "azurerm_user_assigned_identity" "uami" {
  name                = "${var.name_prefix}-uami"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.target.name
  tags                = local.tags
}

resource "azurerm_container_registry" "acr" {
  name                          = "${var.name_prefix}acr"
  location                      = local.location
  resource_group_name           = data.azurerm_resource_group.target.name
  sku                           = "Basic"
  admin_enabled                 = false
  public_network_access_enabled = true
  tags                          = local.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope              = azurerm_container_registry.acr.id
  role_definition_id = local.acr_pull_role_id
  principal_id       = azurerm_user_assigned_identity.uami.principal_id
}

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

resource "azurerm_postgresql_flexible_server" "server" {
  name                   = "${var.name_prefix}-pg"
  resource_group_name    = data.azurerm_resource_group.target.name
  location               = local.postgres_location
  version                = var.postgres_version
  administrator_login    = var.db_administrator_login
  administrator_password = var.db_administrator_password
  sku_name               = var.postgres_sku_name
  storage_mb             = var.postgres_storage_size_gb * 1024

  backup_retention_days         = 7
  geo_redundant_backup_enabled  = false
  public_network_access_enabled = true

  tags = local.tags
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure_services" {
  name             = "AllowAllAzureServices"
  server_id        = azurerm_postgresql_flexible_server.server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_postgresql_flexible_server_database" "database" {
  name      = var.db_name
  server_id = azurerm_postgresql_flexible_server.server.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_key_vault" "vault" {
  name                          = "${var.name_prefix}-kv"
  location                      = local.location
  resource_group_name           = data.azurerm_resource_group.target.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  soft_delete_retention_days    = 7
  public_network_access_enabled = true

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

# null_resource runs az keyvault secret set which is idempotent (create-or-update).
# This avoids the "already exists" error that azurerm_key_vault_secret produces
# when the KV was soft-delete recovered or when re-running the same job.
resource "null_resource" "seed_kv_secrets" {
  for_each = local.key_vault_seed_secrets

  triggers = {
    kv_name = azurerm_key_vault.vault.name
  }

  provisioner "local-exec" {
    # Secret value is passed via env var so it does not appear in TF logs.
    command = "az keyvault secret set --vault-name \"$KV_NAME\" --name \"$SECRET_NAME\" --value \"$SECRET_VALUE\" --output none"
    environment = {
      KV_NAME      = azurerm_key_vault.vault.name
      SECRET_NAME  = each.key
      SECRET_VALUE = each.value
    }
  }

  depends_on = [
    azurerm_role_assignment.key_vault_secrets_user,
    azurerm_role_assignment.key_vault_secrets_officer,
  ]
}

resource "azurerm_log_analytics_workspace" "law" {
  # Bicep omits an explicit Log Analytics workspace for the managed environment.
  # AzureRM requires one to keep the deployment declarative and valid.
  name                = "${var.name_prefix}-law"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.target.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_container_app_environment" "cae" {
  name                       = "${var.name_prefix}-cae"
  location                   = local.location
  resource_group_name        = data.azurerm_resource_group.target.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  infrastructure_subnet_id   = var.container_app_infrastructure_subnet_id
  zone_redundancy_enabled    = var.enable_zone_redundancy ? true : null
  tags                       = local.tags
}

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
    null_resource.seed_kv_secrets,
    azurerm_role_assignment.acr_pull,
    azurerm_role_assignment.blob_contributor
  ]
}

resource "azurerm_application_insights" "app" {
  count = var.app_insights_workspace_resource_id == null ? 0 : 1

  name                = "${var.name_prefix}-appi"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.target.name
  workspace_id        = var.app_insights_workspace_resource_id
  application_type    = "web"
  tags                = local.tags
}
