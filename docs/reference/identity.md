# Identity and authorization

aroapplz keeps GitHub pipeline identity separate from the service principal required by ARO itself.

## Bootstrap operator

Bootstrap authenticates interactively to Azure through the operator's current Azure CLI context and to GitHub through `GITHUB_TOKEN` or `GH_TOKEN`. The token is supplied at runtime and is not written or printed by the module.

The operator must be authorized to create the configured Azure, Entra, RBAC, repository, and environment resources.

## GitHub OIDC identities

Bootstrap creates two Microsoft Entra applications and corresponding service principals:

| Identity | Azure role | Scope | State access |
| --- | --- | --- | --- |
| Plan | `Reader` | Workload subscription | `Storage Blob Data Contributor` on workload state container |
| Apply | `Contributor` | Workload subscription | `Storage Blob Data Contributor` on workload state container |

Each application receives one federated credential scoped to its GitHub environment. Subjects follow `repo:<owner>/<repo>:environment:plan` and `repo:<owner>/<repo>:environment:apply`.

Generated workflows set `ARM_USE_OIDC=true` and use the environment-specific client ID. Bootstrap creates no Azure application password/client secret for these GitHub identities.

!!! warning "Current apply scope"
    The apply principal is subscription-scoped because workload Terraform creates its resource group later. This is broad. Organizations can pre-create an appropriate deployment scope and substitute a tested custom role, but must preserve every permission required for ARO, networking, ARO-related role assignments, and resource-group lifecycle.

## ARO service principal

ARO provisioning still requires a dedicated service principal. The generated workflow receives its client ID, object ID, and client secret at runtime. The client secret is a sensitive Terraform variable and can therefore be present in protected workflow runtime and Terraform state; protect both accordingly.

This ARO principal is not the plan identity and is not the apply identity. GitHub OIDC does not remove the ARO API's service-principal secret requirement.

## Red Hat pull secret

`REDHAT_PULL_SECRET` is optional in the template and is also handled as a protected runtime value and sensitive Terraform variable. Do not place it in local JSON, generated files, logs, or pull requests.

## State access boundary

Workload Terraform state uses Azure Storage with Microsoft Entra data-plane authorization. Anonymous blob access and shared-key authentication are disabled by the bootstrap design. The data endpoint remains network-public for GitHub-hosted runner reachability; private endpoint enforcement requires a self-hosted runner design.

## Rotation and review

- Review plan/apply federated subjects and role assignments after repository or environment changes.
- Rotate the ARO service-principal secret using the organization's approved procedure and update both protected environments.
- Rotate the optional Red Hat pull secret when required.
- Audit access to GitHub environments and the state container.
- Revalidate custom-role changes against plans before reducing permissions.
