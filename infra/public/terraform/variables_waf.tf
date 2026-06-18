variable "app_gateway_restrict_docs_by_ip" {
  type        = bool
  default     = false
  description = "Enable IP restriction for /docs and /openapi/v1.json."
}

variable "app_gateway_docs_allowed_cidrs" {
  type        = list(string)
  default     = []
  description = "Allowed CIDRs for /docs and /openapi/v1.json when IP restriction is enabled."
}
