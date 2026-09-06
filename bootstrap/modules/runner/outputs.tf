output "container_group_names" {
  value = [for group in azurerm_container_group.runner : group.name]
}

output "egress_ip_address" {
  description = "Outbound address the runners present, for hub firewall or GitHub allow lists."
  value       = azurerm_public_ip.runner.ip_address
}

output "container_registry_login_server" { value = azurerm_container_registry.runner.login_server }

output "virtual_network_id" { value = azurerm_virtual_network.runner.id }
