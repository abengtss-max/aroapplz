# Prerequisites

Complete the tooling, access, and platform checks before generating a bootstrap plan.

## Operator workstation

| Requirement | Repository contract |
| --- | --- |
| PowerShell | 7.2 or later |
| Terraform | 1.9 or later; repository validation currently uses 1.9.8 |
| Azure CLI | Installed, authenticated, and providing the `az aro` command |
| GitHub token | Dedicated fine-grained PAT in `GITHUB_TOKEN` or `GH_TOKEN`; repository permissions are listed below |
| Git | Required for the normal review workflow |

The module preflight verifies `az`, `terraform`, Azure CLI authentication, subscription visibility, and presence of a GitHub token. In `spoke` mode it also verifies that the existing hub VNet can be read.

## Azure access

The interactive bootstrap operator needs enough access to create and configure:

- the Azure Storage account/container used for workload Terraform state;
- user-assigned managed identities;
- federated identity credentials and Azure role assignments;
- the later workload resources in the target subscriptions.

The exact authority model is organization-specific. Confirm it with the subscription and Entra administrators before running apply.

## ARO prerequisites

Prepare and verify:

- a workload subscription registered for `Microsoft.RedHatOpenShift` with sufficient regional quota;
- a unique ARO domain prefix;
- non-overlapping VNet, control-plane subnet, worker subnet, pod, and service CIDRs;
- an optional Red Hat pull secret when required by the intended workload.

Bootstrap discovers the Microsoft-managed ARO resource-provider identity. Workload Terraform creates the cluster and operator managed identities and their role assignments.

ARO versions vary by region. The module calls `az aro get-versions --location` against the workload subscription, validates an explicitly supplied version or chooses the newest version returned, and persists the exact result before planning bootstrap.

## GitHub controls

- Bootstrap creates the private GitHub workload repository, environments, variables, generated files, and workflows through the Terraform GitHub provider.
- The PAT user must be allowed to create private repositories and administer repository contents, Actions variables, and environments for the configured owner.
- Prefer a fine-grained PAT scoped to the configured resource owner and **All repositories**, because bootstrap creates a repository that does not exist when the token is issued.
- Grant repository permissions **Administration**, **Actions**, **Contents**, **Environments**, **Variables**, and **Workflows** at **Read and write**. Administration permits creation, management, and later deletion of the generated repository.
- For an organization, confirm that fine-grained PAT policy permits the token and wait for administrator approval when required. Do not store the PAT in configuration or generated repository secrets.
- The requested target repository name must be available to the supplied owner or organization.
- Supply at least one GitHub username in `apply_approvers`.
- Confirm the owner permits private-repository creation, GitHub environments, Actions, and OIDC. Required reviewers on private repositories require GitHub Enterprise; other plans retain the manual immutable-SHA and exact-plan safeguards but cannot add the reviewer protection rule.
- Plan how to add the runtime secrets to both generated `plan` and `apply` environments after bootstrap.

## GitHub runner

A GitHub Actions runner is an external prerequisite, exactly like the hub. Provide either a GitHub-hosted runner or one your organization operates, and set `runner_label` to its label. The accelerator selects a runner; it never creates, registers, or removes one, and bootstrap destroy leaves it untouched.

The runner must reach the Terraform state storage endpoint. Where policy denies public network access on storage, a GitHub-hosted runner cannot reach the backend, so the runner needs private network connectivity to it.

The runner also has to satisfy two requirements that are easy to miss on a self-managed host:

- **Azure CLI must be installed.** `azure/login` performs `az login` internally, so a runner image without the Azure CLI fails at the sign-in step even though the workflow itself never calls `az`.
- **The runner must survive a long job.** Creating an ARO cluster takes roughly 45 to 60 minutes in a single Terraform apply. Anything that restarts the runner service mid-job cancels the deployment and leaves the cluster still installing while Terraform loses track of it. On Ubuntu hosts, `unattended-upgrades` combined with `needrestart` will do exactly this when a library is patched. Either exclude the runner service from automatic restarts or schedule patching outside deployment windows.

### Optional: let bootstrap create the runners

If you do not already operate a suitable runner, set `self_hosted_runner_enabled` to `true` and bootstrap will build one for you on Azure Container Instances. This is off by default; leave it `false` to keep using your own runner. See [self-hosted runners](../operations/self-hosted-runner.md) for what it creates and what it costs.

## Extra requirements for `spoke`

`spoke` requires an existing hub VNet and an existing firewall or NVA next hop. Obtain:

- the connectivity subscription ID;
- the full existing hub VNet resource ID;
- the private IP of the existing firewall/NVA;
- platform-owner approval for bidirectional peering, forwarded traffic, UDR behavior, DNS, and ARO-required egress.

The hub VNet ID must belong to the configured connectivity subscription. aroapplz references these platform resources but does not create or manage them.

## Policy and cost review

Before apply, evaluate deny policies, required tags, allowed regions/SKUs, role-assignment restrictions, public network rules, and centralized DNS requirements. Also review current ARO and dependent Azure service pricing. See [ALZ corporate policy](../governance/alz-corp-policy.md) for the implemented state-access trade-off.

!!! warning "Azure Landing Zone policy carve-out"
    In a default Azure Landing Zone, `Deny-PublicPaaSEndpoints` blocks ARO cluster creation because ARO requires public endpoint reachability on the storage accounts in its own managed resource group. The accelerator cannot fix this from workload Terraform.

    A platform or governance owner must create the policy exemption **before the first workload apply**. Bootstrap does not need it; the workload `apply` that creates the cluster does. The bootstrap preflight warns when a known-blocking assignment is enforced, naming the assignment and the resource group to scope to.

    Commands: [Create the exemption](../governance/azure-landing-zone.md#create-the-exemption).
