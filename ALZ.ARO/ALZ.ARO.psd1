@{
    RootModule        = 'ALZ.ARO.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '62980f45-d956-4721-a682-4a5e45275d49'
    Author            = 'ARO Application Landing Zone contributors'
    CompanyName       = 'Community'
    Copyright         = '(c) 2026 contributors. MIT License.'
    Description       = 'Bootstrap an Azure Red Hat OpenShift application landing zone and GitHub OIDC delivery repository.'
    PowerShellVersion = '7.2'
    FunctionsToExport = @('Deploy-AROLandingZone')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{ PSData = @{ Tags = @('Azure', 'ARO', 'Terraform', 'ALZ', 'GitHubActions') } }
}
