# Configuration reference

The module accepts JSON so PowerShell 7 requires no additional YAML parser. Sample files contain placeholders, not deployable identifiers or secrets:

- [`config/standalone.json`](https://github.com/abengtss-max/aroapplz/blob/main/config/standalone.json)
- [`config/spoke.json`](https://github.com/abengtss-max/aroapplz/blob/main/config/spoke.json)

Copy one to the ignored `config/local.json` before editing.

## Shared bootstrap inputs

| Field | Required | Meaning |
| --- | --- | --- |
| `deployment_mode` | Yes | Exactly `standalone` or `spoke` |
| `tenant_id` | Yes | Microsoft Entra tenant for created applications |
| `bootstrap_subscription_id` | Yes | Subscription for bootstrap Azure resources |
| `workload_subscription_id` | Yes | Subscription for the new ARO workload |
| `location` | Yes | Azure region used for resources and ARO version discovery |
| `service_name` | Yes | Short service component used in generated names |
| `environment_name` | Yes | Environment component used in generated names |
| `github_organization` | Yes | GitHub organization or owner for the generated repository |
| `github_repository` | Yes | Name of the new private workload repository |
| `apply_approvers` | Yes | Non-empty array of GitHub usernames for environment protection |

Generated workload names include `rg-<service>-<environment>-aro` and `aro-<service>-<environment>`.

## ARO and network inputs

| Field | Required | Meaning |
| --- | --- | --- |
| `aro_version` | Resolved before plan | Empty for newest returned regional version, or an exact version to validate |
| `aro_domain` | Yes | Unique ARO domain prefix |
| `aro_vnet_cidr` | Yes | CIDR for the new ARO VNet |
| `control_plane_subnet_cidr` | Yes | CIDR for the new control-plane subnet |
| `worker_subnet_cidr` | Yes | CIDR for the new worker subnet |

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

These defaults are declared by the generated Terraform template rather than collected by the current PowerShell JSON wizard.

## Mode-specific inputs

| Field | `standalone` | `spoke` |
| --- | --- | --- |
| `connectivity_subscription_id` | Empty | Required existing hub subscription ID |
| `hub_vnet_id` | Empty | Required full existing hub VNet resource ID |
| `next_hop_ip` | Empty | Required existing firewall/NVA private IP |

For `spoke`, the subscription segment in `hub_vnet_id` must equal `connectivity_subscription_id`, and `next_hop_ip` must parse as an IP address. Validation does not prove reachability or routing correctness.

## Ingress

`ingress_mode` is required by module configuration and accepts exactly:

| Value | Implementation |
| --- | --- |
| `none` | Default; no follow-on edge contract selected |
| `front_door` | Follow-on integration contract; no Front Door deployment |
| `application_gateway` | Preview contract; no Application Gateway deployment |

## Runtime values: never put these in JSON

Configure the generated GitHub `plan` and `apply` environments with:

- `ARO_SERVICE_PRINCIPAL_CLIENT_ID`
- `ARO_SERVICE_PRINCIPAL_CLIENT_SECRET`
- `ARO_SERVICE_PRINCIPAL_OBJECT_ID`
- `ARO_RESOURCE_PROVIDER_OBJECT_ID`
- optionally `REDHAT_PULL_SECRET`

The ARO client secret and pull secret are sensitive runtime inputs. Keeping all values in protected environments also provides a consistent generated workflow contract. Azure pipeline authentication uses the separate OIDC client IDs created by bootstrap.

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

The generated Terraform exports cluster ID/name, ARO VNet ID, both subnet IDs, console URL, and a human-readable ingress status. It does not output the ARO service-principal secret.
