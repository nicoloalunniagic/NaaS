output "container_registry_name" {
  value       = azurerm_container_registry.acr.name
  description = "Container Registry name."
}

output "container_registry_login_server" {
  value       = azurerm_container_registry.acr.login_server
  description = "Container Registry login server."
}

output "managed_environment_name" {
  value       = azurerm_container_app_environment.cae.name
  description = "Container App managed environment name."
}

output "container_app_name" {
  value       = azurerm_container_app.api.name
  description = "Container App name."
}

output "container_app_url" {
  value       = "https://${azurerm_container_app.api.ingress[0].fqdn}"
  description = "Container App URL."
}

output "storage_account_name" {
  value       = azurerm_storage_account.blob.name
  description = "Storage Account name."
}

output "blob_container_name" {
  value       = azurerm_storage_container.uploads.name
  description = "Blob container name."
}

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

output "postgres_server_name" {
  value       = azurerm_postgresql_flexible_server.server.name
  description = "PostgreSQL Flexible Server name."
}

output "postgres_fqdn" {
  value       = azurerm_postgresql_flexible_server.server.fqdn
  description = "PostgreSQL fully qualified domain name."
}

output "postgres_database_name" {
  value       = azurerm_postgresql_flexible_server_database.database.name
  description = "PostgreSQL database name."
}

output "postgres_administrator_login" {
  value       = var.db_administrator_login
  description = "PostgreSQL administrator login."
}

output "postgres_connection_string" {
  value       = local.database_connection_string
  sensitive   = true
  description = "Npgsql-style connection string."
}

output "key_vault_name" {
  value       = azurerm_key_vault.vault.name
  description = "Key Vault name."
}

output "key_vault_uri" {
  value       = azurerm_key_vault.vault.vault_uri
  description = "Key Vault URI."
}

output "app_insights_id" {
  value       = try(azurerm_application_insights.app[0].id, null)
  description = "Optional Application Insights ID."
}

output "app_gateway_name" {
  value       = azurerm_application_gateway.waf.name
  description = "Application Gateway WAF name."
}

output "app_gateway_public_ip" {
  value       = azurerm_public_ip.appgw.ip_address
  description = "Application Gateway public IP address."
}

output "app_gateway_url" {
  value       = "http://${azurerm_public_ip.appgw.ip_address}"
  description = "Application Gateway URL."
}
