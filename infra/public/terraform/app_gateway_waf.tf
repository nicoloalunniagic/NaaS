# ── Public WAF Infrastructure ─────────────────────────────────────────────────

resource "azurerm_virtual_network" "appgw" {
  name                = "${var.name_prefix}-agw-vnet"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.target.name
  address_space       = ["10.20.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "appgw" {
  name                 = "appgw-subnet"
  resource_group_name  = data.azurerm_resource_group.target.name
  virtual_network_name = azurerm_virtual_network.appgw.name
  address_prefixes     = ["10.20.0.0/24"]
}

resource "azurerm_public_ip" "appgw" {
  name                = "${var.name_prefix}-agw-pip"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.target.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

# ── WAF Policy ────────────────────────────────────────────────────────────────

resource "azurerm_web_application_firewall_policy" "appgw" {
  name                = "${var.name_prefix}-agw-waf"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.target.name
  tags                = local.tags

  policy_settings {
    enabled                          = true
    mode                             = "Prevention"
    request_body_check               = true
    file_upload_limit_in_mb          = 100
    max_request_body_size_in_kb      = 128
    request_body_inspect_limit_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }

  # SQL Injection blocking
  custom_rules {
    name      = "BlockSqliSignatures"
    priority  = 10
    action    = "Block"
    rule_type = "MatchRule"
    enabled   = true

    match_conditions {
      match_variables {
        variable_name = "QueryString"
      }
      operator           = "Contains"
      negation_condition = false
      match_values = [
        " or 1=1",
        "union select",
        "pg_sleep(",
        "information_schema"
      ]
      transforms = ["Lowercase", "UrlDecode"]
    }

    match_conditions {
      match_variables {
        variable_name = "RequestUri"
      }
      operator           = "Contains"
      negation_condition = false
      match_values = [
        " or 1=1",
        "union select",
        "pg_sleep(",
        "information_schema"
      ]
      transforms = ["Lowercase", "UrlDecode"]
    }
  }

  # XSS blocking
  custom_rules {
    name      = "BlockXssSignatures"
    priority  = 20
    action    = "Block"
    rule_type = "MatchRule"
    enabled   = true

    match_conditions {
      match_variables {
        variable_name = "QueryString"
      }
      operator           = "Contains"
      negation_condition = false
      match_values = [
        "<script",
        "onerror=",
        "onload=",
        "javascript:"
      ]
      transforms = ["Lowercase", "UrlDecode"]
    }

    match_conditions {
      match_variables {
        variable_name = "RequestUri"
      }
      operator           = "Contains"
      negation_condition = false
      match_values = [
        "<script",
        "onerror=",
        "onload=",
        "javascript:"
      ]
      transforms = ["Lowercase", "UrlDecode"]
    }
  }

  # Docs IP restriction (optional)
  # NOTE: Disabled in public topology. Enable by setting var.app_gateway_restrict_docs_by_ip = true
  # and providing CIDR ranges in var.app_gateway_docs_allowed_cidrs.
  custom_rules {
    name      = "BlockDocsFromNonAllowlist"
    priority  = 30
    action    = "Block"
    rule_type = "MatchRule"
    enabled   = var.app_gateway_restrict_docs_by_ip

    match_conditions {
      match_variables {
        variable_name = "RequestUri"
      }
      operator           = "Regex"
      negation_condition = false
      match_values = [
        "^/(docs|openapi/v1\\.json)(.*)?$"
      ]
      transforms = ["Lowercase"]
    }

    dynamic "match_conditions" {
      for_each = length(var.app_gateway_docs_allowed_cidrs) > 0 ? [1] : []
      content {
        match_variables {
          variable_name = "RemoteAddr"
        }
        operator           = "IPMatch"
        negation_condition = true
        match_values       = var.app_gateway_docs_allowed_cidrs
      }
    }
  }

  # Rate limiting
  custom_rules {
    name                 = "GlobalRateLimit"
    priority             = 40
    action               = "Block"
    rule_type            = "RateLimitRule"
    enabled              = true
    rate_limit_duration  = "OneMin"
    rate_limit_threshold = 300
    group_rate_limit_by  = "ClientAddr"

    match_conditions {
      match_variables {
        variable_name = "RequestUri"
      }
      operator           = "Contains"
      negation_condition = false
      match_values       = ["/"]
    }
  }
}

# ── Application Gateway ────────────────────────────────────────────────────────

resource "azurerm_application_gateway" "waf" {
  name                = "${var.name_prefix}-agw"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.target.name
  tags                = local.tags

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = 1
    max_capacity = 3
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_ip_configuration {
    name                 = "frontend-ip"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  frontend_port {
    name = "frontend-port-http"
    port = 80
  }

  backend_address_pool {
    name  = "backend-pool"
    fqdns = [azurerm_container_app.api.latest_revision_fqdn]
  }

  backend_http_settings {
    name                  = "backend-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 30

    probe_name                          = "backend-probe"
    pick_host_name_from_backend_address = true
  }

  probe {
    name                = "backend-probe"
    host                = azurerm_container_app.api.latest_revision_fqdn
    protocol            = "Https"
    path                = "/"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3

    match {
      status_code = ["200-399"]
    }
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "frontend-ip"
    frontend_port_name             = "frontend-port-http"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "default-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "backend-pool"
    backend_http_settings_name = "backend-http-settings"
    priority                   = 100
  }

  rewrite_rule_set {
    name = "security-header-rewrite"

    rewrite_rule {
      name          = "remove-server-header"
      rule_sequence = 10

      response_header_configuration {
        header_name  = "Server"
        header_value = ""
      }
    }
  }

  firewall_policy_id = azurerm_web_application_firewall_policy.appgw.id

  depends_on = [
    azurerm_web_application_firewall_policy.appgw,
  ]
}
