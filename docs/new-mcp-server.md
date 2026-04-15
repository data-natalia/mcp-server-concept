# New MCP Server

This guide explains what the `/new-mcp-server` Copilot agent command does and walks through everything you need to do after running it.

---

## What it does

`/new-mcp-server` scaffolds a complete, deployable MCP server from templates. In one command it:

- Generates all C# project files (Program, Service, Tool, csproj, appsettings)
- Creates the infrastructure parameter file wired to `Infrastructure/containerApp.bicep`
- Generates the GitHub Actions workflow that builds and deploys the server
- Generates the Copilot Custom Connector definition
- Registers the project in the solution (`.slnx`)
- Adds a build task and launch config to `.vscode/`

---

## Inputs

### ServerName

PascalCase name for the server. Used as the folder name, namespace, class prefix, `.csproj` name, and workflow file name.

| Input | Generates |
|---|---|
| `WeatherForecast` | `MCPServers/WeatherForecast/`, namespace `WeatherForecast`, class `WeatherForecastService`, etc. |

Rules: PascalCase, no spaces or special characters. Examples: `PartnerCenter`, `Dynamics365`, `PowerBIReports`.

### AuthType

Determines how the server calls its upstream API. The server **always** verifies the caller's Entra ID JWT regardless of this choice — AuthType only affects outbound calls.

| AuthType | Choose when … |
|---|---|
| **`obo`** | The upstream API requires a user-delegated Entra ID token — e.g. Dynamics 365, Power BI, Microsoft Graph. The server performs an OAuth 2.0 On-Behalf-Of (OBO) exchange so the upstream API sees the signed-in user's identity. |
| **`apikey`** | The upstream API authenticates with a static key sent as a request header. |
| **`noauth`** | The upstream API has no authentication (open or internal API). |

### ApiConfigSection *(apikey and noauth only)*

The configuration section name used in `appsettings.json` for the upstream API settings (`BaseUrl`, and `ApiKey` for apikey mode). Leave blank to auto-derive as `{ServerName}Api` (e.g. `WeatherForecastApi`). Ignored for `obo`.

### Port

Container-internal HTTP port. Leave blank to use the default `4547`. Only change this if you are running multiple servers locally at the same time.

---

## Generated files

The agent reads each template from `.github/templates/mcp-server/` and writes a substituted copy. All `{{ServerName}}`, `{{servername}}` (lowercase), `{{Port}}`, and `{{ApiConfigSection}}` placeholders are replaced.

### C# project — both auth types

| File | Purpose |
|---|---|
| `MCPServers/{ServerName}/{ServerName}.csproj` | Project file referencing `MCPServers/Shared/Shared.csproj` |
| `MCPServers/{ServerName}/Program.cs` | App entry point: configures auth, OpenTelemetry, MCP server, and HTTP transport |
| `MCPServers/{ServerName}/Tools/{ServerName}Tool.cs` | MCP tool class — defines the tool methods exposed to Copilot |
| `MCPServers/{ServerName}/Services/{ServerName}Service.cs` | Service class — implements calls to the upstream API |
| `MCPServers/{ServerName}/appsettings.json` | Production configuration skeleton |
| `MCPServers/{ServerName}/appsettings.Development.json` | Local development overrides (stateless: false, debug logging) |
| `MCPServers/{ServerName}/Dockerfile` | Multi-stage Docker build using the `MCPServers/` folder as context |

### Infrastructure

| File | Purpose |
|---|---|
| `Infrastructure/containerApp-{ServerName}.bicepparam` | Parameters file for `Infrastructure/containerApp.bicep` — fill in the `TODO` values before first deploy |

### CI/CD

| File | Purpose |
|---|---|
| `.github/workflows/docker-publish-{servername}.yml` | Per-server workflow: triggers on path changes to `MCPServers/{ServerName}/`, builds and pushes the Docker image to ACR, then deploys the Container App via Bicep |

### Copilot Custom Connector

| File | Purpose |
|---|---|
| `Copilot/CustomConnectors/{ServerName}.swagger.json` | OpenAPI definition for registering the server as a Copilot Studio custom connector |

### VS Code

| Change | Purpose |
|---|---|
| Task added to `.vscode/tasks.json` | `build {ServerName}` build task |
| Config added to `.vscode/launch.json` | `{ServerName}` launch config with `ASPNETCORE_ENVIRONMENT=Development` |

---

## Post-scaffold steps

### 1. Fill in bicepparam TODOs

Open `Infrastructure/containerApp-{ServerName}.bicepparam` and replace every `TODO` value:

| Parameter | Description |
|---|---|
| `environmentName` | The short environment name from `/setup-deployment` (e.g. `mymcpenv`) |
| `resourceGroupName` | The resource group from `/setup-deployment` (e.g. `rg-mymcpenv`) |
| `EntraIdAuth__PublicUrl` | Leave as `TODO` for now — fill in after the first successful deploy |
| **apikey only:** `EntraIdAuth__TenantId` | Your Entra ID tenant ID (obo and noauth read this from Key Vault instead) |
| **apikey / noauth:** `{ApiConfigSection}__BaseUrl` | Base URL of the upstream API |
| **obo only:** `DownstreamApi__Scope` | OBO scope for the downstream Entra ID-protected API — must end in `/.default` (e.g. `https://org.crm4.dynamics.com/.default`, `https://analysis.windows.net/powerbi/api/.default`) |
| **obo only:** `DownstreamApi__BaseUrl` | Base URL of the downstream API (e.g. `https://org.crm4.dynamics.com/api/data/v9.2`, `https://api.powerbi.com/v1.0/myorg`) |

### 2. Create Key Vault secrets

Secrets are read by the Container App via the User-Assigned Managed Identity. Create them in the Key Vault provisioned by `/setup-deployment`:

```
az keyvault secret set --vault-name {EnvironmentName} --name {SecretName} --value {SecretValue}
```

#### apikey

| Key Vault secret name | Description |
|---|---|
| `{ServerName}ApiKey` | The API key for the upstream API |
| `{ServerName}ClientId` | Client ID of the Entra ID app registration for this MCP server |
| `{ServerName}ClientSecret` | Client secret of the Entra ID app registration |

> **Note:** For `apikey` the tenant ID is a plain environment variable in the bicepparam (`EntraIdAuth__TenantId`), not a Key Vault secret.

#### obo

| Key Vault secret name | Description |
|---|---|
| `{ServerName}ClientId` | Client ID of the Entra ID app registration for this MCP server |
| `{ServerName}ClientSecret` | Client secret of the Entra ID app registration |
| `{ServerName}TenantId` | Tenant ID — stored in Key Vault so it is masked in logs |

#### noauth

| Key Vault secret name | Description |
|---|---|
| `{ServerName}ClientId` | Client ID of the Entra ID app registration for this MCP server |
| `{ServerName}ClientSecret` | Client secret of the Entra ID app registration |
| `{ServerName}TenantId` | Tenant ID — stored in Key Vault so it is masked in logs |

> **Tip:** Secret names in Key Vault are PascalCase (e.g. `WeatherForecastApiKey`). The bicepparam template maps them to lowercase `secretRef` keys internally — do not change the casing in the bicepparam file.

### 3. Configure the Entra ID app registration

Register (or reuse) an app registration in Entra ID for this server:

- Expose an API scope: `api://{ClientId}/mcp.tools`
- Add `{ClientId}` as the Application ID URI prefix
- For **EntraId (OBO) mode**: grant the app delegated permissions to the downstream resource (e.g. Power BI or Dynamics 365) and enable the OBO flow by adding a client secret

The Copilot agent / Copilot Studio connector authenticates users and obtains tokens for `api://{ClientId}/mcp.tools` using OAuth 2.0 Authorization Code flow.

### 4. Fill in appsettings.Development.json

For local development, update `MCPServers/{ServerName}/appsettings.Development.json` with real values:

```json
{
  "EntraIdAuth": {
    "TenantId": "your-tenant-id",
    "ClientId": "your-client-id",
    "ClientSecret": "your-client-secret"
  }
}
```

This file is excluded from the Docker build and should not be committed with real secrets (add it to `.gitignore` for your server folder, or use user-secrets instead).

### 5. Implement the service and tool

The generated service and tool contain placeholder implementations — replace them with real logic:

**`MCPServers/{ServerName}/Services/{ServerName}Service.cs`**
- Inherits from `BaseHttpService` which provides `GetAsync<T>` and `PostAsync<T>` helpers with structured logging
- **apikey**: reads `{ApiConfigSection}:ApiKey` and `{ApiConfigSection}:BaseUrl` from `IConfiguration`; sends the key as `X-Api-Key` header
- **obo**: reads `DownstreamApi:Scope` (OBO scope) and `DownstreamApi:BaseUrl` from `IConfiguration`; exchanges the signed-in user's token via MSAL OBO using the scope, then calls the API with the resulting bearer token
- **noauth**: reads `{ApiConfigSection}:BaseUrl` from `IConfiguration`; no auth header added

**`MCPServers/{ServerName}/Tools/{ServerName}Tool.cs`**
- Decorate methods with `[McpServerTool]` and `[Description("…")]` — these descriptions appear in Copilot
- Keep tool methods thin: validate inputs, call the service, return the result
- Return strings, objects, or use `IExportToStorageService` to upload large results to Blob Storage and return a SAS URL

### 6. Run locally

```
dotnet run --project MCPServers/{ServerName}/{ServerName}.csproj
```

Or use the VS Code launch config (`F5` after selecting `{ServerName}` in the Run and Debug panel).

The server starts on `http://localhost:{Port}` with stateless transport disabled (`IsTransportStateless: false` in `appsettings.Development.json`), which is more convenient for local testing with the MCP Inspector or a locally configured Copilot agent.

### 7. Push to main and complete the deployment

Push to the `main` branch. The generated workflow (`.github/workflows/docker-publish-{servername}.yml`) triggers automatically, builds the Docker image using the `MCPServers/` folder as context, pushes it to `{EnvironmentName}.azurecr.io/{servername}:latest`, and deploys the Container App.

### 8. Update the public URL (after first deploy)

After the Container App is created for the first time, get its ingress URL:

```
az containerapp show --name {servername} --resource-group rg-{EnvironmentName} --query "properties.configuration.ingress.fqdn" -o tsv
```

Update `EntraIdAuth__PublicUrl` in `Infrastructure/containerApp-{ServerName}.bicepparam`:

```bicep
{
  name: 'EntraIdAuth__PublicUrl'
  value: 'https://{fqdn}'
}
```

Push again. This URL appears in the MCP `WWW-Authenticate` discovery header so Copilot Studio can find the auth endpoint.

### 9. Register the Copilot Custom Connector

Use `Copilot/CustomConnectors/{ServerName}.swagger.json` to register the server as a custom connector in Copilot Studio, pointing to `https://{fqdn}/sse` (or `/mcp` for stateless transport).

---

## Troubleshooting

### `dotnet run` fails with authentication errors locally

Check that `appsettings.Development.json` contains valid `TenantId`, `ClientId`, and `ClientSecret` values. For quick local testing without Entra ID, you can temporarily comment out `.RequireAuthorization()` in `Program.cs` — but never commit that change.

### Container App starts but tools return 401

The `EntraIdAuth__PublicUrl` value in the bicepparam file is likely missing or wrong. It must match the Container App's public HTTPS URL exactly (no trailing slash). Redeploy after fixing it.

### Push triggers no workflow

The workflow path filter in `.github/workflows/docker-publish-{servername}.yml` watches `MCPServers/{ServerName}/**`. Make sure you pushed changes inside that folder (e.g. the bicepparam file is in `Infrastructure/`, not inside the server folder — edit a source file to trigger the build, or use `workflow_dispatch`).

### `AcrPull` permission denied when deploying Container App

The Container App uses the User-Assigned Managed Identity (`umi-{EnvironmentName}`) to pull images from ACR. If it was not assigned the `AcrPull` role during `main.bicep` deployment, assign it manually:

```
az role assignment create \
  --assignee $(az identity show --name umi-{EnvironmentName} --resource-group rg-{EnvironmentName} --query principalId -o tsv) \
  --role AcrPull \
  --scope $(az acr show --name {EnvironmentName} --query id -o tsv)
```

### Key Vault secret not found at runtime

Secret names are case-sensitive in Key Vault. Ensure the secret name in Key Vault (PascalCase, e.g. `WeatherForecastApiKey`) matches the `value` field in `keyVaultSecrets` in the bicepparam file.
