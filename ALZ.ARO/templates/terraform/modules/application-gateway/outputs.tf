output "id" {
  value = azurerm_application_gateway.this.id
}

output "public_ip_address" {
  value = azurerm_public_ip.this.ip_address
}

output "fqdn" {
  value = azurerm_public_ip.this.fqdn
}
