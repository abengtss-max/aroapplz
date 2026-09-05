# Identity and authorization

Bootstrap authenticates interactively to Azure and through a runtime GitHub token. It creates two user-assigned managed identities:

- plan: `Reader` on the workload subscription and `Storage Blob Data Contributor` on the workload state container.
- apply: `Contributor` and `Role Based Access Control Administrator` on the workload subscription and `Storage Blob Data Contributor` on the state container.

Each identity has one federated credential scoped to its GitHub environment. Workflows set `ARM_USE_OIDC=true` and consume an environment-specific client ID; no Azure application password/client secret exists.

The apply assignment is intentionally subscription-scoped because Terraform creates the workload resource group later. A production platform can reduce scope by pre-creating a deployment scope and substituting a tested custom role. Any reduction must retain permissions for ARO, networking, role assignments required by ARO, and resource-group lifecycle.

ARO uses one cluster user-assigned identity and eight platform workload identities with least-privilege ARO built-in roles. No ARO client secret is created or stored.
