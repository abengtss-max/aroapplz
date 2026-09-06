# Self-hosted runners

Bootstrap can create GitHub Actions runners on Azure Container Instances so you do not have to operate a runner yourself. The feature is **off by default**. Everything on this page applies only when `self_hosted_runner_enabled` is `true`.

If you already run a suitable runner, leave the feature off and point `runner_label` at your own runner instead. Nothing else changes.

## Why you might want it

The Terraform state account denies public network access, so a GitHub-hosted runner cannot reach the backend. Without a runner inside a virtual network, you have to build that connectivity yourself. Turning this on solves it in the same bootstrap that creates the state account.

## What it creates

All of it lands in the existing bootstrap resource group, and bootstrap destroy removes it again.

| Resource | Purpose |
| --- | --- |
| Virtual network with two subnets | One delegated to Container Instances, one for private endpoints |
| NAT gateway and public IP | Outbound access from a single known address |
| Private endpoint to the state account | Lets the runner reach the Terraform backend privately |
| Container registry, Premium | Holds the runner image |
| Container registry task | Builds the image from the upstream Azure Verified Modules runner |
| Private endpoint to the registry | Keeps image pulls inside the virtual network |
| User-assigned identity | Pulls the image, holds `AcrPull` only |
| Container groups | The runners themselves, `runner_count` of them |

## Configuration

```json
{
  "runner_label": "self-hosted",
  "self_hosted_runner_enabled": true,
  "runner_count": 2,
  "runner_cpu": 2,
  "runner_memory_gb": 8,
  "runner_image_tag": "latest",
  "runner_virtual_network_cidr": "10.60.0.0/24",
  "runner_container_instances_subnet_cidr": "10.60.0.0/26",
  "runner_private_endpoint_subnet_cidr": "10.60.0.64/26"
}
```

The three address ranges must not overlap the cluster virtual network or the hub. `runner_label` must name a self-hosted label, because the created runners never carry `ubuntu-latest`.

## The registration token

The runners register themselves using a personal access token, which they exchange for a short-lived registration token at startup. Supply it through the environment so it is never written to the configuration file or the generated Terraform variables:

```powershell
$env:GITHUB_RUNNER_TOKEN = Read-Host 'PAT for runner registration' -MaskInput
```

The token needs permission to manage runners on the generated repository. It is passed to Azure as a secure environment variable on the container group, so it is not readable from the container's normal environment listing.

!!! warning "The masked prompt does not mask everywhere"
    `Read-Host -MaskInput` does not mask in the PowerShell extension terminal in Visual Studio Code. Use a normal PowerShell 7 terminal when entering the token.

## Security decisions worth knowing

Two choices here differ from the common pattern of a shared organization runner pool, and both are deliberate.

**Runners are scoped to one repository.** They register against the generated workload repository, not the organization. A runner can therefore only ever accept jobs for its own landing zone. An organization-wide pool would let any repository in the organization run code on a host that also runs your infrastructure deployments.

**Runners are ephemeral.** The container exits after a single job and the restart policy registers a fresh one. No workspace, cached credential, or `~/.azure` token survives from one job to the next. A persistent runner shared between pipelines is a credential-theft path, because a job can leave something behind for the next job to find.

Azure permissions are unaffected by either choice: the runner's own identity holds only `AcrPull`, and deployment permissions come from the workload identity federation bound to the repository environment, not from the runner.

## Operational limits

- **A container restart cancels a running job.** Creating an ARO cluster is a single Terraform apply of roughly 45 to 60 minutes. If Container Instances restarts the group for platform maintenance during that window, the job is cancelled and the cluster carries on installing while Terraform loses track of it. Recover by clearing the state lock and re-running apply.
- **The registry allows public network access.** Registry tasks build on Azure-managed public agents that cannot reach a private-only registry, so the registry keeps public access with the `AzureServices` bypass while the private endpoint carries the runners' pull traffic. Disabling public access breaks the image build.
- **Runners are billed while idle.** They run continuously waiting for jobs. Reduce `runner_count` or turn the feature off when the landing zone is not being changed.
