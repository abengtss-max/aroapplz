locals {
  pull_secret                                  = try(trimspace(var.pull_secret), "") == "" ? null : var.pull_secret
  application_gateway_ssl_certificate_data     = try(trimspace(var.application_gateway_ssl_certificate_data), "") == "" ? null : var.application_gateway_ssl_certificate_data
  application_gateway_ssl_certificate_password = try(var.application_gateway_ssl_certificate_password, "") == "" ? null : var.application_gateway_ssl_certificate_password
  application_gateway_backend_root_certificate = try(trimspace(var.application_gateway_backend_root_certificate), "") == "" ? null : var.application_gateway_backend_root_certificate
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
  }
}

resource "azurerm_resource_group" "aro" {
  provider = azurerm.workload
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}
