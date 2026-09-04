#Requires -Version 7.2
[CmdletBinding()]
param(
    [string]$Scope = 'CurrentUser'
)

$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'ALZ.ARO'
$destinationRoot = if ($Scope -eq 'AllUsers') {
    Join-Path $env:ProgramFiles 'PowerShell\Modules'
} else {
    Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules'
}
$destination = Join-Path $destinationRoot 'ALZ.ARO'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
Copy-Item -Path (Join-Path $source '*') -Destination $destination -Recurse -Force
Write-Host "ALZ.ARO installed at $destination"
Write-Host 'Import with: Import-Module ALZ.ARO'
