# Quickstart

## Prerequisites

- PowerShell 7.2 or later
- Terraform 1.9 or later
- Azure CLI with the `aro` command
- Azure permissions to create storage, role assignments, managed identities, and workload resources
- GitHub token in `GITHUB_TOKEN` or `GH_TOKEN` with repository/environment administration permissions

## Plan-first workflow

1. Copy a sample JSON file to an ignored local configuration and replace placeholders. Leave `aro_version` empty to select the newest version currently returned for the region, or provide an exact available version.
2. Authenticate with Azure CLI and export the GitHub token in the process environment.
3. Import the module and invoke `Deploy-AROLandingZone -InputConfigPath <path>`. The default action is `plan`.
4. Review the bootstrap plan. Explicitly invoke again with `-BootstrapAction apply`; confirmation is required unless `-AutoApprove` is intentionally supplied.
5. In the generated private repository, populate the optional protected `plan` and `apply` environment secrets named in the workload README.
6. Open a pull request for CI. The first workload deployment is manual through the protected CD workflow and requires a full commit SHA.

For interactive generation, omit `InputConfigPath`. Use `-GenerateConfig` to stop after writing and validating the wizard inputs without preflight/version resolution.

No command in this guide deploys a hub, firewall, or NVA.
