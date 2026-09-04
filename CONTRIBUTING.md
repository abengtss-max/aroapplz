# Contributing

Use focused pull requests and preserve the two-mode contract. Never add a mode that adopts an existing spoke, and never add hub/firewall/NVA resources to workload Terraform.

Before submitting, run the project validation script, Pester tests, Terraform formatting/validation, and Checkov. Add tests for identity, workflow safety, and conditional resource behavior. Do not commit generated plans, state, local configuration, credentials, subscription/tenant values, pull secrets, or ARO client secrets.

Stable major tags are used for public GitHub Actions because verified immutable SHAs are not maintained in this initial scaffold. Dependabot is configured for monthly update proposals; organizations may pin reviewed commits in their generated repository.
