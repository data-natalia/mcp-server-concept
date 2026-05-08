[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]{5,22}$')]
    [string]$DevEnvironmentName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]{5,22}$')]
    [string]$ProdEnvironmentName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]{5,50}$')]
    [string]$AcrName,

    [Parameter(Mandatory = $true)]
    [string]$Location,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$SubscriptionId
)

$ErrorActionPreference = 'Stop'

function Fail {
    param([string]$Message)

    [ordered]@{
        success      = $false
        errorMessage = $Message
    } | ConvertTo-Json -Depth 3 -Compress
    exit 1
}

function Invoke-AzTsv {
    param([string]$CommandArgs)

    $escapedArgs = $CommandArgs -replace '\$', '`$'
    $output = Invoke-Expression ("az " + $escapedArgs) 2>&1
    if ($LASTEXITCODE -ne 0) {
        $detail = ($output | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($detail)) {
            $detail = "az command failed with exit code {0}: az {1}" -f $LASTEXITCODE, $CommandArgs
        }

        throw [System.Exception]::new($detail)
    }

    return ($output | Out-String).Trim()
}

try {
    if ($DevEnvironmentName -eq $ProdEnvironmentName) {
        Fail 'DevEnvironmentName and ProdEnvironmentName must be different.'
    }

    $null = Invoke-AzTsv "account set --subscription $SubscriptionId"

    $repoRoot = Split-Path -Parent $PSScriptRoot

    $devContent = @"
using 'main.bicep'

// Shared registry — keep acrName and acrResourceGroupName identical in prod.bicepparam
param acrName             = '$AcrName'
param acrResourceGroupName = 'rg-$AcrName'

// Dev-environment resources
param containerAppsEnvName = '$DevEnvironmentName'
param keyVaultName        = '$DevEnvironmentName'
param logAnalyticsName    = '$DevEnvironmentName'
param location            = '$Location'
param resourceGroupName   = 'rg-$DevEnvironmentName'
param storageAccountName  = 'st$DevEnvironmentName'
"@

    Set-Content -Path (Join-Path $repoRoot 'Infrastructure' 'dev.bicepparam') -Value $devContent -Encoding utf8

    $prodContent = @"
using 'main.bicep'

// Shared registry — keep acrName and acrResourceGroupName identical to dev.bicepparam
param acrName             = '$AcrName'
param acrResourceGroupName = 'rg-$AcrName'

// Prod-environment resources
param containerAppsEnvName = '$ProdEnvironmentName'
param keyVaultName        = '$ProdEnvironmentName'
param logAnalyticsName    = '$ProdEnvironmentName'
param location            = '$Location'
param resourceGroupName   = 'rg-$ProdEnvironmentName'
param storageAccountName  = 'st$ProdEnvironmentName'
"@

    Set-Content -Path (Join-Path $repoRoot 'Infrastructure' 'prod.bicepparam') -Value $prodContent -Encoding utf8

    [ordered]@{
        success      = $true
        errorMessage = $null
    } | ConvertTo-Json -Depth 3 -Compress
} catch {
    Fail $_.Exception.Message
}
