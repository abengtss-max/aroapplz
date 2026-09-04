data "azurerm_subscription" "workload" {
  subscription_id = var.workload_subscription_id
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "state" {
  name     = var.names.state_resource_group
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "state" {
  name                            = var.names.state_storage
  resource_group_name             = azurerm_resource_group.state.name
  location                        = azurerm_resource_group.state.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  shared_access_key_enabled       = false
  public_network_access_enabled   = true
  allow_nested_items_to_be_public = false
  infrastructure_encryption_enabled = true
  tags                            = var.tags

  blob_properties {
    versioning_enabled = true
    change_feed_enabled = true
    delete_retention_policy { days = 30 }
    container_delete_retention_policy { days = 30 }
  }
}

resource "azurerm_storage_container" "state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

locals {
  pipelines = {
    plan  = var.names.plan_application
    apply = var.names.apply_application
  }
}

resource "azuread_application" "pipeline" {
  for_each               = local.pipelines
  display_name           = each.value
  prevent_duplicate_names = true
  sign_in_audience       = "AzureADMyOrg"
  owners                 = [data.azurerm_client_config.current.object_id]
}

resource "azuread_service_principal" "pipeline" {
  for_each  = local.pipelines
  client_id = azuread_application.pipeline[each.key].client_id
  owners    = [data.azurerm_client_config.current.object_id]
}

resource "azuread_application_federated_identity_credential" "github" {
  for_each       = local.pipelines
  application_id = azuread_application.pipeline[each.key].id
  display_name   = "github-${each.key}"
  description    = "GitHub environment OIDC; no Azure client secret."
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_organization}/${var.github_repository}:environment:${each.key}"
}

resource "azurerm_role_assignment" "plan_reader" {
  scope                = data.azurerm_subscription.workload.id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.pipeline["plan"].object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "apply_contributor" {
  scope                = data.azurerm_subscription.workload.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.pipeline["apply"].object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "state" {
  for_each             = local.pipelines
  scope                = azurerm_storage_container.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.pipeline[each.key].object_id
  principal_type       = "ServicePrincipal"
}
