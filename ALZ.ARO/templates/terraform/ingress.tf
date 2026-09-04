locals {
  application_gateway_enabled = var.ingress_mode == "application_gateway"
}

# Front Door remains an explicit follow-on contract because a private ARO origin
# requires a separately governed Private Link/origin design.
resource "terraform_data" "front_door_integration" {
  count = var.ingress_mode == "front_door" ? 1 : 0
  input = {
    status       = "integration-required"
    cluster_id   = azurerm_redhat_openshift_cluster.aro.id
    ingress_mode = var.ingress_mode
  }
}

resource "azurerm_public_ip" "application_gateway" {
  provider            = azurerm.workload
  count               = local.application_gateway_enabled ? 1 : 0
  name                = "pip-agw-${var.cluster_name}"
  location            = azurerm_resource_group.aro.location
  resource_group_name = azurerm_resource_group.aro.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = substr(lower(replace("agw-${var.cluster_name}", "_", "-")), 0, 63)
  tags                = var.tags
}

resource "azurerm_application_gateway" "aro" {
  provider            = azurerm.workload
  count               = local.application_gateway_enabled ? 1 : 0
  name                = "agw-${var.cluster_name}"
  location            = azurerm_resource_group.aro.location
  resource_group_name = azurerm_resource_group.aro.name
  http2_enabled       = true
  tags                = var.tags

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = var.application_gateway_capacity
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
    subnet_id = azurerm_subnet.application_gateway[0].id
  }

  frontend_ip_configuration {
    name                 = "public-frontend"
    public_ip_address_id = azurerm_public_ip.application_gateway[0].id
  }

  frontend_port {
    name = "https"
    port = 443
  }

  backend_address_pool {
    name         = "aro-private-ingress"
    ip_addresses = [azurerm_redhat_openshift_cluster.aro.ingress_profile[0].ip_address]
  }

  probe {
    name                                      = "aro-https-probe"
    protocol                                  = "Https"
    host                                      = var.application_gateway_backend_host_name
    path                                      = "/"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = false

    match {
      status_code = ["200-399"]
    }
  }

  backend_http_settings {
    name                  = "aro-https"
    cookie_based_affinity = "Disabled"
    port                  = 443
    protocol              = "Https"
    host_name             = var.application_gateway_backend_host_name
    request_timeout       = 60
    probe_name            = "aro-https-probe"
  }

  ssl_certificate {
    name     = "frontend-pfx"
    data     = var.application_gateway_ssl_certificate_data
    password = var.application_gateway_ssl_certificate_password
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
      condition     = length(trimspace(coalesce(var.application_gateway_ssl_certificate_data, ""))) > 0 && length(coalesce(var.application_gateway_ssl_certificate_password, "")) > 0
      error_message = "Application Gateway requires a base64-encoded PFX and password supplied through the protected runtime inputs."
    }
  }
}

resource "azurerm_log_analytics_workspace" "application_gateway" {
  provider            = azurerm.workload
  count               = local.application_gateway_enabled ? 1 : 0
  name                = "law-agw-${var.cluster_name}"
  location            = azurerm_resource_group.aro.location
  resource_group_name = azurerm_resource_group.aro.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "application_gateway" {
  provider                   = azurerm.workload
  count                      = local.application_gateway_enabled ? 1 : 0
  name                       = "send-to-log-analytics"
  target_resource_id         = azurerm_application_gateway.aro[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.application_gateway[0].id

  enabled_log { category = "ApplicationGatewayAccessLog" }
  enabled_log { category = "ApplicationGatewayPerformanceLog" }
  enabled_log { category = "ApplicationGatewayFirewallLog" }
  enabled_metric { category = "AllMetrics" }
}
