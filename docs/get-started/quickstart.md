# Quickstart

Deploy an ARO landing zone with a reviewed bootstrap plan, then start the workload deployment from GitHub. Complete the [prerequisites](prerequisites.md) first.

## 1. Clone and configure

Run from PowerShell 7:

```powershell
git clone https://github.com/abengtss-max/aroapplz.git
Set-Location ./aroapplz

# Choose exactly one mode.
Copy-Item ./config/standalone.json ./config/local.json
# Copy-Item ./config/spoke.json ./config/local.json

notepad ./config/local.json
```

Replace every placeholder in `config/local.json`. Keep secrets out of this file. For a first deployment, use `standalone` and leave `aro_version` empty so the module selects an available version.

Set `runner_label` to the GitHub runner your organization already operates.

!!! tip "No runner yet? Let bootstrap create one"
    Set these five values instead, and bootstrap creates ephemeral GitHub runners on Azure Container Instances as part of step 3. Everything after that is identical.

    ```json
    "runner_label": "self-hosted",
    "self_hosted_runner_enabled": true,
    "runner_virtual_network_cidr": "10.60.0.0/24",
    "runner_container_instances_subnet_cidr": "10.60.0.0/26",
    "runner_private_endpoint_subnet_cidr": "10.60.0.64/26"
    ```

    The three ranges must not overlap `aro_vnet_cidr` or your hub. Building the runner image adds a few minutes to step 3. See [self-hosted runners](../operations/self-hosted-runner.md).

!!! warning "After clean-slate recreation"
    Deleting and recreating bootstrap invalidates any repository-scoped runner registration and disconnects a private endpoint that targeted the deleted state storage account, even though the storage account name is deterministic. Restore that connectivity and confirm the runner is online before deploying ARO.

## 2. Sign in

Sign in to Azure first:

```powershell
az login
az account set --subscription <bootstrap-subscription-id>
az provider register `
  --namespace Microsoft.RedHatOpenShift `
  --subscription <workload-subscription-id> `
  --wait
```

!!! warning "Continuous Access Evaluation can block the directory lookup"
    Bootstrap reads the Azure Red Hat OpenShift resource provider service principal from Microsoft Graph. In tenants with Continuous Access Evaluation, the token that plain `az login` caches for Graph can be rejected part way through a run, which surfaces as an authorization or expired token failure on `azuread_service_principal`. Request a Graph-scoped token up front so the cached token is fresh:

    ```powershell
    az login --tenant <tenant-id> --scope https://graph.microsoft.com/.default
    ```

    Run this in the same shell you use for `Deploy-AROLandingZone`. If a run fails on the directory lookup, repeat the command and retry; no Azure resources need to be cleaned up first.

Create a dedicated fine-grained PAT rather than reusing an existing GitHub CLI credential:

1. Open [GitHub fine-grained tokens](https://github.com/settings/personal-access-tokens/new).
2. Set **Token name** to `aroapplz-bootstrap` and choose a short expiration.
3. Set **Resource owner** to the user or organization in `github_organization`.
4. Set **Repository access** to **All repositories**. Bootstrap creates a new repository, so it cannot be selected before deployment.
5. Under **Repository permissions**, select:
  - **Administration: Read and write**
  - **Actions: Read and write**
  - **Contents: Read and write**
  - **Environments: Read and write**
  - **Variables: Read and write**
  - **Workflows: Read and write**
6. Generate and copy the token. If organization approval is required, wait until the token is approved.

Load it only into the current PowerShell process. The masked prompt does not display or save it:

```powershell
Remove-Item Env:GITHUB_TOKEN,Env:GH_TOKEN -ErrorAction SilentlyContinue
$env:GITHUB_TOKEN = Read-Host 'Fine-grained GitHub PAT' -MaskInput

Import-Module ./ALZ.ARO/ALZ.ARO.psd1 -Force
```

The token is limited to one resource owner and the permissions above. The module does not reuse GitHub CLI authentication. **Administration: Read and write** also permits bootstrap teardown to delete the generated repository, and lets bootstrap-created runners register themselves. See [prerequisites](prerequisites.md) for owner-policy requirements.

## 3. Plan and apply bootstrap

Create and inspect the plan. Pass `-InputConfigPath` so the file edited in step 1 is used; without it the command starts an interactive wizard and ignores that file:

```powershell
Deploy-AROLandingZone -InputConfigPath ./config/local.json -BootstrapAction plan
terraform -chdir=bootstrap/alz/github show bootstrap.tfplan
```

Apply only after confirming the GitHub owner, repository, subscriptions, and bootstrap resources:

```powershell
Deploy-AROLandingZone -InputConfigPath ./config/local.json -BootstrapAction apply
```

Enter `Y` at the PowerShell confirmation prompt. This creates the Azure state platform, managed identities, OIDC configuration, and generated GitHub repository. It does **not** deploy ARO automatically.

## 4. Clear the policy carve-out

The plan in step 3 checks the workload subscription for policy that blocks ARO. If it printed a warning, it also printed the exact `az group create` and `az policy exemption create` commands with your subscription, region, resource group, and policy assignment already filled in.

Have a platform or governance owner run those printed commands now. They must complete **before** the workload apply in step 5, otherwise ARO fails partway through with a generic `InternalServerError`.

If nothing was printed, skip to step 5. Background and the manual discovery steps are in [Deploying into an Azure Landing Zone](../governance/azure-landing-zone.md).

!!! warning "`spoke` mode only: grant the pipeline identities access to the hub"
    Spoke mode writes a peering on **both** sides, so the hub side is created by the workload pipeline in a subscription the accelerator does not own. Bootstrap cannot grant this for you. A connectivity owner must run the following after step 3, using the identities that bootstrap created, otherwise the apply in step 5 fails with `AuthorizationFailed` on `virtualNetworkPeerings/write`:

    ```powershell
    $hub = '<hub-vnet-resource-id>'
    az role assignment create --assignee-object-id <id-<service>-<env>-apply principal id> `
      --assignee-principal-type ServicePrincipal --role 'Network Contributor' --scope $hub
    az role assignment create --assignee-object-id <id-<service>-<env>-plan principal id> `
      --assignee-principal-type ServicePrincipal --role Reader --scope $hub
    ```

    See [networking](../concepts/networking.md) for why the grant is scoped to the hub virtual network rather than the resource group.

## 5. Deploy ARO

Choose GitHub UI unless command-line dispatch is required.

=== "GitHub UI"

    1. Open the generated workload repository.
    2. Select **Actions**.
    3. Select **02 ARO Landing Zone Continuous Delivery**.
    4. Select **Run workflow**.
    5. Keep the default branch, choose `apply`, and select **Run workflow**.
    6. Open the run, review the plan, and approve the `apply` environment if prompted.

=== "GitHub CLI"

    Use the dedicated fine-grained PAT for this process instead of a potentially broader GitHub CLI credential:

    ```powershell
    $config = Get-Content ./config/local.json -Raw | ConvertFrom-Json
    $repo = "$($config.github_organization)/$($config.github_repository)"
    $env:GH_TOKEN = $env:GITHUB_TOKEN

    gh workflow run "02 ARO Landing Zone Continuous Delivery" `
      --repo $repo `
      --ref main `
      -f action=apply

    $runId = gh run list `
      --repo $repo `
      --workflow "02 ARO Landing Zone Continuous Delivery" `
      --limit 1 `
      --json databaseId `
      --jq '.[0].databaseId'
    gh run watch $runId --repo $repo
    ```

When `REDHAT_PULL_SECRET` is required, add it to both generated GitHub environments before dispatch. Application Gateway HTTPS also requires the certificate data and password described in the [configuration reference](../reference/configuration.md).

## 6. Publish a Front Door custom domain

Skip this when `ingress_mode` is not `front_door`, or when serving the `azurefd.net` endpoint is enough.

Front Door issues and rotates the certificate itself, so no certificate purchase, Key Vault, or PFX is
involved. Set `front_door_custom_domain` in `config/local.json`, re-run the bootstrap so the workload
repository picks the value up, and dispatch `apply` again. Terraform then prints the two records to
publish:

```powershell
terraform output -json front_door_custom_domain_validation
```

Create both records with your DNS provider, using the subdomain only if the provider appends the zone:

| Type | Name | Value | Purpose |
| --- | --- | --- | --- |
| `TXT` | `_dnsauth.<subdomain>` | `txt_record_value` from the output | Proves domain ownership so Front Door issues the managed certificate |
| `CNAME` | `<subdomain>` | `cname_target` from the output, ending in `azurefd.net` | Sends client traffic to Front Door |

Both records are required. With only the TXT record the certificate is issued but nothing resolves;
with only the CNAME the domain never validates and HTTPS fails.

Validation usually completes within minutes. Confirm with:

```powershell
az afd custom-domain list -g <aro-resource-group> --profile-name <front-door-profile> `
  --query "[].{domain:hostName,state:domainValidationState}" -o table
```

Traffic flows once the state reaches `Approved`. Front Door is a global service, so allow up to
30 minutes after the first apply before treating an error page as a failure.

## Standards alignment

This accelerator follows [Secure access to Azure Red Hat OpenShift with Azure Front
Door](https://learn.microsoft.com/azure/openshift/howto-secure-openshift-with-front-door): a private
cluster with private ingress visibility, a dedicated Private Link subnet that is neither delegated
nor given service endpoints, a Private Link Service attached to the cluster `-internal` load balancer
on the ingress frontend address, Front Door Premium, a Private Link origin, and certificate subject
name checking left enabled. The ARO-managed resource group is never modified, in line with Red Hat
guidance; the cluster load balancer is only read.

Where the implementation differs from the documented click-through, and why:

| Difference | Reason |
| --- | --- |
| Terraform approves the private endpoint connection and deletes connections before destroy | `azurerm` exposes no resource for either. Microsoft documents approving through the Azure CLI, which is what runs. Without the destroy step the Private Link Service cannot be deleted and teardown fails |
| The origin defaults to the cluster `apps` domain rather than a customer domain | The default ARO ingress certificate is publicly trusted and matches that name, so the walkthrough works before you own a domain. Set `front_door_custom_domain` for the documented pattern |
| The Private Link Service is visible only to the workload subscription | The walkthrough uses *Anyone with your alias*. Restricting visibility is tighter, and Front Door still connects |
| The runner registry allows public network access with the `AzureServices` bypass | ACR Tasks build the runner image on Microsoft-managed public agents, which cannot reach a private-only registry. Runners pull through a private endpoint. Set `self_hosted_runner_enabled` to `false` to avoid it entirely. A [dedicated agent pool](https://learn.microsoft.com/azure/container-registry/tasks-agent-pools) can run the build inside a virtual network and remove the public endpoint, but it is still in preview, is billed on allocation rather than use, and needs its own subnet and outbound rules |

Two platform limits apply to any Front Door Private Link design:

- Each Front Door regional cluster is limited to **7200 requests per second per profile**; beyond that
  Azure returns `429`. Spread traffic across origins in different Private Link regions to scale past it.
- An origin group cannot mix public and private origins.

## Destroy everything safely

Destroy in this order: **workload first, bootstrap second**. Keep this clone, `config/local.json`, and local Terraform state until all verification succeeds. Your runner is outside accelerator ownership and is not removed.

### 1. Destroy the ARO workload

Skip this step only if the workload workflow never successfully applied resources.

=== "GitHub UI"

    1. Open the generated workload repository.
    2. Select **Actions** > **02 ARO Landing Zone Continuous Delivery**.
    3. Select **Run workflow** from the default branch.
    4. Choose `destroy` and select **Run workflow**.
    5. Review the destroy plan, approve the `apply` environment if prompted, and wait for success.

=== "GitHub CLI"

    ```powershell
    $config = Get-Content ./config/local.json -Raw | ConvertFrom-Json
    $repo = "$($config.github_organization)/$($config.github_repository)"
    $env:GH_TOKEN = $env:GITHUB_TOKEN

    gh workflow run "02 ARO Landing Zone Continuous Delivery" `
      --repo $repo `
      --ref main `
      -f action=destroy

    $runId = gh run list `
      --repo $repo `
      --workflow "02 ARO Landing Zone Continuous Delivery" `
      --limit 1 `
      --json databaseId `
      --jq '.[0].databaseId'
    gh run watch $runId --repo $repo
    ```

Review the destroy plan, approve the `apply` environment if prompted, and wait for a successful run before continuing.

### 2. Create and review the bootstrap destroy plan

Reuse the dedicated fine-grained PAT created in step 2. Its **Administration: Read and write** permission allows deletion of the generated repository. Reload it if it is no longer present in this PowerShell process:

```powershell
Remove-Item Env:GITHUB_TOKEN,Env:GH_TOKEN -ErrorAction SilentlyContinue
$env:GITHUB_TOKEN = Read-Host 'Fine-grained GitHub PAT' -MaskInput
Import-Module ./ALZ.ARO/ALZ.ARO.psd1 -Force

Deploy-AROLandingZone -BootstrapAction destroy -WhatIf
terraform -chdir=bootstrap/alz/github show bootstrap-destroy.tfplan
```

Confirm that the plan deletes only the generated repository and bootstrap resources. It must not contain an independently managed runner VM or runner resource group.

### 3. Apply the exact reviewed bootstrap plan

Apply the saved plan directly so Terraform cannot generate a different plan between review and execution:

```powershell
terraform -chdir=bootstrap/alz/github apply bootstrap-destroy.tfplan
```

Enter `yes` only after checking the plan path and target names. Then verify deletion:

```powershell
gh repo view $repo
az group exists `
  --name "rg-$($config.service_name)-$($config.environment_name)-bootstrap" `
  --subscription $config.bootstrap_subscription_id
```

The repository lookup should fail and `az group exists` should return `false`. Only then remove local credentials and artifacts:

```powershell
Remove-Item Env:GITHUB_TOKEN,Env:GH_TOKEN -ErrorAction SilentlyContinue
Remove-Item ./config/local.json -ErrorAction SilentlyContinue
Remove-Item ./bootstrap/alz/github/bootstrap*.tfplan -ErrorAction SilentlyContinue
Remove-Item ./bootstrap/alz/github/terraform.tfvars.json -ErrorAction SilentlyContinue
Remove-Item ./bootstrap/alz/github/terraform.tfstate* -ErrorAction SilentlyContinue
Remove-Item ./bootstrap/alz/github/.terraform -Recurse -Force -ErrorAction SilentlyContinue
```

For recovery steps and state-backup guidance, see [remove workload and bootstrap](../operations/cleanup.md).
