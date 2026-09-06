locals {
  runner_image = "${azurerm_container_registry.runner.login_server}/${var.names.runner_image}:${var.runner_image_tag}"

  runners = {
    for index in range(var.runner_count) :
    format("%02d", index + 1) => "${var.names.runner_container_group}-${format("%02d", index + 1)}"
  }

  private_dns_zones = {
    blob = "privatelink.blob.core.windows.net"
    acr  = "privatelink.azurecr.io"
  }
}

resource "azurerm_public_ip" "runner" {
  name                = var.names.runner_public_ip
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = var.tags
}

# Runners egress through a NAT gateway so their outbound traffic presents one
# known address that a hub firewall or GitHub allow list can name.
resource "azurerm_nat_gateway" "runner" {
  name                    = var.names.runner_nat_gateway
  resource_group_name     = var.resource_group_name
  location                = var.location
  sku_name                = "Standard"
  idle_timeout_in_minutes = 4
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "runner" {
  nat_gateway_id       = azurerm_nat_gateway.runner.id
  public_ip_address_id = azurerm_public_ip.runner.id
}

resource "azurerm_virtual_network" "runner" {
  name                = var.names.runner_virtual_network
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.virtual_network_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = var.names.runner_subnet_private_endpoints
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.runner.name
  address_prefixes     = [var.private_endpoint_subnet_cidr]
}

resource "azurerm_subnet" "container_instances" {
  name                 = var.names.runner_subnet_container_instances
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.runner.name
  address_prefixes     = [var.container_instances_subnet_cidr]

  delegation {
    name = "Microsoft.ContainerInstance.containerGroups"
    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet_nat_gateway_association" "container_instances" {
  subnet_id      = azurerm_subnet.container_instances.id
  nat_gateway_id = azurerm_nat_gateway.runner.id
}

resource "azurerm_private_dns_zone" "runner" {
  for_each            = local.private_dns_zones
  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "runner" {
  for_each              = local.private_dns_zones
  name                  = "vnetlink-${each.key}-bootstrap"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.runner[each.key].name
  virtual_network_id    = azurerm_virtual_network.runner.id
  registration_enabled  = false
  tags                  = var.tags
}

# Gives the runners a private route to the Terraform backend, which they need
# because the state account denies public network access.
resource "azurerm_private_endpoint" "state_blob" {
  name                = var.names.state_private_endpoint
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-state-blob"
    private_connection_resource_id = var.state_storage_account_id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.runner["blob"].id]
  }
}

resource "azurerm_container_registry" "runner" {
  name                = var.names.runner_container_registry
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Premium"
  admin_enabled       = false

  # ACR Tasks build on Azure-managed public agents that cannot reach a
  # private-only registry, so public access stays on while the private endpoint
  # keeps the runners' pull traffic inside the virtual network.
  public_network_access_enabled = true
  network_rule_bypass_option    = "AzureServices"
  zone_redundancy_enabled       = true
  data_endpoint_enabled         = true
  retention_policy_in_days      = 7

  tags = var.tags
}

resource "azurerm_private_endpoint" "container_registry" {
  name                = var.names.runner_registry_private_endpoint
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-registry"
    private_connection_resource_id = azurerm_container_registry.runner.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "registry"
    private_dns_zone_ids = [azurerm_private_dns_zone.runner["acr"].id]
  }
}

# Built from the Azure Verified Modules runner image, so the image contents stay
# owned upstream instead of being vendored into this repository.
resource "azurerm_container_registry_task" "runner_image" {
  name                  = "build-${var.names.runner_image}"
  container_registry_id = azurerm_container_registry.runner.id

  platform {
    os = "Linux"
  }

  docker_step {
    dockerfile_path      = "Dockerfile"
    context_path         = "https://github.com/Azure/avm-container-images-cicd-agents-and-runners.git#57a937f:github-runner-aci"
    context_access_token = "ignored" # public repository, but the provider requires a value
    image_names          = ["${var.names.runner_image}:${var.runner_image_tag}"]
    push_enabled         = true
  }
}

resource "azurerm_container_registry_task_schedule_run_now" "runner_image" {
  container_registry_task_id = azurerm_container_registry_task.runner_image.id
}

resource "azurerm_user_assigned_identity" "runner" {
  name                = var.names.runner_identity
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "runner_acr_pull" {
  scope                = azurerm_container_registry.runner.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.runner.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_container_group" "runner" {
  for_each            = local.runners
  name                = each.value
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  restart_policy      = "Always"
  zones               = ["1"]
  tags                = var.tags

  ip_address_type = "Private"
  subnet_ids      = [azurerm_subnet.container_instances.id]

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.runner.id]
  }

  image_registry_credential {
    server                    = azurerm_container_registry.runner.login_server
    user_assigned_identity_id = azurerm_user_assigned_identity.runner.id
  }

  container {
    name   = "runner"
    image  = local.runner_image
    cpu    = var.runner_cpu
    memory = var.runner_memory_gb

    # Registration is scoped to the generated repository rather than the whole
    # organization, so a runner can only ever accept jobs for this landing zone.
    # GH_RUNNER_MODE is deliberately unset, which leaves the image in its default
    # ephemeral mode: the container exits after one job and the restart policy
    # registers a fresh runner, so no workspace or credential survives a job.
    environment_variables = {
      GH_RUNNER_URL  = "https://github.com/${var.github_organization}/${var.github_repository}"
      GH_RUNNER_NAME = each.value
    }

    secure_environment_variables = {
      GH_RUNNER_TOKEN = var.github_runner_token
    }

    ports {
      port     = 80
      protocol = "TCP"
    }
  }

  depends_on = [
    azurerm_container_registry_task_schedule_run_now.runner_image,
    azurerm_role_assignment.runner_acr_pull,
    azurerm_private_endpoint.container_registry,
    azurerm_subnet_nat_gateway_association.container_instances,
  ]
}
