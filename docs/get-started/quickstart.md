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

Use `"runner_label": "self-hosted"` only when an independently managed repository runner is already available. The accelerator does not create or destroy runner infrastructure.

## 2. Sign in

```powershell
az login
az account set --subscription <bootstrap-subscription-id>

# Use a GitHub CLI token without printing it.
Remove-Item Env:GITHUB_TOKEN,Env:GH_TOKEN -ErrorAction SilentlyContinue
$env:GITHUB_TOKEN = gh auth token

Import-Module ./ALZ.ARO/ALZ.ARO.psd1 -Force
```

The GitHub credential needs classic PAT scopes `repo` and `workflow`; add `read:org` for an organization. Add `delete_repo` now if the same token will be used for teardown. See [prerequisites](prerequisites.md) for access requirements.

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

## 4. Deploy ARO

Read the generated repository name and dispatch its delivery workflow:

```powershell
$config = Get-Content ./config/local.json -Raw | ConvertFrom-Json
$repo = "$($config.github_organization)/$($config.github_repository)"

gh workflow run "02 ARO Landing Zone Continuous Delivery" `
  --repo $repo `
  --ref main `
  -f action=apply
```

Open the run, review its plan, and approve the `apply` environment when GitHub requests approval:

```powershell
gh run list --repo $repo --workflow "02 ARO Landing Zone Continuous Delivery" --limit 1
gh run watch --repo $repo
```

When `REDHAT_PULL_SECRET` is required, add it to both generated GitHub environments before dispatch. Application Gateway HTTPS also requires the certificate data and password described in the [configuration reference](../reference/configuration.md).

## Destroy everything safely

Destroy in this order: **workload first, bootstrap second**. Keep this clone, `config/local.json`, and local Terraform state until all verification succeeds. An independent self-hosted runner is outside accelerator ownership and is not removed.

### 1. Destroy the ARO workload

Skip this step only if the workload workflow never successfully applied resources.

```powershell
$config = Get-Content ./config/local.json -Raw | ConvertFrom-Json
$repo = "$($config.github_organization)/$($config.github_repository)"

gh workflow run "02 ARO Landing Zone Continuous Delivery" `
  --repo $repo `
  --ref main `
  -f action=destroy

gh run list --repo $repo --workflow "02 ARO Landing Zone Continuous Delivery" --limit 1
gh run watch --repo $repo
```

Review the destroy plan, approve the `apply` environment if prompted, and wait for a successful run before continuing.

### 2. Create and review the bootstrap destroy plan

The token used here must include `delete_repo`. These commands replace any stale process token with the current GitHub CLI token:

```powershell
Remove-Item Env:GITHUB_TOKEN,Env:GH_TOKEN -ErrorAction SilentlyContinue
$env:GITHUB_TOKEN = gh auth token
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
