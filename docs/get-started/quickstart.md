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

Authenticate Azure CLI and select or verify access to the required subscriptions. Set a GitHub token only in the current process environment as `GITHUB_TOKEN` or `GH_TOKEN`.

!!! warning "Keep credentials out of shell history"
    Use your organization's approved secret-handling method to populate the environment variable. Do not commit the token or write it into configuration.

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

Bootstrap apply creates the state platform, Entra plan/apply identities and OIDC credentials, RBAC, and private GitHub workload repository with protected environments and workflows. It prints that **no workload apply was triggered**.

## 7. Add workload runtime secrets

In both generated `plan` and `apply` GitHub environments, configure:

- `ARO_SERVICE_PRINCIPAL_CLIENT_ID`
- `ARO_SERVICE_PRINCIPAL_CLIENT_SECRET`
- `ARO_SERVICE_PRINCIPAL_OBJECT_ID`
- `ARO_RESOURCE_PROVIDER_OBJECT_ID`
- `REDHAT_PULL_SECRET` when used

The ARO client secret and optional pull secret are runtime secrets. GitHub's Azure login uses OIDC and does not use these values.

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
