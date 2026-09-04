output "repository_url" { value = module.github.repository_url }
output "state_backend" {
  value = {
    resource_group_name  = module.azure.state_resource_group_name
    storage_account_name = module.azure.state_storage_account_name
    container_name       = module.azure.state_container_name
    key                  = "aro.tfstate"
  }
}
output "pipeline_client_ids" {
  value     = module.azure.client_ids
  sensitive = true
}
