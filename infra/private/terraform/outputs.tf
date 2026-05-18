# ── Container Registry ────────────────────────────────────────────────────────

output "container_registry_name" {
  value       = azurerm_container_registry.acr.name
  description = "Container Registry name."
}

output "container_registry_login_server" {
  value       = azurerm_container_registry.acr.login_server
  description = "Container Registry login server."
}

# ── Container App Environment + App ───────────────────────────────────────────

output "managed_environment_name" {
  value       = azurerm_container_app_environment.cae.name
  description = "Container App managed environment name."
}

output "container_app_name" {
  value       = azurerm_container_app.api.name
  description = "Container App name."
}

output "container_app_url" {
  value       = "https://${azurerm_container_app.api.latest_revision_fqdn}"
  description = "Container App URL. Reachable from within the spoke VNet only (internal load balancer disabled but CAE is VNet-injected)."
}

# ── Storage ───────────────────────────────────────────────────────────────────

output "storage_account_name" {
  value       = azurerm_storage_account.blob.name
  description = "Storage Account name."
}

output "blob_container_name" {
  value       = azurerm_storage_container.uploads.name
  description = "Blob container name."
}

# ── Static Web App ────────────────────────────────────────────────────────────

output "static_web_app_name" {
  value       = try(azurerm_static_web_app.swa[0].name, null)
  description = "Static Web App name."
}

output "static_web_app_url" {
  value       = try("https://${azurerm_static_web_app.swa[0].default_host_name}", null)
  description = "Static Web App URL."
}

output "static_web_app_deployment_token" {
  value       = try(azurerm_static_web_app.swa[0].api_key, null)
  sensitive   = true
  description = "Static Web App deployment token."
}

# ── PostgreSQL ────────────────────────────────────────────────────────────────

output "postgres_server_name" {
  value       = azurerm_postgresql_flexible_server.server.name
  description = "PostgreSQL Flexible Server name."
}

output "postgres_fqdn" {
  value       = azurerm_postgresql_flexible_server.server.fqdn
  description = "PostgreSQL fully qualified domain name. Resolves to a private IP within the spoke VNet."
}

output "postgres_database_name" {
  value       = azurerm_postgresql_flexible_server_database.database.name
  description = "PostgreSQL database name."
}

# ── Key Vault ─────────────────────────────────────────────────────────────────

output "key_vault_name" {
  value       = azurerm_key_vault.vault.name
  description = "Key Vault name."
}

output "key_vault_uri" {
  value       = azurerm_key_vault.vault.vault_uri
  description = "Key Vault URI. Reachable from within the spoke VNet via private endpoint."
}

# ── Observability ─────────────────────────────────────────────────────────────

output "app_insights_name" {
  value       = azurerm_application_insights.app.name
  description = "Application Insights component name."
}

output "log_analytics_workspace_name" {
  value       = azurerm_log_analytics_workspace.law.name
  description = "Log Analytics Workspace name."
}

# ── Network ───────────────────────────────────────────────────────────────────

output "hub_vnet_id" {
  value       = azurerm_virtual_network.hub.id
  description = "Hub VNet resource ID."
}

output "spoke_vnet_id" {
  value       = azurerm_virtual_network.spoke.id
  description = "Spoke VNet resource ID."
}

output "pe_subnet_id" {
  value       = azurerm_subnet.spoke_pe.id
  description = "Private endpoint subnet resource ID (spoke)."
}

output "cae_infra_subnet_id" {
  value       = azurerm_subnet.spoke_cae.id
  description = "Container App Environment infrastructure subnet resource ID (spoke)."
}

output "postgres_subnet_id" {
  value       = azurerm_subnet.spoke_postgres.id
  description = "PostgreSQL delegated subnet resource ID (spoke)."
}
