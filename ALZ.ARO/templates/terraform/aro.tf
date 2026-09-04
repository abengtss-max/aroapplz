resource "azurerm_role_assignment" "aro_service_principal_network" {
  provider             = azurerm.workload
  scope                = azurerm_virtual_network.aro.id
  role_definition_name = "Network Contributor"
  principal_id         = var.aro_service_principal_object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "aro_resource_provider_network" {
  provider             = azurerm.workload
  scope                = azurerm_virtual_network.aro.id
  role_definition_name = "Network Contributor"
  principal_id         = var.aro_resource_provider_object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_redhat_openshift_cluster" "aro" {
  provider            = azurerm.workload
  name                = var.cluster_name
  location            = azurerm_resource_group.aro.location
  resource_group_name = azurerm_resource_group.aro.name
  tags                = var.tags

  cluster_profile {
    domain      = var.aro_domain
    version     = var.aro_version
    pull_secret = var.pull_secret
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

  service_principal {
    client_id     = var.aro_service_principal_client_id
    client_secret = var.aro_service_principal_client_secret
  }

  depends_on = [
    azurerm_role_assignment.aro_service_principal_network,
    azurerm_role_assignment.aro_resource_provider_network,
    azurerm_subnet_route_table_association.control_plane,
    azurerm_subnet_route_table_association.worker,
    azurerm_virtual_network_peering.aro_to_hub,
    azurerm_virtual_network_peering.hub_to_aro
  ]
}
