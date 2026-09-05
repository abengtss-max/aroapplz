# Azure self-hosted GitHub runner

The optional runner is a bootstrap-managed Ubuntu VM registered only to the generated private workload repository. Use it when Azure Policy disables public access to the Terraform state account or when workloads require execution from Azure.

## Enable the runner

Add these fields to ignored `config/local.json`:

```json
{
  "use_self_hosted_runner": true,
  "runner_vm_size": "Standard_D2s_v5",
  "runner_ssh_public_key_path": "~/.ssh/id_ed25519.pub"
}
```

Bootstrap creates:

- an Ubuntu 24.04 VM with no inbound NSG rules;
- a dedicated runner VNet and subnets;
- a static public IP for outbound connectivity only;
- a private endpoint and private DNS link for the state account blob endpoint;
- system-assigned VM identity and managed boot diagnostics;
- GitHub Actions runner, Azure CLI, Terraform, Docker, Python, Checkov, Git, jq, and unzip.

The generated `01` and `02` caller workflows select `self-hosted`. The Checkov job remains on `ubuntu-latest` so the security gate does not depend on the workload runner.

## Registration security

After Terraform creates the VM and repository, the PowerShell module requests a short-lived repository registration token from GitHub. It sends that token to Azure VM Run Command, registers the service, and verifies the runner is online. The registration token is not passed to Terraform or stored in Terraform state.

The runtime PAT still needs the documented bootstrap permissions and its owner must administer the generated repository. Clear the PAT after bootstrap.

## Verify readiness

In GitHub, open the generated repository and select **Settings > Actions > Runners**. The runner name follows `vm-<service>-<environment>-runner` and should show **Idle** with `self-hosted`, `Linux`, `X64`, and `aro` labels.

From an authorized terminal:

```powershell
gh api repos/<owner>/<repository>/actions/runners `
  --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'
```

A ready runner reports `status: online` and `busy: false`. Bootstrap also runs version checks for Azure CLI, Terraform, Docker, Checkov, and Git before reporting success.

## Security boundary

A persistent self-hosted runner executes repository workflow code. Restrict write and pull-request access, review workflow changes, and do not use it for untrusted fork pull requests. The runner is repository-scoped rather than account-wide.

The VM has a public IP only for outbound Internet access; the NSG defines no inbound allow rules. Emergency SSH requires a separately reviewed temporary NSG rule. Terraform state traffic resolves through the private endpoint.

## Cost and lifecycle

`Standard_D2s_v5` is the default. At the validated Sweden Central consumption rate, compute is approximately USD 0.102/hour, or USD 74.46 for a 730-hour month, excluding the OS disk, public IP, private endpoint, and network traffic. Stop or resize the VM only after considering workflow availability.

The runner is part of bootstrap state. `Deploy-AROLandingZone -BootstrapAction destroy` removes the VM, network, private endpoint, and runner registration along with the generated repository and other bootstrap resources.

## Troubleshooting

If registration fails, keep local Terraform state and rerun bootstrap apply after correcting the error. The module reuses an already configured runner service when possible.

Inspect VM provisioning and runner service safely:

```powershell
az vm get-instance-view `
  --resource-group <bootstrap-resource-group> `
  --name <runner-vm-name> `
  --query instanceView.statuses

az vm run-command invoke `
  --resource-group <bootstrap-resource-group> `
  --name <runner-vm-name> `
  --command-id RunShellScript `
  --scripts "systemctl --no-pager status 'actions.runner.*'"
```

Do not place a PAT or registration token in configuration, cloud-init, Terraform variables, or committed files.
