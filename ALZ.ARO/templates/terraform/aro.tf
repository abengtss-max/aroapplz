resource "azurerm_role_assignment" "aro_resource_provider_network" {
  provider           = azurerm.workload
  scope              = azurerm_virtual_network.aro.id
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
    domain      = var.aro_domain
    version     = var.aro_version
    pull_secret = local.pull_secret
  }

  network_profile {
    pod_cidr     = var.pod_cidr
    service_cidr = var.service_cidr
  }

  main_profile {
    subnet_id = azurerm_subnet.control_plane.id
    vm_size   = var.control_plane_vm_size
  }

  worker_profile {
    subnet_id    = azurerm_subnet.worker.id
    vm_size      = var.worker_vm_size
    disk_size_gb = var.worker_disk_size_gb
    node_count   = var.worker_node_count
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
    azurerm_role_assignment.aro_resource_provider_network,
    azurerm_subnet_route_table_association.control_plane,
    azurerm_subnet_route_table_association.worker,
    azurerm_virtual_network_peering.aro_to_hub,
    azurerm_virtual_network_peering.hub_to_aro
  ]
}
