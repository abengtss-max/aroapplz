# Remove the workload and bootstrap

Use this sequence to return an accelerator deployment to a clean slate. Workload and bootstrap are separate Terraform states and must be removed in order.

!!! danger "Destructive operation"
    Verify the GitHub owner, repository, Azure subscription, service name, environment name, and selected default branch before continuing. Never delete the local bootstrap state before teardown succeeds.

## 1. Verify the target

Run these commands from the same accelerator clone that created the bootstrap:

```powershell
git status
git rev-parse --short HEAD
Get-Content ./config/local.json
terraform -chdir=bootstrap/alz/github state list
```

Confirm that `config/local.json` identifies the intended GitHub repository and Azure subscriptions. The local bootstrap state must list the generated repository and bootstrap resources. If the state is missing or belongs to another deployment, stop; do not manually delete resources and assume Terraform state is clean.

Optionally preserve an encrypted, access-controlled state backup before teardown:

```powershell
terraform -chdir=bootstrap/alz/github state pull |
  Set-Content ./bootstrap-state-backup.json
```

The backup can contain resource identifiers and sensitive values. Do not commit it. Delete it securely after cleanup is verified.

## 2. Destroy the ARO workload first

Skip this step only when the workload CD workflow has never successfully applied resources.

1. Open the generated workload repository.
2. Select **Actions**.
3. Open **02 ARO Landing Zone Continuous Delivery**.
4. Select **Run workflow** from the default branch.
5. Select `destroy` and run it.
6. Review the destroy plan and, when configured, approve the `apply` environment.
7. Wait for the workflow to complete successfully.

This removes resources in workload state. In `spoke`, it does not delete the existing hub or firewall/NVA. Review platform-owned DNS, routing, and peering records separately.

Do not remove bootstrap identities or state storage before workload destroy completes; the workflow needs them to authenticate and read its state.

## 3. Prepare GitHub deletion permission

Bootstrap teardown deletes the generated private repository. A classic PAT therefore needs:

- `repo`;
- `workflow`;
- `delete_repo`;
- `read:org` when the configured owner is an organization.

Set the teardown PAT only in the current process:

```powershell
$env:GITHUB_TOKEN = Read-Host 'GitHub teardown PAT' -MaskInput
```

The token owner must also be allowed to delete the target repository. Organization policy or SAML authorization can impose additional requirements.

## 4. Generate and review the bootstrap destroy plan

Import the current module and use `-WhatIf` to create the destroy plan without applying it:

```powershell
Import-Module ./ALZ.ARO/ALZ.ARO.psd1 -Force

Deploy-AROLandingZone `
  -InputConfigPath ./config/local.json `
  -BootstrapAction destroy `
  -WhatIf

terraform -chdir=bootstrap/alz/github show bootstrap-destroy.tfplan
```

When `config/local.json` exists in the accelerator clone, the equivalent shorter command is:

```powershell
Deploy-AROLandingZone -BootstrapAction destroy -WhatIf
```

Confirm that the plan targets only the intended:

- generated GitHub workload repository;
- `plan` and `apply` environments and repository configuration;
- pipeline managed identities, federated credentials, and role assignments;
- Terraform state container and storage account;
- bootstrap resource group.

## 5. Apply the exact bootstrap destroy plan

Run the destroy action without `-WhatIf`:

```powershell
Deploy-AROLandingZone `
  -InputConfigPath ./config/local.json `
  -BootstrapAction destroy
```

With the existing default configuration file, this can be shortened to:

```powershell
Deploy-AROLandingZone -BootstrapAction destroy
```

PowerShell displays the GitHub repository and bootstrap resource-group targets. Confirm only after matching them to `config/local.json`. The module generates a fresh destroy plan and applies that exact plan; `-AutoApprove` is intentionally not recommended for interactive cleanup.

Expected completion message:

```text
Bootstrap destroy completed. The generated GitHub repository and Azure bootstrap resources were removed.
```

## 6. Verify and remove local artifacts

Verify that the repository no longer exists and the resource group is absent:

```powershell
gh repo view <owner>/<generated-repository>
az group exists `
  --name <bootstrap-resource-group> `
  --subscription <bootstrap-subscription-id>
```

The repository lookup should fail and `az group exists` should return `false`. Then clear credentials and local artifacts:

```powershell
Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
Remove-Item ./config/local.json -ErrorAction SilentlyContinue
Remove-Item ./bootstrap/alz/github/bootstrap*.tfplan -ErrorAction SilentlyContinue
Remove-Item ./bootstrap/alz/github/terraform.tfvars.json -ErrorAction SilentlyContinue
Remove-Item ./bootstrap/alz/github/terraform.tfstate* -ErrorAction SilentlyContinue
Remove-Item ./bootstrap/alz/github/.terraform -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item ./bootstrap-state-backup.json -ErrorAction SilentlyContinue
```

Only remove local state after both Terraform destroy and verification succeed.

## Recovery when teardown fails

Keep the local state, configuration, PAT, and terminal output. Correct the reported issue and rerun the same destroy action; Terraform resumes from current state. Do not use `terraform state rm`, delete the generated repository manually, or delete the bootstrap resource group unless a reviewed state-recovery procedure explicitly requires it.
