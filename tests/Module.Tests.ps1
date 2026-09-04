BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $manifest = Join-Path $root 'ALZ.ARO\ALZ.ARO.psd1'
}

Describe 'ALZ.ARO module' {
    It 'has a valid manifest' {
        Test-ModuleManifest $manifest | Should -Not -BeNullOrEmpty
    }

    It 'exports only the public entrypoint' {
        $module = Import-Module $manifest -Force -PassThru
        @($module.ExportedFunctions.Keys) | Should -Be @('Deploy-AROLandingZone')
    }

    It 'parses on PowerShell 7' {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'ALZ.ARO\ALZ.ARO.psm1'), [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }
}
