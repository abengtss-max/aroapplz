terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      version               = "~> 5.2"
      configuration_aliases = [azurerm.workload]
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

data "azurerm_resources" "internal_load_balancer" {
  provider            = azurerm.workload
  resource_group_name = var.managed_resource_group_name
  type                = "Microsoft.Network/loadBalancers"
}

data "azurerm_lb" "internal" {
  provider            = azurerm.workload
  name                = one([for lb in data.azurerm_resources.internal_load_balancer.resources : lb.name if endswith(lower(lb.name), "-internal")])
  resource_group_name = var.managed_resource_group_name
}

locals {
  # Selecting by address rather than by position, because frontend ordering is not a contract.
  ingress_frontend_ip_configuration_id = one([
    for configuration in data.azurerm_lb.internal.frontend_ip_configuration :
    configuration.id if configuration.private_ip_address == var.ingress_ip_address
  ])
}

resource "azurerm_private_link_service" "aro" {
  provider            = azurerm.workload
  name                = "pls-${var.cluster_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  nat_ip_configuration {
    name                       = "primary"
    private_ip_address_version = "IPv4"
    subnet_id                  = var.private_link_subnet_id
    primary                    = true
  }

  load_balancer_frontend_ip_configuration_ids = [local.ingress_frontend_ip_configuration_id]
  visibility_subscription_ids                 = [var.subscription_id]

  lifecycle {
    precondition {
      condition     = local.ingress_frontend_ip_configuration_id != null
      error_message = "No load balancer frontend matched the cluster ingress address; the cluster may not have finished provisioning."
    }
  }
}

resource "azurerm_cdn_frontdoor_profile" "aro" {
  provider            = azurerm.workload
  name                = "afd-${var.cluster_name}"
  resource_group_name = var.resource_group_name
  sku_name            = var.sku
  tags                = var.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "aro" {
  provider                 = azurerm.workload
  name                     = "fde-${var.cluster_name}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.aro.id
  tags                     = var.tags
}

resource "azurerm_cdn_frontdoor_origin_group" "aro" {
  provider                 = azurerm.workload
  name                     = "aro-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.aro.id

  health_probe {
    interval_in_seconds = 100
    path                = "/"
    protocol            = "Https"
    request_type        = "HEAD"
  }

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }
}

# Azure keeps the private endpoint connection for a while after the origin is deleted, and
# refuses to delete a Private Link Service that still has one. Ordering the origin behind this
# makes destroy wait between removing the origin and removing the service.
resource "time_sleep" "private_link_drain" {
  depends_on       = [azurerm_private_link_service.aro]
  destroy_duration = "300s"
}

resource "azurerm_cdn_frontdoor_origin" "aro" {
  provider                      = azurerm.workload
  name                          = "aro-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.aro.id
  enabled                       = true
  host_name                     = var.backend_host_name
  origin_host_header            = var.backend_host_name
  http_port                     = 80
  https_port                    = 443
  priority                      = 1
  weight                        = 500
  # Azure rejects a private link origin unless certificate name checking is on, so the
  # OpenShift ingress must present a publicly trusted certificate for backend_host_name.
  certificate_name_check_enabled = true

  private_link {
    request_message        = "Front Door origin for ${var.cluster_name}"
    location               = var.location
    private_link_target_id = azurerm_private_link_service.aro.id
  }

  depends_on = [time_sleep.private_link_drain]
}

# Without a route the endpoint accepts no traffic, which is the defect in the reference implementation.
resource "azurerm_cdn_frontdoor_route" "aro" {
  provider                      = azurerm.workload
  name                          = "default-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.aro.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.aro.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.aro.id]
  enabled                       = true
  forwarding_protocol           = "HttpsOnly"
  https_redirect_enabled        = true
  patterns_to_match             = ["/*"]
  supported_protocols           = ["Http", "Https"]
  link_to_default_domain        = true
}

resource "azurerm_cdn_frontdoor_firewall_policy" "aro" {
  provider            = azurerm.workload
  name                = replace("waf${var.cluster_name}", "-", "")
  resource_group_name = var.resource_group_name
  sku_name            = azurerm_cdn_frontdoor_profile.aro.sku_name
  enabled             = true
  mode                = var.waf_mode
  tags                = var.tags

  managed_rule {
    type    = "Microsoft_DefaultRuleSet"
    version = "2.1"
    action  = "Block"
  }

  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.0"
    action  = "Block"
  }
}

resource "azurerm_cdn_frontdoor_security_policy" "aro" {
  provider                 = azurerm.workload
  name                     = "waf-association"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.aro.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.aro.id

      association {
        patterns_to_match = ["/*"]

        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.aro.id
        }
      }
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "aro" {
  provider                   = azurerm.workload
  name                       = "send-to-log-analytics"
  target_resource_id         = azurerm_cdn_frontdoor_profile.aro.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "FrontDoorAccessLog" }
  enabled_log { category = "FrontDoorHealthProbeLog" }
  enabled_log { category = "FrontDoorWebApplicationFirewallLog" }
  enabled_metric { category = "AllMetrics" }
}
