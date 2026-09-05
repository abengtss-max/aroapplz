locals {
  pull_secret                                  = try(trimspace(var.pull_secret), "") == "" ? null : var.pull_secret
  application_gateway_ssl_certificate_data     = try(trimspace(var.application_gateway_ssl_certificate_data), "") == "" ? null : var.application_gateway_ssl_certificate_data
  application_gateway_ssl_certificate_password = try(var.application_gateway_ssl_certificate_password, "") == "" ? null : var.application_gateway_ssl_certificate_password
  application_gateway_backend_root_certificate = try(trimspace(var.application_gateway_backend_root_certificate), "") == "" ? null : var.application_gateway_backend_root_certificate

  front_door_enabled          = var.ingress_mode == "front_door"
  supporting_services_enabled = var.container_registry_enabled || var.key_vault_enabled
  log_analytics_workspace_id  = var.log_analytics_workspace_id != "" ? var.log_analytics_workspace_id : module.monitoring[0].workspace_id
}

resource "terraform_data" "input_contract" {
  input = var.deployment_mode
  lifecycle {
    precondition {
      condition = var.deployment_mode == "standalone" || (
        var.connectivity_subscription_id != "" &&
        var.hub_vnet_id != "" &&
        var.next_hop_ip != ""
      )
      error_message = "spoke requires connectivity_subscription_id, hub_vnet_id, and next_hop_ip."
    }
    precondition {
      condition     = var.deployment_mode != "spoke" || startswith(lower(var.hub_vnet_id), "/subscriptions/${lower(var.connectivity_subscription_id)}/")
      error_message = "hub_vnet_id must belong to connectivity_subscription_id."
    }
    precondition {
      condition = var.ingress_mode != "application_gateway" || (
        var.application_gateway_subnet_cidr != "" &&
        var.application_gateway_backend_host_name != ""
      )
      error_message = "application_gateway requires application_gateway_subnet_cidr and application_gateway_backend_host_name."
    }
    precondition {
      condition = (
        local.application_gateway_ssl_certificate_data == null &&
        local.application_gateway_ssl_certificate_password == null
        ) || (
        local.application_gateway_ssl_certificate_data != null &&
        local.application_gateway_ssl_certificate_password != null
      )
      error_message = "Application Gateway PFX data and password must either both be set or both be omitted."
    }
    precondition {
      condition     = !local.supporting_services_enabled || var.private_endpoint_subnet_cidr != ""
      error_message = "private_endpoint_subnet_cidr is required when container_registry_enabled or key_vault_enabled is true."
    }
    precondition {
      condition     = var.ingress_mode != "front_door" || var.front_door_subnet_cidr != ""
      error_message = "front_door_subnet_cidr is required when ingress_mode is front_door."
    }
    precondition {
      condition     = var.ingress_mode != "front_door" || var.front_door_backend_host_name != ""
      error_message = "front_door_backend_host_name is required when ingress_mode is front_door."
    }
  }
}

resource "azurerm_resource_group" "aro" {
  provider = azurerm.workload
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

module "monitoring" {
  source = "./modules/monitoring"
  count  = var.log_analytics_workspace_id == "" ? 1 : 0
  providers = {
    azurerm.workload = azurerm.workload
  }

  name                = "law-${var.cluster_name}"
  location            = azurerm_resource_group.aro.location
  resource_group_name = azurerm_resource_group.aro.name
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

module "supporting" {
  source = "./modules/supporting"
  count  = local.supporting_services_enabled ? 1 : 0
  providers = {
    azurerm.workload = azurerm.workload
  }

  cluster_name               = var.cluster_name
  location                   = azurerm_resource_group.aro.location
  resource_group_name        = azurerm_resource_group.aro.name
  resource_group_id          = azurerm_resource_group.aro.id
  tenant_id                  = var.tenant_id
  virtual_network_id         = azurerm_virtual_network.aro.id
  private_endpoint_subnet_id = azurerm_subnet.private_endpoints[0].id
  container_registry_enabled = var.container_registry_enabled
  container_registry_sku     = var.container_registry_sku
  key_vault_enabled          = var.key_vault_enabled
  tags                       = var.tags
}
