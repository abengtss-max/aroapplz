- [x] Verify that the copilot-instructions.md file in the .github directory is created.

- [x] Clarify Project Requirements

- [x] Scaffold the Project

- [x] Customize the Project

- [x] Install Required Extensions

- [x] Compile the Project

- [x] Create and Run Task

- [x] Launch the Project

- [x] Ensure Documentation is Complete

- Work through each checklist item systematically.
- Keep communication concise and focused.
- Follow development best practices.
- The only supported deployment modes are `standalone` and `spoke`.
- Both modes create and own the ARO VNet and ARO subnets.
- `spoke` peers to an existing hub and routes through an existing firewall or NVA; never create or destroy the hub, firewall, or NVA.
- Existing platform resources must be referenced with data sources or resource IDs.
- Never commit, print, or expose service-principal secrets.
