locals {
  application_gateway_enabled = var.ingress_mode == "application_gateway"
}

# Front Door remains an explicit follow-on contract because a private ARO origin
# requires a separately governed Private Link/origin design.
resource "terraform_data" "front_door_integration" {
  count = local.front_door_enabled ? 1 : 0
  input = {
    status       = "integration-required"
    cluster_id   = azurerm_redhat_openshift_cluster.aro.id
    ingress_mode = var.ingress_mode
  }
}

module "application_gateway" {
  source = "./modules/application-gateway"
  count  = local.application_gateway_enabled ? 1 : 0
  providers = {
    azurerm.workload = azurerm.workload
  }

  cluster_name               = var.cluster_name
  location                   = azurerm_resource_group.aro.location
  resource_group_name        = azurerm_resource_group.aro.name
  subnet_id                  = azurerm_subnet.application_gateway[0].id
  backend_ip_address         = azurerm_redhat_openshift_cluster.aro.ingress_profile[0].ip_address
  backend_host_name          = var.application_gateway_backend_host_name
  capacity                   = var.application_gateway_capacity
  ssl_certificate_data       = local.application_gateway_ssl_certificate_data
  ssl_certificate_password   = local.application_gateway_ssl_certificate_password
  backend_root_certificate   = local.application_gateway_backend_root_certificate
  log_analytics_workspace_id = local.log_analytics_workspace_id
  tags                       = var.tags
}
