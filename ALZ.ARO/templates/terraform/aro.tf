locals {
  managed_resource_group_name = coalesce(var.managed_resource_group_name, "rg-${var.cluster_name}-managed")
}

resource "azurerm_role_assignment" "aro_resource_provider_network" {
  provider           = azurerm.workload
  scope              = azurerm_virtual_network.aro.id
  role_definition_id = "/subscriptions/${var.workload_subscription_id}/providers/Microsoft.Authorization/roleDefinitions/42f3c60f-e7b1-46d7-ba56-6de681664342"
  principal_id       = var.aro_resource_provider_object_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "aro_resource_provider_nsg" {
  provider           = azurerm.workload
  for_each           = azurerm_network_security_group.aro
  scope              = each.value.id
  role_definition_id = "/subscriptions/${var.workload_subscription_id}/providers/Microsoft.Authorization/roleDefinitions/42f3c60f-e7b1-46d7-ba56-6de681664342"
  principal_id       = var.aro_resource_provider_object_id
  principal_type     = "ServicePrincipal"
}

# In spoke mode the cluster subnets carry a user defined route. The resource
# provider validates and programs that route table during installation and
# fails with InvalidResourceProviderPermissions without this grant.
resource "azurerm_role_assignment" "aro_resource_provider_route_table" {
  provider           = azurerm.workload
  count              = local.is_spoke ? 1 : 0
  scope              = azurerm_route_table.egress[0].id
  role_definition_id = "/subscriptions/${var.workload_subscription_id}/providers/Microsoft.Authorization/roleDefinitions/42f3c60f-e7b1-46d7-ba56-6de681664342"
  principal_id       = var.aro_resource_provider_object_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_redhat_openshift_cluster" "aro" {
  provider            = azurerm.workload
  name                = var.cluster_name
  location            = azurerm_resource_group.aro.location
  resource_group_name = azurerm_resource_group.aro.name
  tags                = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aro["aro-cluster"].id]
  }

  cluster_profile {
    domain                      = var.aro_domain
    version                     = var.aro_version
    pull_secret                 = local.pull_secret
    managed_resource_group_name = local.managed_resource_group_name
    fips_enabled                = var.fips_enabled
  }

  network_profile {
    pod_cidr     = var.pod_cidr
    service_cidr = var.service_cidr
    # UserDefinedRouting is required when egress is forced to the hub NVA, and it
    # stops ARO provisioning a public outbound IP. It requires a private cluster.
    outbound_type                                = local.is_spoke ? "UserDefinedRouting" : "Loadbalancer"
    preconfigured_network_security_group_enabled = true
  }

  main_profile {
    subnet_id                  = azurerm_subnet.control_plane.id
    vm_size                    = var.control_plane_vm_size
    encryption_at_host_enabled = var.encryption_at_host_enabled
    disk_encryption_set_id     = var.disk_encryption_set_id
  }

  worker_profile {
    subnet_id                  = azurerm_subnet.worker.id
    vm_size                    = var.worker_vm_size
    disk_size_gb               = var.worker_disk_size_gb
    node_count                 = var.worker_node_count
    encryption_at_host_enabled = var.encryption_at_host_enabled
    disk_encryption_set_id     = var.disk_encryption_set_id
  }

  api_server_profile { visibility = "Private" }
  ingress_profile { visibility = "Private" }

  platform_workload_identity_profile {
    dynamic "platform_workload_identity" {
      for_each = local.aro_operator_identities
      content {
        name        = platform_workload_identity.key
        identity_id = platform_workload_identity.value.id
      }
    }
  }

  depends_on = [
    azurerm_role_assignment.cluster_federated_credential,
    azurerm_role_assignment.operator_subnet,
    azurerm_role_assignment.operator_vnet,
    azurerm_role_assignment.operator_route_table,
    azurerm_role_assignment.operator_nsg,
    azurerm_role_assignment.aro_resource_provider_network,
    azurerm_role_assignment.aro_resource_provider_nsg,
    azurerm_role_assignment.aro_resource_provider_route_table,
    azurerm_subnet_network_security_group_association.control_plane,
    azurerm_subnet_network_security_group_association.worker,
    azurerm_subnet_route_table_association.control_plane,
    azurerm_subnet_route_table_association.worker,
    azurerm_virtual_network_peering.aro_to_hub,
    azurerm_virtual_network_peering.hub_to_aro
  ]
}
