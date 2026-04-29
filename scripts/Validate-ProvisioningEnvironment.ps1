[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Fail {
    param([string]$Message)

    $result = [ordered]@{
        success = $false
        errorMessage = $Message
        currentSubscriptionName = $null
        currentSubscriptionId = $null
        directoryRoleNames = @()
        availableKeyVaults = @()
        suggestedEnvironmentName = ''
    }

    $result | ConvertTo-Json -Depth 5 -Compress
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
    try {
        $null = Invoke-AzTsv 'version'
    } catch {
        Fail 'Azure CLI not found. Install Azure CLI first: https://learn.microsoft.com/cli/azure/install-azure-cli'
    }

    $currentSubscriptionName = Invoke-AzTsv 'account show --query "name" -o tsv'
    if ([string]::IsNullOrWhiteSpace($currentSubscriptionName)) {
        Fail 'No active Azure login found. Run az login first.'
    }

    $subscriptionPair = Invoke-AzTsv 'account show --query "[name, id]" -o tsv'
    $parts = $subscriptionPair -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($parts.Count -lt 2) {
        Fail 'Could not determine current subscription name/id from az account show.'
    }

    $currentSubscriptionName = $parts[0].Trim()
    $currentSubscriptionId = $parts[1].Trim()

    $rolesRaw = Invoke-AzTsv 'rest --method GET --url "https://graph.microsoft.com/v1.0/me/transitiveMemberOf/microsoft.graph.directoryRole?$select=displayName" --query "value[].displayName" -o tsv'
    $directoryRoleNames = @()
    if (-not [string]::IsNullOrWhiteSpace($rolesRaw)) {
        $directoryRoleNames = $rolesRaw -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() }
    }

    $requiredRoles = @('Application Developer', 'Application Administrator', 'Global Administrator')
    $hasRequiredRole = $false
    foreach ($role in $requiredRoles) {
        if ($directoryRoleNames -contains $role) {
            $hasRequiredRole = $true
            break
        }
    }

    if (-not $hasRequiredRole) {
        Fail 'You do not have Application Developer, Application Administrator, or Global Administrator role in Entra ID. Contact your Azure AD administrator.'
    }

    $keyVaultsRaw = Invoke-AzTsv 'keyvault list --query "[].name" -o tsv'
    $availableKeyVaults = @()
    if (-not [string]::IsNullOrWhiteSpace($keyVaultsRaw)) {
        $availableKeyVaults = $keyVaultsRaw -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() }
    }

    if ($availableKeyVaults.Count -eq 0) {
        Fail "No Key Vaults found in subscription $currentSubscriptionId. Run /setup-deployment first."
    }

    $suggestedEnvironmentName = ''
    $bicepParamPath = Join-Path (Get-Location) 'Infrastructure/dev.bicepparam'
    if (Test-Path $bicepParamPath) {
        $line = Select-String -Path $bicepParamPath -Pattern 'containerAppsEnvName' | Select-Object -First 1
        if ($null -ne $line -and $line.Line -match "'([^']+)'") {
            $suggestedEnvironmentName = $matches[1]
        }
    }

    [ordered]@{
        success = $true
        currentSubscriptionName = $currentSubscriptionName
        currentSubscriptionId = $currentSubscriptionId
        directoryRoleNames = $directoryRoleNames
        availableKeyVaults = $availableKeyVaults
        suggestedEnvironmentName = $suggestedEnvironmentName
    } | ConvertTo-Json -Depth 5 -Compress
} catch {
    Fail $_.Exception.Message
}
