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
  }
}

resource "azurerm_resource_group" "aro" {
  provider = azurerm.workload
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}
