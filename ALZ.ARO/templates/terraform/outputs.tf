output "cluster_id" { value = azurerm_redhat_openshift_cluster.aro.id }
output "cluster_name" { value = azurerm_redhat_openshift_cluster.aro.name }
output "aro_vnet_id" { value = azurerm_virtual_network.aro.id }
output "control_plane_subnet_id" { value = azurerm_subnet.control_plane.id }
output "worker_subnet_id" { value = azurerm_subnet.worker.id }
output "console_url" { value = azurerm_redhat_openshift_cluster.aro.console_url }
output "ingress_status" {
  value = var.ingress_mode == "none" ? "none" : (
    var.ingress_mode == "front_door" ? "follow-on integration required" : "application_gateway provisioned"
  )
}
output "application_gateway_public_ip" {
  value = var.ingress_mode == "application_gateway" ? azurerm_public_ip.application_gateway[0].ip_address : null
}
output "application_gateway_fqdn" {
  value = var.ingress_mode == "application_gateway" ? azurerm_public_ip.application_gateway[0].fqdn : null
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
