# Deploying into an Azure Landing Zone

aroapplz deploys an *application* landing zone. It never assigns management groups or platform-scope policy. When the workload subscription sits inside an Azure Landing Zones (ALZ) hierarchy, several default policy assignments interact with Azure Red Hat OpenShift. Some the accelerator now satisfies natively; the rest need a platform-side carve-out **before** the first apply.

## What the accelerator satisfies natively

| Default ALZ assignment | Scope | Effect | How aroapplz satisfies it |
| --- | --- | --- | --- |
| `Deny-Subnet-Without-Nsg` | Landing Zones | Deny | The generated Terraform creates one NSG per cluster subnet, attaches them to the control-plane and worker subnets, and sets `preconfigured_network_security_group_enabled = true`. |
| `Deny-Storage-http` | Landing Zones | Deny | ARO creates its managed storage accounts with HTTPS-only enabled. |
| `Deny-MgmtPortsFromInternet` | Landing Zones | Deny | The cluster is private; no management ports are exposed. |

!!! note "Bring-your-own NSG is permanent"
    ARO cannot enable the preconfigured NSG feature on an existing cluster, and preconfigured NSGs are **not** updated automatically when you create `LoadBalancer` services or OpenShift routes. Add those rules yourself. Never add DENY rules between the control-plane and worker subnets in either direction — it breaks the cluster and blocks SRE support.

ARO permits either one shared NSG or one per subnet. The accelerator uses one per subnet so that ingress rules can be scoped to the worker subnet without also opening the control plane. Each NSG carries the four operator identity role assignments plus the ARO resource provider.

## What needs a platform carve-out

### Deny-PublicPaaSEndpoints (the blocker)

Assigned at **Landing Zones/Corp** with effect `Deny`. It includes storage `publicNetworkAccess`. ARO creates its managed storage accounts with the public endpoint reachable and restricted by service-endpoint rules to the resource provider's own subnets, so the assignment denies cluster creation outright.

The equivalent Microsoft-internal policy is `StorageAccount_PublicNetwork_Modify`, which uses `Modify` rather than `Deny` and therefore fails later and far more obscurely — the cluster reaches base-resource creation and then returns a generic `InternalServerError`.

=== "ALZ Terraform"

    ```terraform
    module "alz" {
      # ...
      policy_assignments_to_modify = {
        corp = {
          Deny-PublicPaaSEndpoints = {
            parameters = {
              effect = jsonencode({ value = "Audit" })
            }
          }
        }
      }
    }
    ```

=== "ALZ Bicep"

    ```bicep-params
    param landingzonesCorpConfig = {
      managementGroupDoNotEnforcePolicyAssignments: [
        'Deny-PublicPaaSEndpoints'
      ]
    }
    ```

=== "Archetype override"

    ```yaml
    base_archetype: corp
    name: corp_aro
    policy_assignments_to_remove: [
      Deny-PublicPaaSEndpoints,
    ]
    ```

### Enable-DDoS-VNET

Assigned at **Landing Zones** with effect `Modify`. It injects a DDoS plan reference into every virtual network. If no DDoS protection plan exists, virtual network creation fails with `LinkedAuthorizationFailed`, so the accelerator's ARO VNet never gets created. Exclude the assignment or supply a real plan ID.

### Enforce-Subnet-Private

Assigned at **Landing Zones**. ARO cluster subnets require `defaultOutboundAccess = true`. The assignment is harmless while its effect is `Audit` and becomes a hard blocker if your organisation set it to `Deny`. Confirm the effect in your environment.

### VM-targeting DeployIfNotExists assignments

`Deploy-VM-Backup`, the Azure Monitor Agent initiatives, ChangeTracking, and Trusted Launch guest attestation all target virtual machines. ARO nodes are RHCOS instances inside a deny-assignment-protected managed resource group. These assignments cannot remediate, generate perpetual failures, and conflict with the ARO support policy statement:

> Don't place policies within your subscription or management group that prevent SREs from performing normal maintenance against the Azure Red Hat OpenShift cluster.

Set them to `DoNotEnforce` for ARO subscriptions.

!!! warning "Assignment names drift"
    Verify each assignment name against the [ALZ library](https://github.com/Azure/Azure-Landing-Zones-Library/tree/main/platform/alz/policy_assignments) for your ALZ version before applying these snippets.

## Scope the exemption to the managed resource group

The storage accounts that get denied are **not** in the resource group the accelerator targets. They live in the resource group the ARO resource provider creates and owns. An exemption on the workload resource group has no effect.

The accelerator pins that name so a platform team can author the carve-out ahead of time:

```
rg-aro-<service_name>-<environment_name>-managed
```

The name is derived once by the module, written into the generated `terraform/aro.auto.tfvars.json` as `managed_resource_group_name`, and used verbatim in the commands the plan prints, so all three always agree. Set `managed_resource_group_name` in your configuration to override it. The value cannot contain uppercase characters.

!!! warning "Timing"
    A policy exemption requires its scope to already exist, and ARO creates the managed resource group during deployment. Pre-create the group yourself to scope the exemption to it, or use a subscription-scoped exemption instead. ARO deletes the group along with the cluster either way, so a group-scoped exemption must be recreated on every rebuild.

## Create the exemption

`Deploy-AROLandingZone -BootstrapAction plan` prints both commands with your subscription, region, resource group, and policy assignment already substituted. Run what it printed. The rest of this section is the manual fallback.

```bash
az group create -n <MANAGED_RG> -l <REGION> \
  --managed-by "/subscriptions/<SUB>/resourceGroups/<WORKLOAD_RG>/providers/Microsoft.RedHatOpenShift/openShiftClusters/<CLUSTER>"

az policy exemption create -n aro-storage-public-endpoint \
  -g <MANAGED_RG> -a "<ASSIGNMENT_ID>" -e Mitigated -r "<REFERENCE_ID>"
```

Discover the two IDs, which vary by ALZ version:

```bash
az policy assignment list --scope "/subscriptions/<SUB>" --disable-scope-strict-match \
  --query "[].{name:name,id:id,definition:policyDefinitionId}" -o table

az policy set-definition show --id <SET_DEFINITION_ID> \
  --query "policyDefinitions[?contains(policyDefinitionReferenceId,'Storage')].policyDefinitionReferenceId" -o tsv
```

!!! warning "ARO must accept the pre-created group"
    ARO reuses an existing managed resource group only when its location matches the cluster location and `managedBy` equals the cluster resource ID exactly. Otherwise it fails with `ClusterResourceGroupAlreadyExists`. That behaviour is in the resource provider source but is not a documented contract, and the Azure CLI rejects a pre-existing group for `--cluster-resource-group`. Validate it once in a non-production subscription. To avoid the dependency entirely, replace `-g <MANAGED_RG>` with `--scope "/subscriptions/<SUB>"`.

### Why the accelerator does not create the exemption for you

It would be easy to add an `azurerm_resource_group_policy_exemption` to the workload Terraform. We deliberately do not, for three reasons:

1. **Privilege.** Creating an exemption needs `Microsoft.Authorization/policyExemptions/write`, which comes with Resource Policy Contributor or Owner. The apply identity holds Contributor and Role Based Access Control Administrator, and neither grants it. Adding it would let the workload pipeline exempt itself from any policy in the subscription — the opposite of the separation of duties the landing zone exists to enforce.
2. **Timing.** The ARO-managed resource group does not exist until the cluster deployment is already running, so there is nothing to scope a resource-group exemption to beforehand.
3. **Lifecycle.** ARO deletes the managed resource group along with the cluster, so a resource-group-scoped exemption disappears on every rebuild.

Policy exemptions are a platform-team decision with an owner, a justification, and an expiry. The accelerator's job is to tell you exactly which one you need, which the preflight does.

## Recommended placement

For one or two clusters, use a scoped carve-out. Cloud Adoption Framework guidance is explicit that you should "always try to build on the existing archetypes" and "only create new archetypes when they're truly needed".

Once ARO is a strategic platform across several subscriptions, create a dedicated management group **as a sibling of Corp under Landing Zones — not as a child of Corp**. `Deny-PublicPaaSEndpoints` is a Corp-only assignment, so a sibling archetype never inherits the blocker and needs no exemption at all. Keep the hierarchy within four levels and expand horizontally.

Remember that Corp versus Online is a connectivity decision as well as a policy one: an ARO archetype beside Corp must deliberately re-add whichever Corp guardrails you still want.

## Preflight

`Deploy-AROLandingZone` inspects effective policy assignments on the workload subscription and warns when a known-blocking assignment is enforced, naming the assignment, its scope, and the managed resource group to scope the carve-out to. The check is deliberately a warning rather than a failure, because it cannot see exemptions, tag opt-outs, or resource selectors that may already permit the deployment. It is not exhaustive — always run a workload plan in the target policy context.
