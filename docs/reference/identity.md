# Identity and authorization

aroapplz uses separate user-assigned managed identities for GitHub delivery and ARO platform operations.

## Bootstrap operator

Bootstrap authenticates interactively to Azure through the operator's current Azure CLI context and to GitHub through a runtime-only PAT in `GITHUB_TOKEN` or `GH_TOKEN`. The Terraform GitHub provider reads `GITHUB_TOKEN`; when only `GH_TOKEN` is supplied, the module maps it to `GITHUB_TOKEN` in process memory. The token is not written or printed by the module.

The bootstrap is responsible for creating the private workload repository, protected environments, Actions variables, generated source files, and workflows. A classic PAT requires `repo` and `workflow`; add `read:org` when the configured owner is an organization. It does not require `admin:org`, `delete_repo`, package scopes, or Azure permissions for creation/update. The token owner must be permitted to create and administer repositories for the configured user or organization. Organization SAML SSO and PAT policies still apply. Remove the environment variable after bootstrap; it is not used by generated workload workflows, which authenticate to Azure through OIDC.

Self-hosted runner registration is external to the accelerator. No runner registration token is requested, accepted as Terraform input, or stored in accelerator state.

The operator must be authorized to create the configured Azure, Entra, RBAC, repository, and environment resources.

## GitHub OIDC identities

Bootstrap creates two user-assigned managed identities:

| Identity | Azure role | Scope | State access |
| --- | --- | --- | --- |
| Plan | `Reader` | Workload subscription | `Storage Blob Data Contributor` on workload state container |
| Apply | `Contributor` and `Role Based Access Control Administrator` | Workload subscription | `Storage Blob Data Contributor` on workload state container |

Each managed identity receives one federated credential scoped to its GitHub environment. For repositories created after July 15, 2026, subjects use GitHub's immutable owner and repository IDs: `repo:<owner>@<owner-id>/<repo>@<repo-id>:environment:plan` and the corresponding `apply` subject. Bootstrap obtains both IDs rather than treating names as the complete trust boundary.

Generated workflows set `ARM_USE_OIDC=true` and use the environment-specific client ID. Bootstrap creates no Azure application password/client secret for these GitHub identities.

!!! warning "Current apply scope"
    The apply identity is subscription-scoped because workload Terraform creates its resource group and ARO role assignments later. This is broad. Organizations can pre-create an appropriate deployment scope and substitute tested custom roles, but must preserve resource lifecycle and role-assignment permissions.

## ARO managed identities

ARO provisioning creates one cluster user-assigned identity and eight platform workload identities: `aro-operator`, `cloud-controller-manager`, `cloud-network-config`, `disk-csi-driver`, `file-csi-driver`, `image-registry`, `ingress`, and `machine-api`.

Terraform assigns each identity its ARO built-in role at the narrowest supported VNet, subnet, route-table, or identity scope. The cluster identity receives `Azure Red Hat OpenShift Federated Credential` on every operator identity. The Microsoft-managed ARO resource provider receives `Azure Red Hat OpenShift First Party Network` on the ARO VNet. No ARO client secret is created or stored.

## Red Hat pull secret

`REDHAT_PULL_SECRET` is optional in the template and is also handled as a protected runtime value and sensitive Terraform variable. Do not place it in local JSON, generated files, logs, or pull requests.

## State access boundary

Workload Terraform state uses Azure Storage with Microsoft Entra data-plane authorization. Anonymous blob access and shared-key authentication are disabled by the bootstrap design. If Azure Policy disables public network access, an independently managed self-hosted runner needs private endpoint and DNS connectivity to the blob endpoint.

## Rotation and review

- Review plan/apply federated subjects and role assignments after repository or environment changes.
- Review all ARO managed-identity and federated-credential role assignments after version upgrades.
- Rotate the optional Red Hat pull secret when required.
- Audit access to GitHub environments and the state container.
- Revalidate custom-role changes against plans before reducing permissions.
