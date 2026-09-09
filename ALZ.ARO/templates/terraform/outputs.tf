output "cluster_id" { value = azurerm_redhat_openshift_cluster.aro.id }
output "cluster_name" { value = azurerm_redhat_openshift_cluster.aro.name }
output "aro_vnet_id" { value = azurerm_virtual_network.aro.id }
output "control_plane_subnet_id" { value = azurerm_subnet.control_plane.id }
output "worker_subnet_id" { value = azurerm_subnet.worker.id }
output "console_url" { value = azurerm_redhat_openshift_cluster.aro.console_url }
output "ingress_status" {
  value = var.ingress_mode == "none" ? "none" : "front_door provisioned"
}
output "front_door_endpoint_host_name" {
  value = local.front_door_enabled ? module.front_door[0].endpoint_host_name : null
}
output "front_door_custom_domain_validation" {
  description = "DNS records to publish before Front Door issues the managed certificate."
  value       = local.front_door_enabled ? module.front_door[0].custom_domain_validation : null
}

output "log_analytics_workspace_id" {
  value = local.log_analytics_workspace_id
}

output "container_registry_login_server" {
  value = local.supporting_services_enabled ? module.supporting[0].container_registry_login_server : null
}

output "key_vault_uri" {
  value = local.supporting_services_enabled ? module.supporting[0].key_vault_uri : null
}
