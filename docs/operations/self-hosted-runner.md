# Azure self-hosted GitHub runner

Self-hosted runners are external prerequisites, not resources owned by the ARO Application Landing Zone Accelerator. Use one when Azure Policy disables public access to the Terraform state account or when workflows require execution from Azure.

## Enable the runner

Provision and register a repository-scoped runner independently, then select it in ignored `config/local.json`:

```json
{
  "runner_label": "self-hosted"
}
```

The external runner should provide:

- GitHub Actions runner, Azure CLI, Terraform, Docker, Python, Checkov, Git, jq, and unzip.

The generated `01` and `02` caller workflows select `self-hosted`. The Checkov job remains on `ubuntu-latest` so the security gate does not depend on the workload runner.

## Registration security

Create and consume the short-lived repository registration token outside this accelerator. Never pass it to accelerator Terraform or store it in accelerator state.

The runtime PAT still needs the documented bootstrap permissions and its owner must administer the generated repository. Clear the PAT after bootstrap.

## Verify readiness

In GitHub, open the generated repository and select **Settings > Actions > Runners**. The independently chosen runner name should show **Idle** with `self-hosted`, `Linux`, `X64`, and any required custom labels.

From an authorized terminal:

```powershell
gh api repos/<owner>/<repository>/actions/runners `
  --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'
```

A ready runner reports `status: online` and `busy: false`. Verify Azure CLI, Terraform, Docker, Checkov, and Git directly on the independently managed host.

## Security boundary

A persistent self-hosted runner executes repository workflow code. Restrict write and pull-request access, review workflow changes, and do not use it for untrusted fork pull requests. The runner is repository-scoped rather than account-wide.

The VM has a public IP only for outbound Internet access; the NSG defines no inbound allow rules. Emergency SSH requires a separately reviewed temporary NSG rule. Terraform state traffic resolves through the private endpoint.

## Cost and lifecycle

For the separate example deployment, `Standard_D2s_v5` costs approximately USD 0.102/hour, or USD 74.46 for a 730-hour month at the validated Sweden Central consumption rate, excluding the OS disk, public IP, private endpoint, and network traffic. Stop or resize the VM only after considering workflow availability.

The runner has an independent lifecycle and state. Accelerator bootstrap destroy does not remove the VM, its network, private endpoint, or registration.

## Troubleshooting

If registration fails, keep the runner's independent Terraform state and retry registration after correcting the error. Rerunning accelerator bootstrap does not register the runner.

Inspect VM provisioning and runner service safely:

```powershell
az vm get-instance-view `
  --resource-group <runner-resource-group> `
  --name <runner-vm-name> `
  --query instanceView.statuses

az vm run-command invoke `
  --resource-group <runner-resource-group> `
  --name <runner-vm-name> `
  --command-id RunShellScript `
  --scripts "systemctl --no-pager status 'actions.runner.*'"
```

Do not place a PAT or registration token in configuration, cloud-init, Terraform variables, or committed files.
