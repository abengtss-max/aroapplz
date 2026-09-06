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

Set `runner_label` to the GitHub runner your organization already operates. The accelerator selects a runner; it never creates, registers, or removes one.

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

The token is limited to one resource owner and the permissions above. The module does not reuse GitHub CLI authentication. **Administration: Read and write** also permits bootstrap teardown to delete the generated repository. See [prerequisites](prerequisites.md) for owner-policy requirements.

## 3. Plan and apply bootstrap

Create and inspect the plan:

```powershell
Deploy-AROLandingZone -BootstrapAction plan
terraform -chdir=bootstrap/alz/github show bootstrap.tfplan
```

Apply only after confirming the GitHub owner, repository, subscriptions, and bootstrap resources:

```powershell
Deploy-AROLandingZone -BootstrapAction apply
```

Enter `Y` at the PowerShell confirmation prompt. This creates the Azure state platform, managed identities, OIDC configuration, and generated GitHub repository. It does **not** deploy ARO automatically.

## 4. Clear the policy carve-out

The plan in step 3 checks the workload subscription for policy that blocks ARO. If it printed a warning, it also printed the exact `az group create` and `az policy exemption create` commands with your subscription, region, resource group, and policy assignment already filled in.

Have a platform or governance owner run those printed commands now. They must complete **before** the workload apply in step 5, otherwise ARO fails partway through with a generic `InternalServerError`.

If nothing was printed, skip to step 5. Background and the manual discovery steps are in [Deploying into an Azure Landing Zone](../governance/azure-landing-zone.md).

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
