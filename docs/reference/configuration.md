# Configuration reference

The module accepts JSON so PowerShell 7 requires no additional YAML parser. Sample files contain placeholders, not deployable identifiers or secrets:

- [`config/standalone.json`](https://github.com/abengtss-max/aroapplz/blob/main/config/standalone.json)
- [`config/spoke.json`](https://github.com/abengtss-max/aroapplz/blob/main/config/spoke.json)

Copy one to the ignored `config/local.json` before editing.

## Shared bootstrap inputs

| Field | Required | Meaning |
| --- | --- | --- |
| `deployment_mode` | Yes | Exactly `standalone` or `spoke` |
| `tenant_id` | Yes | Microsoft Entra tenant for managed identities and workload authentication |
| `bootstrap_subscription_id` | Yes | Subscription for bootstrap Azure resources |
| `workload_subscription_id` | Yes | Subscription for the new ARO workload |
| `location` | Yes | Azure region used for resources and ARO version discovery |
| `service_name` | Yes | Short service component used in generated names |
| `environment_name` | Yes | Environment component used in generated names |
| `github_organization` | Yes | GitHub organization or owner for the generated repository |
| `github_repository` | Yes | Name of the new private workload repository |
| `apply_approvers` | Yes | Non-empty array of GitHub usernames used for private-repository environment protection when the owner has GitHub Enterprise |
| `runner_label` | No | Label of a GitHub runner your organization already operates, used by the generated CI/CD callers. Defaults to `ubuntu-latest`. The accelerator never provisions runners |

Preflight derives `apply_environment_reviewers_enabled` from the GitHub owner plan and writes it only to generated bootstrap input. It is not a user-supplied configuration field. Non-Enterprise owners receive a warning because GitHub does not support the reviewer rule for their generated private repository.

Generated workload names include `rg-<service>-<environment>-aro` and `aro-<service>-<environment>`.

For `standalone`, the empty connectivity subscription value is omitted from generated GitHub Actions variables; the generated Terraform configuration selects the workload subscription. `spoke` publishes and uses the configured connectivity subscription ID.

## ARO and network inputs

| Field | Required | Meaning |
| --- | --- | --- |
| `aro_version` | Resolved before plan | Empty for newest returned regional version, or an exact version to validate |
| `aro_domain` | Yes | Unique ARO domain prefix |
| `aro_vnet_cidr` | Yes | CIDR for the new ARO VNet |
| `control_plane_subnet_cidr` | Yes | CIDR for the new control-plane subnet |
| `worker_subnet_cidr` | Yes | CIDR for the new worker subnet |
| `private_endpoint_subnet_cidr` | Supporting services only | Subnet holding private endpoints for the registry and vault. Required unless both are disabled |
| `front_door_subnet_cidr` | Front Door only | Subnet holding the Private Link Service NAT addresses |
| `front_door_backend_host_name` | Front Door only | OpenShift application hostname used as the Front Door origin |
| `container_registry_enabled` | No | Create a private Container Registry. Default `true` |
| `key_vault_enabled` | No | Create a private Key Vault. Default `true` |
| `application_gateway_subnet_cidr` | Application Gateway only | Dedicated gateway subnet inside the ARO VNet |
| `application_gateway_backend_host_name` | Application Gateway only | Existing OpenShift application hostname used by the HTTPS health probe |

The module persists the exact resolved ARO version into the local JSON before creating bootstrap input.

The rendered workload Terraform also exposes these defaults:

| Terraform variable | Default |
| --- | --- |
| `pod_cidr` | `10.128.0.0/14` |
| `service_cidr` | `172.30.0.0/16` |
| `control_plane_vm_size` | `Standard_D8s_v3` |
| `worker_vm_size` | `Standard_D4s_v3` |
| `worker_disk_size_gb` | `128` |
| `worker_node_count` | `3` (minimum enforced: 3) |
| `managed_resource_group_name` | `rg-<cluster_name>-managed`; pinned so policy exemptions can be scoped before deployment |
| `fips_enabled` | `false`; FIPS validated cryptographic modules. Forces a new cluster |
| `encryption_at_host_enabled` | `false`; requires the `EncryptionAtHost` feature registered on the subscription and a supporting VM size |
| `disk_encryption_set_id` | `null`; customer-managed key encryption for cluster disks |
| `hub_gateway_transit_enabled` | `false`; `spoke` only. Reaches on-premises through the hub ExpressRoute or VPN gateway. Peering fails if the hub has no gateway |
| `egress_bgp_route_propagation_enabled` | `false`; keeps learned routes from bypassing the firewall default route |
| `application_gateway_backend_root_certificate` | `null`; base64 root certificate of the OpenShift ingress certificate |

Cluster subnets are validated as `/27` or larger and `pod_cidr` as `/18` or larger, matching the documented ARO minimums.

!!! warning "Application Gateway and the OpenShift ingress certificate"
    OpenShift presents self-signed certificates on `*.apps` routes by default. Application Gateway v2 marks an HTTPS backend unhealthy unless the backend certificate chains to a well-known CA or its root is supplied through `application_gateway_backend_root_certificate`. Either replace the ingress certificate with one from a trusted CA or supply the root.

!!! note "Cluster logging"
    Azure Red Hat OpenShift exposes no resource-level diagnostic log categories, so no Azure Monitor diagnostic setting is created for the cluster. Forward cluster logs with the in-cluster Cluster Logging Forwarder instead. Application Gateway does receive a diagnostic setting when `ingress_mode` is `application_gateway`.

These defaults are declared by the generated Terraform template rather than collected by the current PowerShell JSON wizard.

## Mode-specific inputs

| Field | `standalone` | `spoke` |
| --- | --- | --- |
| `connectivity_subscription_id` | Empty | Required existing hub subscription ID |
| `hub_vnet_id` | Empty | Required full existing hub VNet resource ID |
| `next_hop_ip` | Empty | Required existing firewall/NVA private IP |

For `spoke`, the subscription segment in `hub_vnet_id` must equal `connectivity_subscription_id`, and `next_hop_ip` must parse as an IP address. Validation does not prove reachability or routing correctness.

In `spoke` mode the cluster is created with `outbound_type = UserDefinedRouting`, which stops ARO provisioning a public outbound IP and requires the private API server and private ingress the accelerator already configures. `standalone` keeps `Loadbalancer` egress because no route table is attached.

## Ingress

`ingress_mode` is required by module configuration and accepts exactly:

| Value | Implementation |
| --- | --- |
| `none` | Default; no follow-on edge contract selected |
| `front_door` | Follow-on integration contract; no Front Door deployment |
| `application_gateway` | Provisions public WAF_v2 with a private ARO ingress backend and diagnostics |

## Runtime values: never put these in JSON

Configure the generated GitHub `plan` and `apply` environments with optional `REDHAT_PULL_SECRET`. When Application Gateway is enabled, configure base64 PFX data as `APPLICATION_GATEWAY_SSL_CERTIFICATE_DATA` and its password as `APPLICATION_GATEWAY_SSL_CERTIFICATE_PASSWORD`. Both values are required because the public listener is HTTPS-only; Terraform rejects an Application Gateway plan when either value is absent.

Pipeline and ARO authentication use user-assigned managed identities. The bootstrap discovers the Microsoft-managed ARO resource-provider object ID and writes it to generated Terraform configuration; no operator-managed identity credential belongs in JSON.

The GitHub runner is an external prerequisite. Provision and register it before bootstrap, and make sure it can reach the Terraform state endpoint.

## Command parameters

`Deploy-AROLandingZone` exposes:

| Parameter | Behavior |
| --- | --- |
| `InputConfigPath` | Reads configuration noninteractively from an existing JSON file |
| `OutputConfigPath` | Wizard output path; defaults to `config/local.json` |
| `BootstrapAction` | `plan` (default) or `apply` |
| `GenerateConfig` | Stops after wizard write and configuration validation |
| `AutoApprove` | Skips PowerShell apply confirmation; use only with an external reviewed control |

## Workload outputs

The generated Terraform exports cluster ID/name, ARO VNet ID, both ARO subnet IDs, console URL, ingress status, and conditional Application Gateway public IP and FQDN.

## Supporting services

The landing zone creates a Container Registry and a Key Vault that are reachable only through private endpoints in `private_endpoint_subnet_cidr`. Both have `publicNetworkAccess` disabled, a `Deny` default network rule, and a private DNS zone linked to the ARO VNet. The registry uses the Premium SKU because private endpoints require it, and admin credentials are disabled in favour of Microsoft Entra authentication. Set `container_registry_enabled` or `key_vault_enabled` to `false` to opt out.

A Log Analytics workspace is created for the landing zone unless `log_analytics_workspace_id` names an existing one. Ingress diagnostics are sent to it.

!!! note "Azure Verified Modules"
    AVM is the preferred source for these resources, but every candidate AVM module currently constrains `azurerm` to 4.x while this accelerator targets 5.x. They are therefore declared natively, in modules that mirror the AVM boundaries, and can be swapped when AVM supports the 5.x provider.

## Front Door ingress

`ingress_mode = "front_door"` publishes the private cluster without giving it a public address. Terraform creates a Private Link Service over the cluster internal load balancer, with its NAT addresses in `front_door_subnet_cidr`, and a Premium Front Door profile whose origin reaches the cluster through that service. Premium is required because Private Link origins do not exist in the standard tier.

The frontend of the internal load balancer is selected by matching the cluster ingress address rather than by position, because frontend ordering is not a documented contract.

A managed WAF policy runs in `front_door_waf_mode` (`Prevention` by default) with the Microsoft default rule set and bot manager rule set, associated with the endpoint through a security policy. A route publishes `/*` over HTTPS with HTTP redirect.

!!! note "Destroying a Front Door landing zone"
    Azure refuses to delete a Private Link Service that still has a private endpoint connection, and the connection outlives the Front Door origin by a short period. The module inserts a drain so `destroy` waits between removing the origin and removing the service. If a destroy still reports `PrivateLinkServiceWithPrivateEndpointConnectionsCannotBeDeleted`, remove the connection and rerun:

    ```bash
    CONN=$(az network private-link-service show -g <WORKLOAD_RG> -n pls-<CLUSTER> \
      --query "privateEndpointConnections[0].name" -o tsv)
    az network private-endpoint-connection delete -g <WORKLOAD_RG> -n "$CONN" \
      --resource-name pls-<CLUSTER> --type Microsoft.Network/privateLinkServices --yes
    ```
!!! warning "Approve the private link connection after the first apply"
    Front Door raises the private endpoint connection to the Private Link Service in `Pending`. Terraform cannot approve it, because the approval is made on the service side after Front Door requests it. Approve it once per cluster, then the origin becomes reachable:

    ```bash
    CONN=$(az network private-link-service show -g <WORKLOAD_RG> -n pls-<CLUSTER> \
      --query "privateEndpointConnections[0].name" -o tsv)
    az network private-endpoint-connection approve -g <WORKLOAD_RG> -n "$CONN" \
      --resource-name pls-<CLUSTER> --type Microsoft.Network/privateLinkServices \
      --description "Approved for Front Door origin"
    ```
!!! warning "The origin certificate is a prerequisite, not an option"
    Azure rejects a Private Link origin unless certificate name checking is enabled, so Front Door mode requires the OpenShift ingress to already present a **publicly trusted** certificate matching `front_door_backend_host_name`. OpenShift serves `*.apps` with a self-signed certificate by default, so replace the ingress certificate before selecting this mode. The origin reports as unhealthy until you do.




