#Requires -Version 7.2
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$manifest = Join-Path $root 'ALZ.ARO\ALZ.ARO.psd1'
Test-ModuleManifest $manifest -ErrorAction Stop | Out-Null
Import-Module $manifest -Force
if (-not (Get-Command Deploy-AROLandingZone -ErrorAction SilentlyContinue)) { throw 'Public cmdlet was not exported.' }

$tfRoots = @(
    Join-Path $root 'bootstrap\alz\github'
    Join-Path $root 'ALZ.ARO\templates\terraform'
)
if (Get-Command terraform -ErrorAction SilentlyContinue) {
    foreach ($directory in $tfRoots) {
        $chdirArgument = "-chdir=$directory"
        & terraform $chdirArgument fmt -check -recursive
        if ($LASTEXITCODE -ne 0) { throw "terraform fmt failed: $directory" }
        & terraform $chdirArgument init -backend=false -input=false
        if ($LASTEXITCODE -ne 0) { throw "terraform init failed: $directory" }
        & terraform $chdirArgument validate
        if ($LASTEXITCODE -ne 0) { throw "terraform validate failed: $directory" }
    }
} else { Write-Warning 'terraform not found; skipped Terraform validation.' }

if (Get-Module -ListAvailable Pester) {
    Invoke-Pester -Path (Join-Path $root 'tests') -Output Detailed
} else { Write-Warning 'Pester not installed; skipped tests.' }
