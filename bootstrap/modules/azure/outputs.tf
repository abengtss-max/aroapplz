output "state_resource_group_name" { value = azurerm_resource_group.state.name }
output "state_storage_account_name" { value = azurerm_storage_account.state.name }
output "state_container_name" { value = azurerm_storage_container.state.name }
output "client_ids" {
  value = { for key, identity in azurerm_user_assigned_identity.pipeline : key => identity.client_id }
}
output "principal_ids" {
  value = { for key, identity in azurerm_user_assigned_identity.pipeline : key => identity.principal_id }
}
output "aro_resource_provider_object_id" {
  value = data.azuread_service_principal.aro_resource_provider.object_id
}
