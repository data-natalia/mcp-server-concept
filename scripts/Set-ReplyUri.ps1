[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$AppId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https://')]
    [string]$ReplyUri
)

$ErrorActionPreference = 'Stop'

function Fail {
    param([string]$Message)

    [ordered]@{
        success = $false
        errorMessage = $Message
    } | ConvertTo-Json -Depth 4 -Compress

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
    $appJson = Invoke-AzTsv "ad app show --id $AppId --query `"{displayName:displayName, redirectUris:web.redirectUris}`" -o json"
    $app = $appJson | ConvertFrom-Json

    if ($null -eq $app -or [string]::IsNullOrWhiteSpace($app.displayName)) {
        throw "App registration '$AppId' not found or access denied."
    }

    $displayName = $app.displayName
    $existingUris = @()
    if ($null -ne $app.redirectUris) {
        $existingUris = @($app.redirectUris)
    }

    if ($existingUris -contains $ReplyUri) {
        [ordered]@{
            success = $true
            status = 'already_exists'
            appId = $AppId
            displayName = $displayName
            replyUri = $ReplyUri
            redirectUris = $existingUris
        } | ConvertTo-Json -Depth 4 -Compress

        exit 0
    }

    $updatedUris = $existingUris + $ReplyUri
    $uriList = ($updatedUris | ForEach-Object { "`"$_`"" }) -join ' '
    $null = Invoke-AzTsv "ad app update --id $AppId --web-redirect-uris $uriList --only-show-errors"

    $verifyJson = Invoke-AzTsv "ad app show --id $AppId --query `"web.redirectUris`" -o json"
    $verifiedUris = @($verifyJson | ConvertFrom-Json)

    [ordered]@{
        success = $true
        status = 'added'
        appId = $AppId
        displayName = $displayName
        replyUri = $ReplyUri
        redirectUris = $verifiedUris
    } | ConvertTo-Json -Depth 4 -Compress
} catch {
    $msg = $_.Exception.Message
    if ([string]::IsNullOrWhiteSpace($msg)) {
        $msg = ($_ | Out-String).Trim()
    }

    Fail $msg
}
