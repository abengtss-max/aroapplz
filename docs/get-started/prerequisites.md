# Prerequisites

Complete the tooling, access, and platform checks before generating a bootstrap plan.

## Operator workstation

| Requirement | Repository contract |
| --- | --- |
| PowerShell | 7.2 or later |
| Terraform | 1.9 or later; repository validation currently uses 1.9.8 |
| Azure CLI | Installed, authenticated, and providing the `az aro` command |
| GitHub token | Runtime-only PAT in `GITHUB_TOKEN` or `GH_TOKEN`; classic scopes: `repo`, `workflow`, and `read:org` for an organization target |
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

- a workload subscription with ARO resource-provider readiness and sufficient regional quota;
- a unique ARO domain prefix;
- non-overlapping VNet, control-plane subnet, worker subnet, pod, and service CIDRs;
- an optional Red Hat pull secret when required by the intended workload.

Bootstrap discovers the Microsoft-managed ARO resource-provider identity. Workload Terraform creates the cluster and operator managed identities and their role assignments.

ARO versions vary by region. The module calls `az aro get-versions --location` against the workload subscription, validates an explicitly supplied version or chooses the newest version returned, and persists the exact result before planning bootstrap.

## GitHub controls

- Bootstrap creates the private GitHub workload repository, environments, variables, generated files, and workflows through the Terraform GitHub provider.
- The PAT user must be allowed to create private repositories and administer repository contents, Actions variables, and environments for the configured owner.
- A classic PAT needs `repo` and `workflow`; add `read:org` when the configured owner is an organization. `admin:org`, `delete_repo`, and package scopes are not required.
- For an organization, authorize the PAT for SAML SSO when required and confirm that organization PAT policy permits it. Do not store the PAT in configuration or generated repository secrets.
- The requested target repository name must be available to the supplied owner or organization.
- Supply at least one GitHub username in `apply_approvers`.
- Confirm the owner permits private-repository creation, GitHub environments, Actions, and OIDC. Required reviewers on private repositories require GitHub Enterprise; other plans retain the manual immutable-SHA and exact-plan safeguards but cannot add the reviewer protection rule.
- Plan how to add the runtime secrets to both generated `plan` and `apply` environments after bootstrap.

## Extra requirements for `spoke`

`spoke` requires an existing hub VNet and an existing firewall or NVA next hop. Obtain:

- the connectivity subscription ID;
- the full existing hub VNet resource ID;
- the private IP of the existing firewall/NVA;
- platform-owner approval for bidirectional peering, forwarded traffic, UDR behavior, DNS, and ARO-required egress.

The hub VNet ID must belong to the configured connectivity subscription. aroapplz references these platform resources but does not create or manage them.

## Policy and cost review

Before apply, evaluate deny policies, required tags, allowed regions/SKUs, role-assignment restrictions, public network rules, and centralized DNS requirements. Also review current ARO and dependent Azure service pricing. See [ALZ corporate policy](../governance/alz-corp-policy.md) for the implemented state-access trade-off.
