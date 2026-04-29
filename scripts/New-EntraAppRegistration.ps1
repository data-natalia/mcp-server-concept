[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9]+$')]
    [string]$ServerName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9-]{3,24}$')]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [ValidateSet('mcp', 'agent')]
    [string]$AccountType = 'mcp',

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$McpAppId
)

$ErrorActionPreference = 'Stop'

function Fail {
    param([string]$Message)

    [ordered]@{
        success = $false
        errorMessage = $Message
    } | ConvertTo-Json -Depth 6 -Compress

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

function Ensure-OAuth2PermissionGrant {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $true)]
        [string]$ClientSpId,

        [Parameter(Mandatory = $true)]
        [string]$ResourceSpId,

        [Parameter(Mandatory = $true)]
        [string]$Scope
    )

    $existing = (Invoke-RestMethod -Method Get -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$ClientSpId/oauth2PermissionGrants" -Headers $Headers).value
    $grantExists = $existing | Where-Object { $_.resourceId -eq $ResourceSpId }

    if ($grantExists) {
        $grantBody = @{ scope = $Scope } | ConvertTo-Json -Compress
        Invoke-RestMethod -Method Patch -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$($grantExists.id)" -Headers $Headers -Body $grantBody | Out-Null
        return 'updated'
    }

    $grantBody = @{ clientId = $ClientSpId; consentType = 'AllPrincipals'; resourceId = $ResourceSpId; scope = $Scope } | ConvertTo-Json -Compress
    Invoke-RestMethod -Method Post -Uri 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants' -Headers $Headers -Body $grantBody | Out-Null
    return 'created'
}

function Ensure-KeyVaultSecretsOfficerRole {
    param(
        [Parameter(Mandatory = $true)]
        [string]$KeyVaultId
    )

    $requiredRoles = @('Key Vault Secrets Officer', 'Key Vault Administrator')
    
    $roleAssignments = Invoke-AzTsv "role assignment list --scope `"$KeyVaultId`" --query `"[].roleDefinitionName`" -o tsv"
    
    foreach ($role in $requiredRoles) {
        if ($roleAssignments -contains $role) {
            return $true
        }
    }
    
    # User doesn't have the required role, assign it
    Write-Host "User does not have Key Vault Secrets Officer role. Assigning now..."
    
    $currentUser = Invoke-AzTsv "ad signed-in-user show --query id -o tsv"
    if ([string]::IsNullOrWhiteSpace($currentUser)) {
        throw "Unable to determine current user identity. Cannot assign Key Vault Secrets Officer role."
    }
    
    try {
        $null = Invoke-AzTsv "role assignment create --role `"Key Vault Secrets Officer`" --assignee-object-id `"$currentUser`" --scope `"$KeyVaultId`""
        Write-Host "Successfully assigned Key Vault Secrets Officer role to current user."
        return $true
    } catch {
        throw "Failed to assign Key Vault Secrets Officer role: $_"
    }
}

try {
    if ($AccountType -eq 'agent' -and [string]::IsNullOrWhiteSpace($McpAppId)) {
        throw 'McpAppId is required when AccountType is agent.'
    }

    $namePrefix = if ($AccountType -eq 'agent') { 'agent' } else { 'mcp' }
    $appDisplayName = "$namePrefix-$ServerName"

    $null = Invoke-AzTsv "account set --subscription $SubscriptionId"

    $kvId = Invoke-AzTsv "keyvault show --name $KeyVaultName --subscription $SubscriptionId --query id -o tsv"
    if ([string]::IsNullOrWhiteSpace($kvId)) {
        throw "Key Vault '$KeyVaultName' not found in sbsucription $SubscriptionId or access denied."
    }

    Ensure-KeyVaultSecretsOfficerRole -KeyVaultId $kvId

    $appId = Invoke-AzTsv "ad app list --filter `"displayName eq '$appDisplayName'`" --query `"[0].appId`" -o tsv"
    $appExists = -not [string]::IsNullOrWhiteSpace($appId)

    if (-not $appExists) {
        $appId = Invoke-AzTsv "ad app create --display-name `"$appDisplayName`" --sign-in-audience AzureADMyOrg --query appId -o tsv"
        if ([string]::IsNullOrWhiteSpace($appId)) {
            throw "Failed to create app registration $appDisplayName"
        }
        $appStatus = 'created'
    } else {
        $appStatus = 'updated'
    }

    $servicePrincipalId = $null
    try {
        $servicePrincipalId = Invoke-AzTsv "ad sp show --id $appId --query id -o tsv"
    } catch {
        $servicePrincipalId = $null
    }

    if ([string]::IsNullOrWhiteSpace($servicePrincipalId)) {
        $servicePrincipalId = Invoke-AzTsv "ad sp create --id $appId --query id -o tsv"
        $spStatus = 'created'
    } else {
        $spStatus = 'existing'
    }

    $appObjectId = Invoke-AzTsv "ad app show --id $appId --query id -o tsv"
    $token = Invoke-AzTsv 'account get-access-token --resource-type ms-graph --query accessToken -o tsv'
    $headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

    $bodyObj = @{
        description = "Manages authentication to the $ServerName MCP Server"
    }

    if ($AccountType -eq 'mcp') {
        $bodyObj.identifierUris = @("api://$appId")
        $bodyObj.api = @{
            oauth2PermissionScopes = @(
                @{
                    id = '00000000-0000-0000-0000-000000000001'
                    isEnabled = $true
                    type = 'User'
                    userConsentDisplayName = "Grants access to $ServerName on behalf of user"
                    userConsentDescription = "Grants access to $ServerName on behalf of user"
                    value = 'mcp.tools'
                    adminConsentDisplayName = "Grants access to $ServerName on behalf of user"
                    adminConsentDescription = "Grants access to $ServerName on behalf of user"
                }
            )
        }
    }

    $body = $bodyObj | ConvertTo-Json -Depth 10 -Compress
    Invoke-RestMethod -Method Patch -Uri "https://graph.microsoft.com/v1.0/applications/$appObjectId" -Headers $headers -Body $body | Out-Null

    $requiredResourceAccess = @()
    
    # Both MCP and agent accounts need Graph permissions
    $requiredResourceAccess += @{
        resourceAppId = '00000003-0000-0000-c000-000000000000'
        resourceAccess = @(
            @{ id = 'e1fe6dd8-ba31-4d61-89e7-88639da4683d'; type = 'Scope' }
            @{ id = '7427e0e9-2fba-42fe-b0c0-848c9e6a8182'; type = 'Scope' }
            @{ id = '14dad69e-099b-42c9-810b-d002981feec1'; type = 'Scope' }
        )
    }
    
    # Agent accounts additionally need MCP scope
    if ($AccountType -eq 'agent') {
        $requiredResourceAccess += @{
            resourceAppId = $McpAppId
            resourceAccess = @(
                @{ id = '00000000-0000-0000-0000-000000000001'; type = 'Scope' }
            )
        }
    }

    $permBody = @{ requiredResourceAccess = [array]$requiredResourceAccess } | ConvertTo-Json -Depth 10 -Compress
    Invoke-RestMethod -Method Patch -Uri "https://graph.microsoft.com/v1.0/applications/$appObjectId" -Headers $headers -Body $permBody | Out-Null

    $spId = $servicePrincipalId
    $graphGrantStatus = $null
    $mcpGrantStatus = $null

    # Both MCP and agent accounts get Graph permissions
    $graphSpId = (Invoke-RestMethod -Method Get -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '00000003-0000-0000-c000-000000000000'&`$select=id" -Headers $headers).value[0].id
    $graphGrantStatus = Ensure-OAuth2PermissionGrant -Headers $headers -ClientSpId $spId -ResourceSpId $graphSpId -Scope 'User.Read offline_access profile'

    if ($AccountType -eq 'agent') {
        $mcpResourceSpId = $null
        try {
            $mcpResourceSpId = Invoke-AzTsv "ad sp show --id $McpAppId --query id -o tsv"
        } catch {
            $mcpResourceSpId = $null
        }

        if ([string]::IsNullOrWhiteSpace($mcpResourceSpId)) {
            $mcpResourceSpId = Invoke-AzTsv "ad sp create --id $McpAppId --query id -o tsv"
        }

        $mcpGrantStatus = Ensure-OAuth2PermissionGrant -Headers $headers -ClientSpId $spId -ResourceSpId $mcpResourceSpId -Scope 'mcp.tools'
    }

    $SECRET_VALUE = Invoke-AzTsv "ad app credential reset --id $appId --append --display-name `"$appDisplayName`" --years 10 --query password -o tsv"
    if ([string]::IsNullOrWhiteSpace($SECRET_VALUE)) {
        throw "Failed to create client secret for appId $appId"
    }

    $tenantId = Invoke-AzTsv 'account show --query tenantId -o tsv'
    $resourceGroupName = Invoke-AzTsv "keyvault show --name $KeyVaultName --query resourceGroup -o tsv"

    $jsonSecretValue = @{ ApplicationId = $appId; ClientSecret = $SECRET_VALUE; TenantId = $tenantId } | ConvertTo-Json -Compress

    if ($AccountType -eq 'mcp') {
        $null = Invoke-AzTsv "keyvault secret set --vault-name $KeyVaultName --name `"mcp-$ServerName`" --value '$jsonSecretValue' --only-show-errors"
        $null = Invoke-AzTsv "keyvault secret set --vault-name $KeyVaultName --name `"$($ServerName)ClientId`" --value `"$appId`" --only-show-errors"
        $null = Invoke-AzTsv "keyvault secret set --vault-name $KeyVaultName --name `"$($ServerName)ClientSecret`" --value `"$SECRET_VALUE`" --only-show-errors"
        $null = Invoke-AzTsv "keyvault secret set --vault-name $KeyVaultName --name `"$($ServerName)TenantId`" --value `"$tenantId`" --only-show-errors"
    } else {
        $null = Invoke-AzTsv "keyvault secret set --vault-name $KeyVaultName --name `"agent-$ServerName`" --value '$jsonSecretValue' --only-show-errors"
    }

    $result = [ordered]@{
        success = $true
        accountType = $AccountType
        serverName = $ServerName
        keyVaultName = $KeyVaultName
        subscriptionId = $SubscriptionId
        appId = $appId
        tenantId = $tenantId
        resourceGroupName = $resourceGroupName
        appStatus = $appStatus
        servicePrincipalStatus = $spStatus
        graphGrantStatus = $graphGrantStatus
    }

    if ($AccountType -eq 'mcp') {
        $result.secrets = @(
            "mcp-$ServerName",
            "$($ServerName)ClientId",
            "$($ServerName)ClientSecret",
            "$($ServerName)TenantId"
        )
        $result.grantStatus = $graphGrantStatus
    } else {
        $result.mcpAppId = $McpAppId
        $result.agentAppId = $appId
        $result.mcpGrantStatus = $mcpGrantStatus
        $result.keyVaultSecretName = "agent-$ServerName"
    }

    $result | ConvertTo-Json -Depth 6 -Compress
} catch {
    $msg = $_.Exception.Message
    if ([string]::IsNullOrWhiteSpace($msg)) {
        $msg = ($_ | Out-String).Trim()
    }

    Fail $msg
}
