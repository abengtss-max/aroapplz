Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-NativeCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Command, [Parameter(Mandatory)][string[]]$Arguments)

    $output = & $Command @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed (exit $LASTEXITCODE): $($output -join [Environment]::NewLine)"
    }
    return ($output -join [Environment]::NewLine)
}

function Read-AROConfig {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Configuration file not found: $Path" }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable }
    catch { throw "Configuration must be valid JSON: $($_.Exception.Message)" }
}

function New-AROConfigWizard {
    param([Parameter(Mandatory)][string]$OutputPath)

    $mode = Read-Host 'Deployment mode (standalone/spoke)'
    $approverInput = Read-Host 'GitHub apply approver usernames (comma-separated; at least one)'
    $config = [ordered]@{
        deployment_mode = $mode
        tenant_id = Read-Host 'Microsoft Entra tenant ID'
        bootstrap_subscription_id = Read-Host 'Bootstrap subscription ID'
        workload_subscription_id = Read-Host 'ARO workload subscription ID'
        connectivity_subscription_id = if ($mode -eq 'spoke') { Read-Host 'Existing hub connectivity subscription ID' } else { '' }
        location = Read-Host 'Azure region (for example eastus)'
        service_name = Read-Host 'Short service name'
        environment_name = Read-Host 'Environment name'
        github_organization = Read-Host 'GitHub organization or owner'
        github_repository = Read-Host 'New workload repository name'
        apply_approvers = @($approverInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        aro_version = Read-Host 'ARO version (leave empty to resolve newest available)'
        aro_domain = Read-Host 'Unique ARO domain prefix'
        aro_vnet_cidr = Read-Host 'New ARO VNet CIDR'
        control_plane_subnet_cidr = Read-Host 'Control-plane subnet CIDR'
        worker_subnet_cidr = Read-Host 'Worker subnet CIDR'
        hub_vnet_id = if ($mode -eq 'spoke') { Read-Host 'Existing hub VNet resource ID' } else { '' }
        next_hop_ip = if ($mode -eq 'spoke') { Read-Host 'Existing firewall/NVA private IP' } else { '' }
        ingress_mode = Read-Host 'Ingress mode (none/front_door/application_gateway; default none)'
    }
    if ([string]::IsNullOrWhiteSpace($config.ingress_mode)) { $config.ingress_mode = 'none' }
    $parent = Split-Path -Parent $OutputPath
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
    return $config
}

function Assert-AROConfig {
    param([Parameter(Mandatory)][hashtable]$Config)

    $required = @('deployment_mode','tenant_id','bootstrap_subscription_id','workload_subscription_id','location','service_name','environment_name','github_organization','github_repository','aro_domain','aro_vnet_cidr','control_plane_subnet_cidr','worker_subnet_cidr','ingress_mode')
    foreach ($name in $required) {
        if (-not $Config.ContainsKey($name) -or [string]::IsNullOrWhiteSpace([string]$Config[$name])) { throw "Missing required configuration value '$name'." }
    }
    if ($Config.deployment_mode -notin @('standalone','spoke')) { throw "deployment_mode must be exactly 'standalone' or 'spoke'." }
    if ($Config.ingress_mode -notin @('none','front_door','application_gateway')) { throw "ingress_mode must be exactly 'none', 'front_door', or 'application_gateway'." }
    if (-not $Config.ContainsKey('apply_approvers') -or @($Config.apply_approvers).Count -eq 0) { throw 'At least one GitHub apply approver is required to protect apply and destroy.' }
    if ($Config.deployment_mode -eq 'spoke') {
        foreach ($name in @('connectivity_subscription_id','hub_vnet_id','next_hop_ip')) {
            if (-not $Config.ContainsKey($name) -or [string]::IsNullOrWhiteSpace([string]$Config[$name])) { throw "spoke mode requires '$name'." }
        }
        if ($Config.hub_vnet_id -notmatch '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Network/virtualNetworks/[^/]+$') { throw 'hub_vnet_id must be a complete Azure VNet resource ID.' }
        $hubSubscription = ($Config.hub_vnet_id -split '/')[2]
        if ($hubSubscription -ne $Config.connectivity_subscription_id) { throw 'hub_vnet_id subscription must match connectivity_subscription_id.' }
        $ip = $null
        if (-not [System.Net.IPAddress]::TryParse([string]$Config.next_hop_ip, [ref]$ip)) { throw 'next_hop_ip must be an IP address.' }
    }
}

function Invoke-AROPreflight {
    param([Parameter(Mandatory)][hashtable]$Config)

    foreach ($tool in @('az','terraform')) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Required command '$tool' is not available on PATH." }
    }
    $account = Invoke-NativeCommand az @('account','show','--output','json') | ConvertFrom-Json
    if (-not $account.id) { throw 'Azure CLI is not authenticated. Run az login.' }
    if ([string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN) -and [string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
        throw 'Set GITHUB_TOKEN or GH_TOKEN for the Terraform GitHub provider. The value is never written or printed.'
    }
    [void](Invoke-NativeCommand az @('account','show','--subscription',[string]$Config.bootstrap_subscription_id,'--output','none'))
    [void](Invoke-NativeCommand az @('account','show','--subscription',[string]$Config.workload_subscription_id,'--output','none'))
    if ($Config.deployment_mode -eq 'spoke') {
        [void](Invoke-NativeCommand az @('network','vnet','show','--ids',[string]$Config.hub_vnet_id,'--subscription',[string]$Config.connectivity_subscription_id,'--output','none'))
    }
}

function Resolve-AROVersion {
    param([Parameter(Mandatory)][hashtable]$Config)

    $raw = Invoke-NativeCommand az @('aro','get-versions','--location',[string]$Config.location,'--subscription',[string]$Config.workload_subscription_id,'--output','json')
    $result = $raw | ConvertFrom-Json
    $versions = @($result | ForEach-Object {
        if ($_ -is [string]) { $_ }
        elseif ($_.version) { [string]$_.version }
    } | Where-Object { $_ } | Sort-Object { [version]($_ -replace '[^0-9.].*$','') } -Descending -Unique)
    if ($versions.Count -eq 0) { throw "No ARO versions were returned for location '$($Config.location)'." }
    if (-not [string]::IsNullOrWhiteSpace([string]$Config.aro_version)) {
        if ([string]$Config.aro_version -notin $versions) { throw "ARO version '$($Config.aro_version)' is unavailable in '$($Config.location)'. Available: $($versions -join ', ')." }
        return [string]$Config.aro_version
    }
    return [string]$versions[0]
}

function New-BootstrapInput {
    param([hashtable]$Config, [string]$RepositoryRoot, [string]$OutputPath)

    $files = @{}
    $templateRoot = Join-Path $RepositoryRoot 'ALZ.ARO\templates'
    Get-ChildItem -LiteralPath $templateRoot -File -Recurse | ForEach-Object {
        $relative = [IO.Path]::GetRelativePath($templateRoot, $_.FullName).Replace('\','/')
        $files[$relative] = Get-Content -LiteralPath $_.FullName -Raw
    }
    $workload = [ordered]@{
        deployment_mode = $Config.deployment_mode
        tenant_id = $Config.tenant_id
        workload_subscription_id = $Config.workload_subscription_id
        connectivity_subscription_id = $Config.connectivity_subscription_id
        location = $Config.location
        resource_group_name = "rg-$($Config.service_name)-$($Config.environment_name)-aro"
        cluster_name = "aro-$($Config.service_name)-$($Config.environment_name)"
        aro_domain = $Config.aro_domain
        aro_version = $Config.aro_version
        aro_vnet_cidr = $Config.aro_vnet_cidr
        control_plane_subnet_cidr = $Config.control_plane_subnet_cidr
        worker_subnet_cidr = $Config.worker_subnet_cidr
        hub_vnet_id = $Config.hub_vnet_id
        next_hop_ip = $Config.next_hop_ip
        ingress_mode = $Config.ingress_mode
    }
    $files['terraform/aro.auto.tfvars.json'] = $workload | ConvertTo-Json -Depth 10
    $input = [ordered]@{
        tenant_id = $Config.tenant_id
        bootstrap_subscription_id = $Config.bootstrap_subscription_id
        workload_subscription_id = $Config.workload_subscription_id
        connectivity_subscription_id = $Config.connectivity_subscription_id
        location = $Config.location
        service_name = $Config.service_name
        environment_name = $Config.environment_name
        github_organization = $Config.github_organization
        github_repository = $Config.github_repository
        apply_approvers = @($Config.apply_approvers)
        repository_files = $files
    }
    $input | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
}

function Deploy-AROLandingZone {
    <#
    .SYNOPSIS
    Generates configuration and plans or applies the ARO landing-zone bootstrap.
    .DESCRIPTION
    With InputConfigPath, runs noninteractively. Without it, runs a JSON configuration wizard. The selected ARO version is validated and persisted exactly before Terraform is invoked. Secrets are accepted only by Terraform through environment variables and are never printed.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [string]$InputConfigPath,
        [string]$OutputConfigPath,
        [ValidateSet('plan','apply')][string]$BootstrapAction = 'plan',
        [switch]$GenerateConfig,
        [switch]$AutoApprove
    )

    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($OutputConfigPath)) { $OutputConfigPath = Join-Path $repositoryRoot 'config\local.json' }
    $configPath = if ($InputConfigPath) { (Resolve-Path -LiteralPath $InputConfigPath).Path } else { $OutputConfigPath }
    $config = if ($InputConfigPath) { Read-AROConfig $configPath } else { New-AROConfigWizard $configPath }
    Assert-AROConfig $config
    if ($GenerateConfig) { Write-Host "Configuration written to $configPath"; return }

    Invoke-AROPreflight $config
    $config.aro_version = Resolve-AROVersion $config
    $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding utf8NoBOM
    Write-Host "Validated and pinned ARO version $($config.aro_version) in $configPath"

    $bootstrapRoot = Join-Path $repositoryRoot 'bootstrap\alz\github'
    $tfvars = Join-Path $bootstrapRoot 'terraform.tfvars.json'
    New-BootstrapInput -Config $config -RepositoryRoot $repositoryRoot -OutputPath $tfvars
    Push-Location $bootstrapRoot
    try {
        [void](Invoke-NativeCommand terraform @('init','-input=false'))
        [void](Invoke-NativeCommand terraform @('validate','-no-color'))
        $planPath = Join-Path $bootstrapRoot 'bootstrap.tfplan'
        [void](Invoke-NativeCommand terraform @('plan','-input=false','-out', $planPath))
        Write-Host "Bootstrap plan created: $planPath"
        if ($BootstrapAction -eq 'apply') {
            if ($AutoApprove -or $PSCmdlet.ShouldProcess("$($config.github_organization)/$($config.github_repository)", 'Apply exact bootstrap Terraform plan')) {
                [void](Invoke-NativeCommand terraform @('apply','-input=false', $planPath))
                Write-Host 'Bootstrap apply completed. No workload apply was triggered.'
            }
        }
    }
    finally { Pop-Location }
}

Export-ModuleMember -Function Deploy-AROLandingZone
