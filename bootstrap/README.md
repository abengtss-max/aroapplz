# Bootstrap

The composition in `alz/github` creates only bootstrap resources: hardened Azure Storage state, two user-assigned managed identities with GitHub-environment federated credentials, role assignments, and a private GitHub workload repository with environments, variables, Terraform, and workflows.

No managed identities or Azure client secrets are created. GitHub provider authentication is supplied at runtime with `GITHUB_TOKEN` or `GH_TOKEN`. The bootstrap state initially remains local; secure it according to organizational policy after first apply. The generated workload state uses the new Azure Storage backend with Entra authorization.

The storage data endpoint is public because GitHub-hosted runners need to reach it, but anonymous access and shared-key authentication are disabled; TLS, infrastructure encryption, ZRS, versioning, change feed, and 30-day deletion retention are enabled. Add private endpoints and self-hosted runners if policy requires network isolation.
