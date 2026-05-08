[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]{5,50}$')]
    [string]$AcrName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$SubscriptionId
)

$ErrorActionPreference = 'Stop'

$spName = "sp-mcp-$AcrName"

function Fail {
    param([string]$Message)

    [ordered]@{
        success      = $false
        errorMessage = $Message
        spName       = $spName
        roleAssigned = $false
    } | ConvertTo-Json -Depth 3 -Compress
    exit 1
}

# Array-based invocation avoids quoting/escaping issues for complex arguments.
# Stderr is merged via 2>&1 so we can capture it, but PowerShell surfaces stderr
# lines as ErrorRecord objects — we split them out so warnings never contaminate
# stdout (e.g. the JSON returned by az ad sp create-for-rbac).
function Invoke-Az {
    param([string[]]$Cmd)

    $merged     = & az @Cmd 2>&1
    $stdoutLines = $merged | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }
    $stderrLines = $merged | Where-Object { $_ -is  [System.Management.Automation.ErrorRecord] }

    if ($LASTEXITCODE -ne 0) {
        $detail = ($stderrLines | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($detail)) {
            $detail = ($merged | Out-String).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($detail)) {
            $detail = "az exited with code $LASTEXITCODE"
        }

        throw [System.Exception]::new($detail)
    }

    return ($stdoutLines | Out-String).Trim()
}

$spJson  = $null
$spObj   = $null
$resetObj = $null

try {
    # --- Idempotent service principal ---
    $existingAppId = Invoke-Az @('ad', 'sp', 'list', '--filter', "displayName eq '$spName'", '--query', '[0].appId', '-o', 'tsv')

    if ([string]::IsNullOrWhiteSpace($existingAppId) -or $existingAppId -eq 'null') {
        # No existing SP — create and get credentials in azure/login format
        $spJson  = Invoke-Az @('ad', 'sp', 'create-for-rbac', '--name', $spName, '--json-auth', '--output', 'json')
        $spObj   = $spJson | ConvertFrom-Json
        $clientId = $spObj.clientId
    } else {
        # Existing SP — reset credentials and reconstruct JSON for azure/login
        $resetRaw = Invoke-Az @('ad', 'sp', 'credential', 'reset', '--id', $existingAppId, '--output', 'json')
        $resetObj = $resetRaw | ConvertFrom-Json
        $clientId = $resetObj.appId
        $spJson   = [ordered]@{
            clientId       = $resetObj.appId
            clientSecret   = $resetObj.password
            subscriptionId = $SubscriptionId
            tenantId       = $resetObj.tenant
        } | ConvertTo-Json -Compress
    }

    # --- Idempotent Owner role assignment ---
    $roleAssigned  = $false
    $existingRole  = Invoke-Az @('role', 'assignment', 'list', '--assignee', $clientId, '--role', 'Owner', '--scope', "/subscriptions/$SubscriptionId", '--query', '[0].id', '-o', 'tsv')

    if ([string]::IsNullOrWhiteSpace($existingRole) -or $existingRole -eq 'null') {
        $null = Invoke-Az @('role', 'assignment', 'create', '--assignee', $clientId, '--role', 'Owner', '--scope', "/subscriptions/$SubscriptionId")
        $roleAssigned = $true
    }

    # --- Store credentials in GitHub (pipe directly — never write to disk or print) ---
    $spJson | & gh secret set AZURE_CREDENTIALS --app actions
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to set AZURE_CREDENTIALS secret via gh CLI.'
    }

    & gh variable set ACR_NAME --body $AcrName
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to set ACR_NAME variable via gh CLI.'
    }

    # Clear credentials from memory
    $spJson   = $null
    $spObj    = $null
    $resetObj = $null

    [ordered]@{
        success      = $true
        errorMessage = $null
        spName       = $spName
        roleAssigned = $roleAssigned
    } | ConvertTo-Json -Depth 3 -Compress
} catch {
    $spJson   = $null
    $spObj    = $null
    $resetObj = $null
    Fail $_.Exception.Message
}
