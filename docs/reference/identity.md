# Identity and authorization

aroapplz uses separate user-assigned managed identities for GitHub delivery and ARO platform operations.

## Bootstrap operator

Bootstrap authenticates interactively to Azure through the operator's current Azure CLI context and to GitHub through `GITHUB_TOKEN` or `GH_TOKEN`. The token is supplied at runtime and is not written or printed by the module.

The operator must be authorized to create the configured Azure, Entra, RBAC, repository, and environment resources.

## GitHub OIDC identities

Bootstrap creates two user-assigned managed identities:

| Identity | Azure role | Scope | State access |
| --- | --- | --- | --- |
| Plan | `Reader` | Workload subscription | `Storage Blob Data Contributor` on workload state container |
| Apply | `Contributor` and `Role Based Access Control Administrator` | Workload subscription | `Storage Blob Data Contributor` on workload state container |

Each managed identity receives one federated credential scoped to its GitHub environment. Subjects follow `repo:<owner>/<repo>:environment:plan` and `repo:<owner>/<repo>:environment:apply`.

Generated workflows set `ARM_USE_OIDC=true` and use the environment-specific client ID. Bootstrap creates no Azure application password/client secret for these GitHub identities.

!!! warning "Current apply scope"
    The apply identity is subscription-scoped because workload Terraform creates its resource group and ARO role assignments later. This is broad. Organizations can pre-create an appropriate deployment scope and substitute tested custom roles, but must preserve resource lifecycle and role-assignment permissions.

## ARO managed identities

ARO provisioning creates one cluster user-assigned identity and eight platform workload identities: `aro-operator`, `cloud-controller-manager`, `cloud-network-config`, `disk-csi-driver`, `file-csi-driver`, `image-registry`, `ingress`, and `machine-api`.

Terraform assigns each identity its ARO built-in role at the narrowest supported VNet, subnet, route-table, or identity scope. The cluster identity receives `Azure Red Hat OpenShift Federated Credential` on every operator identity. The Microsoft-managed ARO resource provider receives `Azure Red Hat OpenShift First Party Network` on the ARO VNet. No ARO client secret is created or stored.

## Red Hat pull secret

`REDHAT_PULL_SECRET` is optional in the template and is also handled as a protected runtime value and sensitive Terraform variable. Do not place it in local JSON, generated files, logs, or pull requests.

## State access boundary

Workload Terraform state uses Azure Storage with Microsoft Entra data-plane authorization. Anonymous blob access and shared-key authentication are disabled by the bootstrap design. The data endpoint remains network-public for GitHub-hosted runner reachability; private endpoint enforcement requires a self-hosted runner design.

## Rotation and review

- Review plan/apply federated subjects and role assignments after repository or environment changes.
- Review all ARO managed-identity and federated-credential role assignments after version upgrades.
- Rotate the optional Red Hat pull secret when required.
- Audit access to GitHub environments and the state container.
- Revalidate custom-role changes against plans before reducing permissions.
