module "front_door" {
  source = "./modules/front-door"
  count  = local.front_door_enabled ? 1 : 0
  providers = {
    azurerm.workload = azurerm.workload
  }

  # The module reads the cluster's internal load balancer, which only exists after the
  # cluster is created; without this the data source resolves to null during the first plan.
  depends_on = [azurerm_redhat_openshift_cluster.aro]

  cluster_name                = var.cluster_name
  location                    = azurerm_resource_group.aro.location
  resource_group_name         = azurerm_resource_group.aro.name
  managed_resource_group_name = local.managed_resource_group_name
  ingress_ip_address          = azurerm_redhat_openshift_cluster.aro.ingress_profile[0].ip_address
  private_link_subnet_id      = azurerm_subnet.front_door[0].id
  backend_host_name           = var.front_door_backend_host_name
  custom_domain               = var.front_door_custom_domain
  sku                         = var.front_door_sku
  waf_mode                    = var.front_door_waf_mode
  subscription_id             = var.workload_subscription_id
  log_analytics_workspace_id  = local.log_analytics_workspace_id
  tags                        = var.tags
}
