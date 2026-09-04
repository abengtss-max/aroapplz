# Day-2 operations

- Keep the exact ARO version pin under pull-request review. Re-run regional version discovery before changing it and review the ARO support lifecycle.
- Use CI for formatting, validation, security checks, and speculative plans. Use manual CD with an immutable full SHA for changes.
- Monitor state storage retention, RBAC, diagnostic coverage, ARO health, quota, certificates, egress, and hub peering status.
- Apply provider and GitHub Action updates from Dependabot after validation.
- Test restore procedures for state blobs and retain platform records for the external hub/NVA dependencies.
- Use the manual destroy workflow only from the default branch with `DELETE`, the current full SHA, and protected-environment approval. Destroy workload resources before separately retiring bootstrap resources.

Front Door remains operator-owned follow-on work. When selected, Application Gateway is Terraform-owned; monitor its WAF, backend health, public IP, certificates, and Log Analytics diagnostics.
