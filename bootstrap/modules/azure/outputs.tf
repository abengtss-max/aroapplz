output "state_resource_group_name" { value = azurerm_resource_group.state.name }
output "state_storage_account_name" { value = azapi_resource.state.name }
output "state_container_name" { value = azapi_resource.state_container.name }
output "client_ids" {
  value = { for key, identity in azurerm_user_assigned_identity.pipeline : key => identity.client_id }
}
output "principal_ids" {
  value = { for key, identity in azurerm_user_assigned_identity.pipeline : key => identity.principal_id }
}
output "aro_resource_provider_object_id" {
  value = data.azuread_service_principal.aro_resource_provider.object_id
}
output "runner" {
  value = var.use_self_hosted_runner ? {
    resource_group_name = azurerm_resource_group.state.name
    vm_name             = azurerm_linux_virtual_machine.runner[0].name
    public_ip_address   = azurerm_public_ip.runner[0].ip_address
  } : null
}
