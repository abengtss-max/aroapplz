locals {
  application_gateway_enabled = var.ingress_mode == "application_gateway"
}

module "front_door" {
  source = "./modules/front-door"
  count  = local.front_door_enabled ? 1 : 0
  providers = {
    azurerm.workload = azurerm.workload
  }

  cluster_name                   = var.cluster_name
  location                       = azurerm_resource_group.aro.location
  resource_group_name            = azurerm_resource_group.aro.name
  managed_resource_group_name    = local.managed_resource_group_name
  ingress_ip_address             = azurerm_redhat_openshift_cluster.aro.ingress_profile[0].ip_address
  private_link_subnet_id         = azurerm_subnet.front_door[0].id
  backend_host_name              = var.front_door_backend_host_name
  certificate_name_check_enabled = var.front_door_certificate_name_check_enabled
  sku                            = var.front_door_sku
  waf_mode                       = var.front_door_waf_mode
  subscription_id                = var.workload_subscription_id
  log_analytics_workspace_id     = local.log_analytics_workspace_id
  tags                           = var.tags
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
