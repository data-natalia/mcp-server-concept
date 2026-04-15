<#
.SYNOPSIS
    Scaffolds a new MCP Server in this repository.

.DESCRIPTION
    Creates all required files for a new MCP Server by:
    - Copying and processing auth-variant templates from .github/templates/mcp-server/
    - Replacing {{ServerName}}, {{servername}}, {{Port}}, {{ApiConfigSection}} tokens
    - Creating the Infrastructure bicep parameter file
    - Creating the GitHub Actions workflow
    - Creating the Copilot Studio custom connector swagger file
    - Adding the project to MCPConcept.slnx
    - Adding a build task to .vscode/tasks.json
    - Adding a launch configuration to .vscode/launch.json
    - Rolling back all created files on any failure

    All three types protect the MCP server itself with Entra ID JWT Bearer.
    The AuthType controls only how the service calls the downstream API.

.PARAMETER ServerName
    PascalCase name for the new server (e.g. WeatherForecast, PartnerCenter).
    Used for the folder name, namespace, class names, and .csproj file name.

.PARAMETER AuthType
    How the service authenticates against the downstream API:
    - obo     : Entra ID On-Behalf-Of token exchange (e.g. Dynamics CRM, SharePoint)
    - apikey  : Static API key passed in a request header
    - noauth  : Downstream API has no authentication

.PARAMETER Port
    HTTP port the container listens on inside Azure Container Apps.
    Defaults to 4547.

.PARAMETER ApiConfigSection
    Configuration section prefix for the upstream API settings.
    Used when AuthType = apikey or noauth. Ignored for obo.
    Defaults to {ServerName}Api (e.g. WeatherForecastApi).

.EXAMPLE
    .\scripts\New-McpServer.ps1 -ServerName PartnerCenter -AuthType obo

.EXAMPLE
    .\scripts\New-McpServer.ps1 -ServerName Flowcase -AuthType apikey -ApiConfigSection FlowcaseApi

.EXAMPLE
    .\scripts\New-McpServer.ps1 -ServerName WeatherForecast -AuthType noauth -ApiConfigSection WeatherApi
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Z][a-zA-Z0-9]+$')]
    [string]$ServerName,

    [Parameter(Mandatory = $true)]
    [ValidateSet('obo', 'apikey', 'noauth')]
    [string]$AuthType,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 65535)]
    [int]$Port = 4547,

    [Parameter(Mandatory = $false)]
    [string]$ApiConfigSection = ''
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Derived values
# ---------------------------------------------------------------------------
$serverNameLower    = $ServerName.ToLower()
$repoRoot           = Split-Path -Parent $PSScriptRoot
$templateDir        = Join-Path $repoRoot '.github' 'templates' 'mcp-server'

# ApiConfigSection is only meaningful for apikey and noauth types
if ($AuthType -eq 'obo') {
    $ApiConfigSection = ''
} elseif ($ApiConfigSection -eq '' -or $ApiConfigSection -eq $null) {
    $ApiConfigSection = "${ServerName}Api"
}

# ---------------------------------------------------------------------------
# Target paths (collected for rollback)
# ---------------------------------------------------------------------------
$serverFolder       = Join-Path $repoRoot 'MCPServers'       $ServerName
$bicepParamFile     = Join-Path $repoRoot 'Infrastructure'   "containerApp-${ServerName}.bicepparam"
$workflowFile       = Join-Path $repoRoot '.github'          'workflows' "docker-publish-${serverNameLower}.yml"
$swaggerFile        = Join-Path $repoRoot 'Copilot'          'CustomConnectors' "${ServerName}.swagger.json"
$slnxFile           = Join-Path $repoRoot 'MCPConcept.slnx'
$tasksJsonPath      = Join-Path $repoRoot '.vscode'          'tasks.json'
$launchJsonPath     = Join-Path $repoRoot '.vscode'          'launch.json'

# Track what we create so we can roll back cleanly
$createdFiles       = [System.Collections.Generic.List[string]]::new()
$createdDirectories = [System.Collections.Generic.List[string]]::new()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Replace-Tokens {
    param([string]$Content)
    $Content = $Content -creplace '\{\{ServerName\}\}',       $ServerName
    $Content = $Content -creplace '\{\{servername\}\}',       $serverNameLower
    $Content = $Content -creplace '\{\{SERVERNAME\}\}',       $ServerName.ToUpper()
    $Content = $Content -creplace '\{\{Port\}\}',             $Port
    $Content = $Content -creplace '\{\{ApiConfigSection\}\}', $ApiConfigSection
    return $Content
}

function Write-TemplateFile {
    param(
        [string]$TemplateName,
        [string]$DestinationPath
    )
    $templatePath = Join-Path $templateDir $TemplateName
    if (-not (Test-Path $templatePath)) {
        throw "Template not found: $templatePath"
    }
    $content = Get-Content -Path $templatePath -Raw -Encoding UTF8
    $content = Replace-Tokens -Content $content

    $destDir = Split-Path -Parent $DestinationPath
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        $createdDirectories.Add($destDir)
    }

    Set-Content -Path $DestinationPath -Value $content -NoNewline -Encoding UTF8
    $createdFiles.Add($DestinationPath)
    Write-Host "   + $($DestinationPath.Substring($repoRoot.Length + 1))" -ForegroundColor Green
}

function Rollback {
    Write-Host ''
    Write-Host 'Rolling back created files...' -ForegroundColor Yellow
    foreach ($f in $createdFiles) {
        if (Test-Path $f) { Remove-Item -Path $f -Force }
    }
    foreach ($d in ($createdDirectories | Sort-Object -Descending)) {
        if (Test-Path $d) {
            $remaining = Get-ChildItem -Path $d -Recurse -Force -ErrorAction SilentlyContinue
            if (-not $remaining) { Remove-Item -Path $d -Force }
        }
    }
    Write-Host 'Rollback complete.' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Pre-flight validation
# ---------------------------------------------------------------------------
Write-Host ''
$authDescription = switch ($AuthType) {
    'obo'    { 'Entra ID OBO token exchange (downstream API uses delegated user token)' }
    'apikey' { 'Entra ID (MCP) + API key (downstream API)' }
    'noauth' { 'Entra ID (MCP) + no auth on downstream API' }
}
Write-Host "Scaffolding MCP Server: $ServerName" -ForegroundColor Cyan
Write-Host "  Auth type  : $AuthType — $authDescription" -ForegroundColor Gray
Write-Host "  Port       : $Port" -ForegroundColor Gray
if ($AuthType -ne 'obo') {
    Write-Host "  Config sec : $ApiConfigSection" -ForegroundColor Gray
}
Write-Host ''

if (Test-Path $serverFolder) {
    Write-Error "Server folder already exists: $serverFolder"
    exit 1
}
if (Test-Path $bicepParamFile) {
    Write-Error "Bicep parameter file already exists: $bicepParamFile"
    exit 1
}
if (Test-Path $workflowFile) {
    Write-Error "Workflow file already exists: $workflowFile"
    exit 1
}
if (Test-Path $swaggerFile) {
    Write-Error "Custom connector file already exists: $swaggerFile"
    exit 1
}
if (-not (Test-Path (Join-Path $repoRoot 'MCPServers' 'Shared' 'Shared.csproj'))) {
    Write-Error "Shared project not found. Ensure MCPServers/Shared/Shared.csproj exists."
    exit 1
}
if (-not (Test-Path $slnxFile)) {
    Write-Error "Solution file not found: $slnxFile"
    exit 1
}
if (-not (Test-Path $templateDir)) {
    Write-Error "Template directory not found: $templateDir"
    exit 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
try {

    # --- C# project files ---
    Write-Host 'Creating C# project files...' -ForegroundColor Yellow
    Write-TemplateFile 'Server.csproj'                  (Join-Path $serverFolder "${ServerName}.csproj")
    Write-TemplateFile 'appsettings.Development.json'   (Join-Path $serverFolder 'appsettings.Development.json')
    Write-TemplateFile 'Dockerfile'                     (Join-Path $serverFolder 'Dockerfile')
    Write-TemplateFile 'Tool.cs'                        (Join-Path $serverFolder 'Tools'    "${ServerName}Tool.cs")

    switch ($AuthType) {
        'obo' {
            Write-TemplateFile 'Program.Obo.cs'         (Join-Path $serverFolder 'Program.cs')
            Write-TemplateFile 'Service.Obo.cs'         (Join-Path $serverFolder 'Services' "${ServerName}Service.cs")
            Write-TemplateFile 'appsettings.Obo.json'   (Join-Path $serverFolder 'appsettings.json')
        }
        'apikey' {
            Write-TemplateFile 'Program.ApiKey.cs'      (Join-Path $serverFolder 'Program.cs')
            Write-TemplateFile 'Service.ApiKey.cs'      (Join-Path $serverFolder 'Services' "${ServerName}Service.cs")
            Write-TemplateFile 'appsettings.ApiKey.json'(Join-Path $serverFolder 'appsettings.json')
        }
        'noauth' {
            Write-TemplateFile 'Program.NoAuth.cs'      (Join-Path $serverFolder 'Program.cs')
            Write-TemplateFile 'Service.NoAuth.cs'      (Join-Path $serverFolder 'Services' "${ServerName}Service.cs")
            Write-TemplateFile 'appsettings.NoAuth.json'(Join-Path $serverFolder 'appsettings.json')
        }
    }

    # --- Infrastructure ---
    Write-Host ''
    Write-Host 'Creating infrastructure file...' -ForegroundColor Yellow
    switch ($AuthType) {
        'obo'    { Write-TemplateFile 'bicepparam.Obo.bicepparam'    $bicepParamFile }
        'apikey' { Write-TemplateFile 'bicepparam.ApiKey.bicepparam' $bicepParamFile }
        'noauth' { Write-TemplateFile 'bicepparam.NoAuth.bicepparam' $bicepParamFile }
    }

    # --- CI/CD workflow ---
    Write-Host ''
    Write-Host 'Creating GitHub Actions workflow...' -ForegroundColor Yellow
    Write-TemplateFile 'workflow.yml' $workflowFile

    # --- Copilot custom connector ---
    Write-Host ''
    Write-Host 'Creating Copilot custom connector...' -ForegroundColor Yellow
    Write-TemplateFile 'swagger.json' $swaggerFile

    # --- Add to solution ---
    Write-Host ''
    Write-Host 'Adding project to solution...' -ForegroundColor Yellow
    $csprojRelative = "MCPServers/$ServerName/${ServerName}.csproj"
    $result = dotnet sln $slnxFile add $csprojRelative 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet sln add failed: $result"
    }
    Write-Host "   + $csprojRelative added to MCPConcept.slnx" -ForegroundColor Green

    # --- Update .vscode/tasks.json ---
    Write-Host ''
    Write-Host 'Updating .vscode/tasks.json...' -ForegroundColor Yellow
    $tasksJson = Get-Content -Path $tasksJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $newTask = [PSCustomObject]@{
        label          = "build $ServerName"
        command        = 'dotnet'
        type           = 'process'
        args           = @(
            'build',
            "`${workspaceFolder}/MCPServers/$ServerName/${ServerName}.csproj"
        )
        problemMatcher = '$msCompile'
    }
    $tasksJson.tasks += $newTask
    $tasksJson | ConvertTo-Json -Depth 10 | Set-Content -Path $tasksJsonPath -Encoding UTF8
    Write-Host "   + build $ServerName task added" -ForegroundColor Green

    # --- Update .vscode/launch.json ---
    Write-Host ''
    Write-Host 'Updating .vscode/launch.json...' -ForegroundColor Yellow
    $launchJson = Get-Content -Path $launchJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $newConfig = [PSCustomObject]@{
        name           = $ServerName
        type           = 'dotnet'
        request        = 'launch'
        projectPath    = "`${workspaceFolder}/MCPServers/$ServerName/${ServerName}.csproj"
        env            = [PSCustomObject]@{ ASPNETCORE_ENVIRONMENT = 'Development' }
        preLaunchTask  = "build $ServerName"
    }
    $launchJson.configurations += $newConfig
    $launchJson | ConvertTo-Json -Depth 10 | Set-Content -Path $launchJsonPath -Encoding UTF8
    Write-Host "   + $ServerName launch configuration added" -ForegroundColor Green

    # --- Done ---
    Write-Host ''
    Write-Host "MCP Server '$ServerName' created successfully." -ForegroundColor Green
    Write-Host ''
    Write-Host 'Files created:' -ForegroundColor Cyan
    foreach ($f in $createdFiles) {
        Write-Host "  $($f.Substring($repoRoot.Length + 1))"
    }
    Write-Host ''
    Write-Host 'Next steps:' -ForegroundColor Cyan
    Write-Host "  1. Fill in the TODO values in Infrastructure/containerApp-${ServerName}.bicepparam"
    switch ($AuthType) {
        'obo' {
            Write-Host "  2. Create Key Vault secrets: ${serverNameLower}clientid, ${serverNameLower}clientsecret, ${serverNameLower}tenantid"
            Write-Host "  3. Configure the Entra ID app registration (expose api://<clientId>/mcp.tools scope)"
            Write-Host "  4. Fill in DownstreamApi__Scope (OBO scope ending in /.default) and DownstreamApi__BaseUrl in the bicepparam"
            Write-Host "  5. Implement your business logic in MCPServers/$ServerName/Services/${ServerName}Service.cs"
            Write-Host "  6. Implement your tool methods in MCPServers/$ServerName/Tools/${ServerName}Tool.cs"
            Write-Host "  7. Fill in dev credentials in MCPServers/$ServerName/appsettings.Development.json"
            Write-Host "  8. Test locally: F5 in VS Code and select '$ServerName', or: cd MCPServers/$ServerName && dotnet run"
            Write-Host "  9. Deploy: commit and push to trigger .github/workflows/docker-publish-${serverNameLower}.yml"
            Write-Host " 10. After first deploy, update EntraIdAuth__PublicUrl in the bicepparam and the swagger.json server URL"
        }
        'apikey' {
            Write-Host "  2. Create Key Vault secrets: ${serverNameLower}apikey, ${serverNameLower}clientid, ${serverNameLower}clientsecret, ${serverNameLower}tenantid"
            Write-Host "  3. Configure the Entra ID app registration (expose api://<clientId>/mcp.tools scope)"
            Write-Host "  4. Implement your business logic in MCPServers/$ServerName/Services/${ServerName}Service.cs"
            Write-Host "  5. Implement your tool methods in MCPServers/$ServerName/Tools/${ServerName}Tool.cs"
            Write-Host "  6. Fill in dev credentials in MCPServers/$ServerName/appsettings.Development.json"
            Write-Host "  7. Test locally: F5 in VS Code and select '$ServerName', or: cd MCPServers/$ServerName && dotnet run"
            Write-Host "  8. Deploy: commit and push to trigger .github/workflows/docker-publish-${serverNameLower}.yml"
            Write-Host "  9. After first deploy, update EntraIdAuth__PublicUrl in the bicepparam and the swagger.json server URL"
        }
        'noauth' {
            Write-Host "  2. Create Key Vault secrets: ${serverNameLower}clientid, ${serverNameLower}clientsecret, ${serverNameLower}tenantid"
            Write-Host "  3. Configure the Entra ID app registration (expose api://<clientId>/mcp.tools scope)"
            Write-Host "  4. Set the upstream API base URL (${ApiConfigSection}__BaseUrl) in the bicepparam environment section"
            Write-Host "  5. Implement your business logic in MCPServers/$ServerName/Services/${ServerName}Service.cs"
            Write-Host "  6. Implement your tool methods in MCPServers/$ServerName/Tools/${ServerName}Tool.cs"
            Write-Host "  7. Fill in dev credentials in MCPServers/$ServerName/appsettings.Development.json"
            Write-Host "  8. Test locally: F5 in VS Code and select '$ServerName', or: cd MCPServers/$ServerName && dotnet run"
            Write-Host "  9. Deploy: commit and push to trigger .github/workflows/docker-publish-${serverNameLower}.yml"
            Write-Host " 10. After first deploy, update EntraIdAuth__PublicUrl in the bicepparam and the swagger.json server URL"
        }
    }
    Write-Host ''

} catch {
    Write-Host ''
    Write-Host "ERROR: $_" -ForegroundColor Red
    Rollback
    exit 1
}
