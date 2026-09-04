# Security

## Reporting

Report suspected vulnerabilities privately through GitHub Security Advisories. Do not open public issues containing credentials, tenant details, or exploit material.

## Credential model

GitHub Actions uses Entra workload identity federation. No Azure client secret is created for CI/CD. The ARO service-principal client secret and Red Hat pull secret are supplied at runtime as sensitive Terraform variables and must be stored as protected GitHub environment secrets or an approved secret manager; they are never generated, printed, or committed by this project.

Review Terraform plans because they can contain sensitive metadata. State is encrypted by Azure Storage, protected with Entra authorization, network restrictions, versioning, and retention.
