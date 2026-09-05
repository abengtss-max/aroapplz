output "container_registry_id" {
  value = var.container_registry_enabled ? azurerm_container_registry.this[0].id : null
}

output "container_registry_login_server" {
  value = var.container_registry_enabled ? azurerm_container_registry.this[0].login_server : null
}

output "key_vault_id" {
  value = var.key_vault_enabled ? azurerm_key_vault.this[0].id : null
}

output "key_vault_uri" {
  value = var.key_vault_enabled ? azurerm_key_vault.this[0].vault_uri : null
}
