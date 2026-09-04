# Azure Landing Zones corp and policy guidance

Target the workload subscription to an ALZ landing-zone management group before deployment. Typical controls include Defender for Cloud, diagnostic settings, approved regions/SKUs, private endpoints, DDoS/network controls, and centralized DNS.

Policy assignments are deliberately not created here: they belong to the platform scope. Validate policy effects before apply, especially deny policies for public network access, required tags, allowed VM sizes, route tables, private DNS, and role assignments. A policy requiring private access to Terraform state also requires a self-hosted runner with network reachability; the default GitHub-hosted design keeps the state endpoint public but Entra-only.

For `spoke`, platform owners must approve address space, bidirectional peering, forwarded traffic, UDR propagation behavior, DNS, and firewall egress required by ARO. This accelerator references but never manages existing platform resources.
