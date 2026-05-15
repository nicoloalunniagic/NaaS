variable "resource_group_name" {
  description = "Name of the existing Azure Resource Group where resources are deployed."
  type        = string
}

variable "location" {
  description = "Azure region for all resources. Null means use the resource group location."
  type        = string
  default     = null
  nullable    = true
}

variable "postgres_location" {
  description = "Azure region for PostgreSQL Flexible Server. Null means use location."
  type        = string
  default     = null
  nullable    = true
}

variable "name_prefix" {
  description = "Prefix used for Azure resource names. Use only lowercase letters and digits."
  type        = string

  validation {
    condition     = length(var.name_prefix) >= 3 && length(var.name_prefix) <= 12
    error_message = "name_prefix must be between 3 and 12 characters."
  }

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.name_prefix))
    error_message = "name_prefix must contain only lowercase letters and digits."
  }
}

variable "container_image" {
  description = "Container image to deploy in Azure Container Apps, for example myregistry.azurecr.io/naas:latest."
  type        = string
}

variable "container_cpu" {
  description = "CPU cores allocated to the container app."
  type        = string
  default     = "0.5"

  validation {
    condition     = contains(["0.25", "0.5", "1.0", "2.0"], var.container_cpu)
    error_message = "container_cpu must be one of: 0.25, 0.5, 1.0, 2.0."
  }
}

variable "container_memory" {
  description = "Memory allocated to the container app."
  type        = string
  default     = "1.0Gi"

  validation {
    condition     = contains(["0.5Gi", "1.0Gi", "2.0Gi", "4.0Gi"], var.container_memory)
    error_message = "container_memory must be one of: 0.5Gi, 1.0Gi, 2.0Gi, 4.0Gi."
  }
}

variable "min_replicas" {
  description = "Minimum number of replicas for the container app."
  type        = number
  default     = 1

  validation {
    condition     = var.min_replicas >= 0 && var.min_replicas <= 10
    error_message = "min_replicas must be between 0 and 10."
  }
}

variable "max_replicas" {
  description = "Maximum number of replicas for the container app."
  type        = number
  default     = 3

  validation {
    condition     = var.max_replicas >= 1 && var.max_replicas <= 20
    error_message = "max_replicas must be between 1 and 20."
  }
}

variable "enable_zone_redundancy" {
  description = "Enable zone redundancy for Container Apps managed environment."
  type        = bool
  default     = false
}

variable "container_app_infrastructure_subnet_id" {
  description = "Optional infrastructure subnet ID for Container Apps environment. Required when enable_zone_redundancy is true."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = !var.enable_zone_redundancy || var.container_app_infrastructure_subnet_id != null
    error_message = "container_app_infrastructure_subnet_id must be set when enable_zone_redundancy is true."
  }
}

variable "static_web_app_location" {
  description = "Region for the Static Web App."
  type        = string
  default     = "westeurope"
}

variable "static_web_app_sku" {
  description = "SKU for the Static Web App."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard"], var.static_web_app_sku)
    error_message = "static_web_app_sku must be one of: Free, Standard."
  }
}

variable "deploy_static_web_app" {
  description = "Controls whether the Static Web App resource is deployed by this Terraform stack."
  type        = bool
  default     = true
}

variable "api_base_url" {
  description = "Optional API base URL application setting on Static Web App."
  type        = string
  default     = ""
}

variable "db_administrator_login" {
  description = "Administrator login for the PostgreSQL Flexible Server."
  type        = string
  default     = "naasadmin"
}

variable "db_administrator_password" {
  description = "Administrator password for the PostgreSQL Flexible Server."
  type        = string
  sensitive   = true
}

variable "jwt_signing_key" {
  description = "JWT signing key used to sign authentication tokens."
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Database name to create on the PostgreSQL server."
  type        = string
  default     = "naas"
}

variable "blob_container_name" {
  description = "Name of the blob container to create."
  type        = string
  default     = "uploads"
}

variable "postgres_sku_name" {
  description = "SKU name for PostgreSQL Flexible Server (azurerm format: <tier>_<sku>, e.g. B_Standard_B1ms)."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "16"

  validation {
    condition     = contains(["14", "15", "16"], var.postgres_version)
    error_message = "postgres_version must be one of: 14, 15, 16."
  }
}

variable "postgres_storage_size_gb" {
  description = "Storage size in GB for PostgreSQL Flexible Server."
  type        = number
  default     = 32
}

variable "additional_tags" {
  description = "Additional tags to merge with default tags."
  type        = map(string)
  default     = {}
}

variable "app_insights_workspace_resource_id" {
  description = "Optional Log Analytics Workspace Resource ID for Application Insights. Null disables Application Insights."
  type        = string
  default     = null
  nullable    = true
}
