output "cluster_id" { value = azurerm_redhat_openshift_cluster.aro.id }
output "cluster_name" { value = azurerm_redhat_openshift_cluster.aro.name }
output "aro_vnet_id" { value = azurerm_virtual_network.aro.id }
output "control_plane_subnet_id" { value = azurerm_subnet.control_plane.id }
output "worker_subnet_id" { value = azurerm_subnet.worker.id }
output "console_url" { value = azurerm_redhat_openshift_cluster.aro.console_url }
output "ingress_status" {
  value = var.ingress_mode == "none" ? "none" : (
    var.ingress_mode == "front_door" ? "follow-on integration required" : "application_gateway preview; no gateway provisioned"
  )
}
