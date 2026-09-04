output "state_resource_group_name" { value = azurerm_resource_group.state.name }
output "state_storage_account_name" { value = azurerm_storage_account.state.name }
output "state_container_name" { value = azurerm_storage_container.state.name }
output "client_ids" {
  value = { for key, principal in azuread_service_principal.pipeline : key => principal.client_id }
}
output "principal_ids" {
  value = { for key, principal in azuread_service_principal.pipeline : key => principal.object_id }
}
