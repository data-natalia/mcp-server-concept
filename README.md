# Atea MCP Concept

A scaffold repository for teams building their first [Model Context Protocol (MCP)](https://modelcontextprotocol.io) servers on Azure. Clone this repo, follow the setup steps, and have a production-ready MCP server deployed in your own Azure environment.

---

## What Is This?

MCP servers expose tools that AI assistants (such as GitHub Copilot or Microsoft 365 Copilot) can invoke on behalf of users. This repository provides:

- A **shared .NET class library** with authentication, telemetry, and token exchange already wired up
- **File templates** for scaffolding new MCP servers (C# project, Dockerfile, Bicep, CI/CD workflow, Copilot custom connector)
- **Copilot agent prompts** that guide you through deployment setup and server creation step by step
- **Reusable GitHub Actions workflows** for building Docker images and deploying to Azure Container Apps

---

## Architecture

Each MCP server runs as a containerised .NET 9 application on Azure Container Apps.

**CI/CD and infrastructure:**

```
GitHub Actions
    ├── Build Docker image → push to Azure Container Registry
    └── Deploy Bicep → Azure Container App
                            ├── reads secrets from Azure Key Vault
                            ├── reports telemetry to Application Insights
                            └── uses Managed Identity for Azure access
```

**Runtime (inbound and outbound auth):**

```
GitHub Copilot / Copilot Studio
        │  OAuth 2.0 (Entra ID)
        │  Bearer token in Authorization header
        ▼
┌───────────────────────────────────────────────┐
│  Azure Container App  (one per MCP server)    │
│  .NET 9 / ModelContextProtocol.AspNetCore     │
│  JWT Bearer + MCP WWW-Authenticate discovery  │
│  Tool  →  Service                             │
└───────────────────────────────────────────────┘
        │
        │  API Key  ──or──  OBO bearer token  ──or──  (no auth)
        ▼
   Upstream API  (Dynamics 365, Power BI, custom …)
```

**Shared infrastructure (one per environment):**
- Azure Container Registry — stores Docker images
- Container Apps Environment — hosts all MCP server containers
- Azure Key Vault — stores per-server secrets
- Log Analytics Workspace + Application Insights — observability
- Azure Storage Account — optional export target for large tool responses
- User-Assigned Managed Identity — grants containers access to Key Vault

**Per server:**
- Container App
- GitHub Actions workflow
- Bicep parameter file
- Copilot Custom Connector (`swagger.json`)

---

## Prerequisites

| Tool | Purpose | Install |
|---|---|---|
| [.NET 9 SDK](https://dotnet.microsoft.com/download/dotnet/9.0) | Build and run C# projects locally | `winget install Microsoft.DotNet.SDK.9` |
| [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) | Provision Azure resources and manage roles | `winget install Microsoft.AzureCLI` |
| [GitHub CLI](https://cli.github.com) | Configure Actions secrets and variables | `winget install GitHub.cli` |
| [VS Code](https://code.visualstudio.com/) | Recommended editor — launch and task configs are included | `winget install Microsoft.VisualStudioCode` |
| A GitHub account | Host the repo and run Actions | — |
| An Azure subscription | Host all infrastructure | — |
| Permission to create App Registrations in Entra ID | Required for inbound authentication | Contact your Azure AD administrator |

---

## Step-by-Step Guide

### 1. Fork the repository

Fork this repository into your own GitHub organisation using the **Fork** button at the top of the page, then clone your fork locally:

```bash
git clone https://github.com/{your-org}/{your-repo}.git
cd {your-repo}
```

### 2. Run `/setup-deployment` in GitHub Copilot Chat

Open GitHub Copilot Chat in VS Code and run:

```
/setup-deployment
```

This guided prompt will:
- Collect your environment name, location, and subscription ID
- Deploy all shared Azure infrastructure (`Infrastructure/main.bicep`)
- Create a service principal and store its credentials as the `AZURE_CREDENTIALS` GitHub secret
- Set the `ACR_NAME_DEV` and `ACR_NAME_PROD` Actions variables

See [docs/setup-deployment.md](docs/setup-deployment.md) for a detailed walkthrough.

### 3. Commit and push `Infrastructure/dev.bicepparam`

The setup prompt writes your environment values into this file. Commit it:

```bash
git add Infrastructure/dev.bicepparam
git commit -m "chore: configure deployment environment"
git push
```

### 4. Create an App Registration in Entra ID

Each MCP server needs an App Registration for inbound authentication (Copilot → your server). In the [Azure Portal](https://portal.azure.com), go to **Entra ID → App registrations** and create one:

1. Give it a name (e.g. `mcp-{servername}`)
2. Add a client secret under **Certificates & secrets**
3. Note the **Tenant ID**, **Client ID**, and **Client Secret value** — you will need these in steps 7 and 8

### 5. Run `/new-mcp-server` in GitHub Copilot Chat

```
/new-mcp-server
```

This guided prompt scaffolds all files for a new server — C# project, Dockerfile, `appsettings.json`, Bicep parameter file, GitHub Actions workflow, and Copilot custom connector.

See [docs/new-mcp-server.md](docs/new-mcp-server.md) for a detailed walkthrough.

### 6. Implement the service and tool

Fill in the generated service and tool classes with real logic:

- `MCPServers/{ServerName}/Services/{ServerName}Service.cs` — calls the upstream API
- `MCPServers/{ServerName}/Tools/{ServerName}Tool.cs` — exposes methods to Copilot via `[McpServerTool]`

### 7. Fill in the TODOs in the bicepparam file

Open `Infrastructure/containerApp-{ServerName}.bicepparam` and replace all `TODO` values:

| TODO | Replace with |
|---|---|
| `TODO-container-apps-environment-name` | Your `EnvironmentName` from step 2 |
| `TODO-resource-group-name` | `rg-{EnvironmentName}` |
| `TODO-upstream-api-base-url` | Base URL of the upstream API *(apikey and noauth only)* |
| `TODO-obo-scope` | OBO scope for the downstream API, must end in `/.default` *(obo only)* |
| `TODO-api-base-url` | Base URL of the downstream API *(obo only)* |
| `TODO-tenant-id` | Tenant ID from step 4 *(apikey only — obo and noauth read this from Key Vault)* |
| `TODO-public-url-after-first-deploy` | Leave for now — fill in after the first deploy (step 10) |

### 8. Create Key Vault secrets

In the [Azure Portal](https://portal.azure.com), open your Key Vault (`{EnvironmentName}`) and add the secrets.

For **apikey** auth:
- `{ServerName}ApiKey` — the upstream API key
- `{ServerName}ClientId` — Client ID from step 4
- `{ServerName}ClientSecret` — Client Secret from step 4

For **obo** or **noauth** auth:
- `{ServerName}ClientId` — Client ID from step 4
- `{ServerName}ClientSecret` — Client Secret from step 4
- `{ServerName}TenantId` — Tenant ID (stored in Key Vault so it is masked in logs)

For all three auth types, see [docs/new-mcp-server.md — Create Key Vault secrets](docs/new-mcp-server.md#2-create-key-vault-secrets).

### 9. Commit and push

```bash
git add .
git commit -m "feat: scaffold {ServerName} MCP server"
git push
```

GitHub Actions triggers automatically: builds the Docker image, pushes it to ACR, and deploys the Container App via Bicep.

### 10. Update the public URL and register the connector

After the first successful deployment, find the Container App's public URL in the Azure Portal (or via `az containerapp show`). Update `EntraIdAuth__PublicUrl` in the bicepparam file and push again. Then add `Copilot/CustomConnectors/{ServerName}.swagger.json` as a Copilot Custom Connector in Copilot Studio.

---

## Repository Structure

```
.github/
├── prompts/
│   ├── setup-deployment.prompt.md    Copilot agent — provision Azure + configure CI/CD
│   └── new-mcp-server.prompt.md      Copilot agent — scaffold a new MCP server
├── templates/mcp-server/             File templates used by /new-mcp-server
└── workflows/
    ├── docker-publish-template.yml              Reusable: build and push Docker image
    └── docker-deploy-containerapp-template.yml  Reusable: deploy Bicep to Azure
Copilot/
└── CustomConnectors/                 Generated swagger files for Copilot connectors
Infrastructure/
├── main.bicep                        Shared infrastructure (ACR, KV, ACA env, …)
├── containerApp.bicep                Per-server Container App deployment
└── dev.bicepparam                    Environment parameters (updated by /setup-deployment)
MCPServers/
└── Shared/                           Shared .NET library (auth, telemetry, token exchange)
docs/
├── setup-deployment.md              Detailed guide for /setup-deployment
└── new-mcp-server.md                Detailed guide for /new-mcp-server
```

---

## Authentication Models

All MCP servers in this scaffold protect their own endpoint with **Entra ID JWT bearer** (inbound auth). The `AuthType` only controls how the **service layer** calls the downstream API.

**obo (On-Behalf-Of)** — the downstream API uses Entra ID (e.g. Dynamics 365, Power BI, Microsoft Graph). The MCP server performs an OAuth 2.0 On-Behalf-Of token exchange using MSAL so requests are made in the context of the signed-in user. Client credentials are stored in Key Vault.

**apikey** — the downstream API authenticates with a static key passed as a request header. The key is stored in Key Vault and injected as an environment variable at runtime.

**noauth** — the downstream API has no authentication (open or internal API). No auth header is sent to the upstream API.
