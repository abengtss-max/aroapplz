output "endpoint_host_name" {
  value = azurerm_cdn_frontdoor_endpoint.aro.host_name
}

output "profile_id" {
  value = azurerm_cdn_frontdoor_profile.aro.id
}

output "private_link_service_id" {
  value = azurerm_private_link_service.aro.id
}

# Front Door only issues the managed certificate once these records exist in public DNS.
output "custom_domain_validation" {
  description = "DNS records required to activate the custom domain."
  value = var.custom_domain == "" ? null : {
    txt_record_name  = "_dnsauth.${split(".", var.custom_domain)[0]}"
    txt_record_value = azurerm_cdn_frontdoor_custom_domain.aro[0].validation_token
    cname_record     = split(".", var.custom_domain)[0]
    cname_target     = azurerm_cdn_frontdoor_endpoint.aro.host_name
  }
}
