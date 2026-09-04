# Quickstart

This workflow is intentionally plan first. Bootstrap and workload are separate Terraform stages, and the workload is never applied automatically by the module.

## 1. Clone the repository

Choose one method, then enter the cloned project directory before running any other command on this page.

=== "HTTPS"

  ```powershell
  git clone https://github.com/abengtss-max/aroapplz.git
  Set-Location ./aroapplz
  ```

=== "GitHub CLI"

  ```powershell
  gh repo clone abengtss-max/aroapplz
  Set-Location ./aroapplz
  ```

Confirm that the expected module and sample configurations are present:

```powershell
Test-Path ./ALZ.ARO/ALZ.ARO.psd1
Get-ChildItem ./config/*.json
```

`Test-Path` should return `True`, and the configuration command should list the `standalone.json` and `spoke.json` samples.

!!! tip "Already cloned?"
  Run `Set-Location <path-to-your-clone>` and continue with step 2. All paths below are relative to the repository root.

## 2. Prepare local configuration

Copy the sample matching the selected mode to the ignored local path:

=== "standalone"

    ```powershell
    Copy-Item ./config/standalone.json ./config/local.json
    ```

=== "spoke"

    ```powershell
    Copy-Item ./config/spoke.json ./config/local.json
    ```

Replace every placeholder and review the [configuration reference](../reference/configuration.md). Do not put secrets in this JSON file. Leave `aro_version` empty for regional discovery or provide an exact version for validation.

## 3. Authenticate

Authenticate Azure CLI and select or verify access to the required subscriptions:

```powershell
az login
az account set --subscription <bootstrap-subscription-id>
```

The bootstrap **does create and configure the GitHub workload repository**. It uses the Terraform GitHub provider to create the private repository, `plan` and `apply` environments, environment variables, generated files, and workflows. A GitHub personal access token (PAT) is therefore required only while planning and applying bootstrap; generated workload workflows use Azure OIDC and do not use this PAT.

Create a classic PAT for the target GitHub owner with these scopes:

| Classic PAT scope | When required | Why bootstrap needs it |
| --- | --- | --- |
| `repo` | Always | Creates and administers the private repository, environments, Actions variables, and generated files |
| `workflow` | Always | Writes the generated workflow files below `.github/workflows` |
| `read:org` | Organization target | Reads organization context and membership while managing an organization-owned repository |

No `admin:org`, `delete_repo`, `packages`, or Azure permission is required by the documented bootstrap. The token owner must independently have permission to create private repositories for the configured user or organization and administer the created repository. A PAT cannot grant privileges that its owner does not have.

If the target is an organization, authorize the token for SAML SSO when required and ensure organization policy permits PAT access and repository creation.

Set the token for the current PowerShell process without displaying it:

```powershell
$env:GITHUB_TOKEN = Read-Host 'GitHub PAT' -MaskInput
```

Alternatively, when GitHub CLI is already authenticated with equivalent access:

```powershell
$env:GITHUB_TOKEN = gh auth token
```

`GH_TOKEN` is also accepted; the module maps it to `GITHUB_TOKEN` in memory for the Terraform provider.

!!! warning "Keep credentials out of shell history"
  Use your organization's approved secret-handling method to populate the environment variable. Do not place the PAT directly in a command, commit it, add it to JSON or Terraform variables, or configure it as a generated repository secret. Remove it from the process after bootstrap with `Remove-Item Env:GITHUB_TOKEN` (and `Remove-Item Env:GH_TOKEN` if used).

!!! note "Fine-grained PATs"
  A fine-grained PAT can be used only when the organization permits it and the token can access repositories created after the token was issued. Select the target organization as **Resource owner**, select **All repositories**, and grant repository permissions **Administration: Read and write**, **Contents: Read and write**, **Environments: Read and write**, **Actions: Read and write**, **Variables: Read and write**, and **Workflows: Read and write**. Because the target repository does not exist when the token is created, repository selection and organization policy can still prevent bootstrap. The tested and documented default is therefore a classic PAT with `repo`, `workflow`, and—when targeting an organization—`read:org`.

## 4. Import the module

Import the repository module directly:

```powershell
Import-Module ./ALZ.ARO/ALZ.ARO.psd1 -Force
```

Alternatively, run `./install.ps1` to copy it into the current user's PowerShell module directory, then use `Import-Module ALZ.ARO`.

Importing the module performs no cloud operation.

## 5. Generate the bootstrap plan

```powershell
Deploy-AROLandingZone -InputConfigPath ./config/local.json
```

The default `BootstrapAction` is `plan`. The command:

1. validates configuration and tool access;
2. verifies Azure subscription access and, for `spoke`, reads the existing hub;
3. discovers or validates an exact ARO version and writes it into the local JSON;
4. renders the generated workload files into bootstrap input;
5. initializes and validates bootstrap Terraform; and
6. writes `bootstrap/alz/github/bootstrap.tfplan` without applying it.

Review the plan and the generated `bootstrap/alz/github/terraform.tfvars.json`. Both are local artifacts and must remain uncommitted.

## 6. Explicitly apply bootstrap

After review, invoke the module again with apply selected:

```powershell
Deploy-AROLandingZone `
  -InputConfigPath ./config/local.json `
  -BootstrapAction apply
```

PowerShell confirmation is required. `-AutoApprove` bypasses that prompt and should only be used when an external reviewed control provides equivalent intent.

Bootstrap apply creates the state platform, managed plan/apply identities and OIDC credentials, RBAC, and private GitHub workload repository with protected environments and workflows. It prints that **no workload apply was triggered**.

After bootstrap succeeds, clear the operator PAT from the shell:

```powershell
Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
```

## 7. Add optional workload runtime secrets

In both generated `plan` and `apply` GitHub environments, configure `REDHAT_PULL_SECRET` when used. For Application Gateway HTTPS, also configure `APPLICATION_GATEWAY_SSL_CERTIFICATE_DATA` with base64 PFX content and `APPLICATION_GATEWAY_SSL_CERTIFICATE_PASSWORD`.

GitHub and ARO both use user-assigned managed identities. There is no ARO client secret to configure.

## 8. Review and deploy the workload

1. Open a pull request in the generated repository so CI can run formatting, validation, Checkov, and a speculative plan.
2. Merge an approved change according to team policy.
3. Manually dispatch the generated CD workflow with the full immutable commit SHA.
4. Review the plan created from that SHA.
5. Approve the protected `apply` environment so the workflow applies the exact uploaded plan artifact.

There is no automatic workload apply.

## 9. Validate the result

Confirm the expected resource group, VNet, control-plane and worker subnets, private ARO cluster, and Terraform outputs. For `spoke`, also verify both peerings, effective routes, firewall/NVA handling, DNS, and outbound reachability. Follow the [validation guide](../operations/validation.md) and your organization's ARO operational checks.

## Configuration-only wizard

Omit `-InputConfigPath` to use the interactive wizard. To stop after writing and validating wizard inputs—before tool preflight or ARO version resolution—add `-GenerateConfig`:

```powershell
Deploy-AROLandingZone `
  -OutputConfigPath ./config/local.json `
  -GenerateConfig
```
