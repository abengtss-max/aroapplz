output "endpoint_host_name" {
  value = azurerm_cdn_frontdoor_endpoint.aro.host_name
}

output "profile_id" {
  value = azurerm_cdn_frontdoor_profile.aro.id
}

output "private_link_service_id" {
  value = azurerm_private_link_service.aro.id
}
