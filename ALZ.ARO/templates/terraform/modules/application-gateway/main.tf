terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      version               = "~> 5.2"
      configuration_aliases = [azurerm.workload]
    }
  }
}

resource "azurerm_public_ip" "this" {
  provider            = azurerm.workload
  name                = "pip-agw-${var.cluster_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = substr(lower(replace("agw-${var.cluster_name}", "_", "-")), 0, 63)
  tags                = var.tags
}

resource "azurerm_application_gateway" "this" {
  provider            = azurerm.workload
  name                = "agw-${var.cluster_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  http2_enabled       = true
  tags                = var.tags

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = var.capacity
  }

  waf_configuration {
    enabled          = true
    firewall_mode    = "Prevention"
    rule_set_type    = "OWASP"
    rule_set_version = "3.2"
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101S"
  }

  gateway_ip_configuration {
    name      = "gateway-ip-configuration"
    subnet_id = var.subnet_id
  }

  frontend_ip_configuration {
    name                 = "public-frontend"
    public_ip_address_id = azurerm_public_ip.this.id
  }

  frontend_port {
    name = "https"
    port = 443
  }

  backend_address_pool {
    name         = "aro-private-ingress"
    ip_addresses = [var.backend_ip_address]
  }

  probe {
    name                                      = "aro-https-probe"
    protocol                                  = "Https"
    host                                      = var.backend_host_name
    path                                      = "/"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = false

    match {
      status_code = ["200-399"]
    }
  }

  # OpenShift serves *.apps routes with a self-signed certificate, which the gateway rejects until its root is trusted.
  dynamic "trusted_root_certificate" {
    for_each = var.backend_root_certificate == null ? toset([]) : toset(["aro-ingress-root"])
    content {
      name = trusted_root_certificate.value
      data = var.backend_root_certificate
    }
  }

  backend_http_settings {
    name                           = "aro-https"
    cookie_based_affinity          = "Disabled"
    port                           = 443
    protocol                       = "Https"
    host_name                      = var.backend_host_name
    request_timeout                = 60
    probe_name                     = "aro-https-probe"
    trusted_root_certificate_names = var.backend_root_certificate == null ? null : ["aro-ingress-root"]
  }

  ssl_certificate {
    name     = "frontend-pfx"
    data     = var.ssl_certificate_data
    password = var.ssl_certificate_password
  }

  http_listener {
    name                           = "https"
    frontend_ip_configuration_name = "public-frontend"
    frontend_port_name             = "https"
    protocol                       = "Https"
    ssl_certificate_name           = "frontend-pfx"
  }

  request_routing_rule {
    name                       = "https"
    rule_type                  = "Basic"
    priority                   = 100
    http_listener_name         = "https"
    backend_address_pool_name  = "aro-private-ingress"
    backend_http_settings_name = "aro-https"
  }

  lifecycle {
    precondition {
      condition     = var.ssl_certificate_data != null && var.ssl_certificate_password != null
      error_message = "Application Gateway requires a base64-encoded PFX and password supplied through the protected runtime inputs."
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  provider                   = azurerm.workload
  name                       = "send-to-log-analytics"
  target_resource_id         = azurerm_application_gateway.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "ApplicationGatewayAccessLog" }
  enabled_log { category = "ApplicationGatewayPerformanceLog" }
  enabled_log { category = "ApplicationGatewayFirewallLog" }
  enabled_metric { category = "AllMetrics" }
}
