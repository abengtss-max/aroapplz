# Identity and authorization

Bootstrap authenticates interactively to Azure and through a runtime GitHub token. It creates two Microsoft Entra applications and corresponding service principals:

- plan: `Reader` on the workload subscription and `Storage Blob Data Contributor` on the workload state container.
- apply: `Contributor` on the workload subscription and `Storage Blob Data Contributor` on the state container.

Each application has one federated credential scoped to its GitHub environment. Workflows set `ARM_USE_OIDC=true` and consume an environment-specific client ID; no Azure application password/client secret exists.

The apply assignment is intentionally subscription-scoped because Terraform creates the workload resource group later. A production platform can reduce scope by pre-creating a deployment scope and substituting a tested custom role. Any reduction must retain permissions for ARO, networking, role assignments required by ARO, and resource-group lifecycle.

ARO itself still requires a dedicated service principal. Its secret is an unavoidable ARO API input and is handled as a sensitive Terraform variable, separate from CI/CD authentication.
