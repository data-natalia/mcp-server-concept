# Manage App Registrations

This guide covers the three Copilot agent commands for managing Entra ID app registrations needed by MCP servers: creating an MCP account, creating an agent account, and setting reply URIs.

---

## Overview

Each MCP server deployment requires one app registration:

1. **MCP App Registration** (`mcp-{ServerName}`) — Protects the MCP server endpoint. Called by upstream clients (including Copilot agents, if directly integrated).

**Optional:** If you are integrating the MCP server with **Copilot or other clients that use APIM** and need an agent or client app to authenticate and call the MCP server with delegated permissions, you may also create:

2. **Agent App Registration** (`agent-{ServerName}`) — Used by AI agents or client applications to authenticate with delegated permissions to call the MCP server. Only required for Copilot Studio custom connectors or APIM-based scenarios.

Both registrations store their credentials in Azure Key Vault for secure retrieval at runtime.

---

## Prerequisites

| Requirement | Details |
|---|---|
| **Azure CLI** | Must be installed and authenticated (`az login`) |
| **Entra ID Role** | You must have one of: Application Developer, Application Administrator, or Global Administrator |
| **Key Vault** | Must exist (created by `/setup-deployment`); you must have Key Vault Secrets Officer or higher role |
| **Azure Subscription** | Where the Key Vault is deployed |

---

## Workflow

```
┌────────────────────────────────────┐
│  1. /setup-deployment              │  (Provision shared infrastructure)
│     Creates Key Vault              │
└────────────┬───────────────────────┘
             │
             ▼
┌────────────────────────────────────┐
│  2. /create-mcp-account            │  (Required)
│     - Creates app for MCP server   │
│     - Exposes API scope            │
│     - Stores credentials in KV     │
└────────────┬───────────────────────┘
             │
             ▼
┌────────────────────────────────────┐
│  3. /create-agent-account          │  (Optional: Copilot/APIM only)
│     - Creates app for agent/client │
│     - Adds delegated permissions   │
│     - Stores credentials in KV     │
└────────────┬───────────────────────┘
             │
             ▼
┌────────────────────────────────────┐
│  4. /set-reply-uri (optional)      │  (Optional: web clients with OAuth redirects)
│     - For web client apps          │
│     - Adds web reply URI           │
│     - Idempotent (no-op if exists) │
└────────────────────────────────────┘
             │
             ▼
┌────────────────────────────────────┐
│  5. /new-mcp-server                │  (Scaffold server & deploy)
│     - Creates server project       │
│     - Configures bicepparam        │
│     - References KV secrets        │
└────────────────────────────────────┘
```

---

## Step 1: Create MCP Account

Run:

```
/create-mcp-account
```

### What it does

- Creates an app registration named `mcp-{ServerName}`
- Exposes an API scope `api://{AppId}/mcp.tools` for delegated access
- Adds Microsoft Graph `User.Read` delegated permission
- Creates a 10-year client secret
- Stores four secrets in Key Vault:
  - `mcp-{ServerName}` — JSON payload with all credentials
  - `{ServerName}ClientId` — Application ID
  - `{ServerName}ClientSecret` — Client secret value
  - `{ServerName}TenantId` — Tenant ID

### Inputs

| Input | Description | Example |
|---|---|---|
| **ServerName** | Name of the MCP server | `WeatherForecast` |
| **KeyVaultName** | Name of the Azure Key Vault | `mymcpenv` |
| **SubscriptionId** | Azure subscription containing the Key Vault | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |

### Example output

```
✅ App registration 'mcp-WeatherForecast' created (AppId: 12345678-1234-1234-1234-123456789012)
✅ API scope api://12345678-1234-1234-1234-123456789012/mcp.tools exposed
✅ Microsoft Graph User.Read delegated permission added
✅ Client secret created (10-year expiry)
✅ Key Vault secrets stored in mymcpenv

Next step: Run /create-agent-account to create the agent app registration...
```

### Idempotent behavior

- If an app registration with the name `mcp-{ServerName}` already exists, it will be reused
- Existing Key Vault secrets will be overwritten with the new credentials
- Running the command again is safe and will not create duplicate registrations

---

## Step 2: Create Agent Account (Optional)

Run:

```
/create-agent-account
```

**Note:** This step is **optional** and only required if you are integrating the MCP server with **Copilot Studio custom connectors or APIM-based clients** that need an agent or client application to authenticate with delegated permissions to call the MCP server. If your MCP server is called directly (e.g., by a backend service), skip this step.

### What it does

- Creates an app registration named `agent-{ServerName}`
- Adds three delegated permissions from Microsoft Graph:
  - `User.Read` — Read user profile
  - `offline_access` — Refresh token access
  - `profile` — Read user's email and profile
- Adds delegated permission to the MCP app's exposed scope `api://{McpAppId}/mcp.tools`
- Creates a 10-year client secret
- Stores one secret in Key Vault:
  - `agent-{ServerName}` — JSON payload with ApplicationId, ClientSecret, TenantId

### Inputs

| Input | Description | Example |
|---|---|---|
| **ServerName** | Same as used in `/create-mcp-account` | `WeatherForecast` |
| **McpAppId** | Application ID from the MCP app registration | `12345678-1234-1234-1234-123456789012` |
| **KeyVaultName** | Same as used in `/create-mcp-account` | `mymcpenv` |
| **SubscriptionId** | Azure subscription containing the Key Vault | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |

### Example output

```
✅ App registration 'agent-WeatherForecast' created (AppId: 87654321-4321-4321-4321-210987654321)
✅ Microsoft Graph delegated permissions added (User.Read, offline_access, profile)
✅ Delegated permission added to MCP app scope api://12345678-1234-1234-1234-123456789012/mcp.tools
✅ Client secret created (10-year expiry)
✅ Key Vault secret stored in mymcpenv

Next step: If this is a Copilot client app, run /set-reply-uri to add the client's redirect URI...
```

### Idempotent behavior

- If an app registration with the name `agent-{ServerName}` already exists, it will be reused
- Existing Key Vault secrets will be overwritten with the new credentials
- Running the command again is safe and will not create duplicate registrations

### Consent and permissions

When users first authenticate to the agent app, they will see a consent prompt requesting permission to:
- Read your profile (User.Read)
- Maintain access to data you have given it access to (offline_access)
- View your basic profile (profile)
- Access the MCP server on your behalf (api://{McpAppId}/mcp.tools)

A tenant administrator can pre-grant admin consent in the Azure Portal to skip the user consent prompt:
1. Go to **Entra ID > App registrations > agent-{ServerName} > API permissions**
2. Click **Grant admin consent for {TenantName}**

---

## Step 3: Set Reply URI (Optional — Web Clients Only)

Run (only if the agent is a **web client application** using OAuth 2.0 redirects):

```
/set-reply-uri
```

**Note:** This step is only required for web applications that use OAuth 2.0 authentication flows with client-side redirects (e.g., single-page applications, web portals). It is not needed for backend services, desktop applications, or server-to-server authentication scenarios.

### What it does

- Adds a web reply URI (OAuth 2.0 redirect URI) to an app registration
- Looks up the app by Application ID (GUID) or display name
- If multiple apps have the same name, prompts you to choose the correct one
- Idempotent: no-op if the URI already exists
- Does not require Key Vault access (no secrets written)

### Inputs

| Input | Description | Example |
|---|---|---|
| **AppIdentifier** | Application ID (GUID) or display name | `87654321-4321-4321-4321-210987654321` or `agent-WeatherForecast` |
| **ReplyUri** | HTTPS web redirect URI | `https://myapp.azurewebsites.net/auth/callback` |

### Example output

```
✅ Reply URI added to app registration '87654321-4321-4321-4321-210987654321'

Web reply URIs:
  - https://myapp.azurewebsites.net/auth/callback
  - https://localhost:3000/auth/callback

Next step: Users will now be redirected to 'https://myapp.azurewebsites.net/auth/callback' when they complete OAuth 2.0 authentication.
```

### Idempotent behavior

- If the URI already exists, the command prints a message and stops (no changes)
- Safe to run multiple times

---

## Key Vault Secret Names and Formats

All secrets are stored in the Key Vault with exact casing as shown. Application code and Bicep parameter files must reference these names exactly.

### MCP Account Secrets

| Secret Name | Description | Format |
|---|---|---|
| `mcp-{ServerName}` | Complete credentials | `{"ApplicationId":"{appId}","ClientSecret":"{secret}","TenantId":"{tenantId}"}` |
| `{ServerName}ClientId` | Application ID only | `{appId}` (GUID) |
| `{ServerName}ClientSecret` | Client secret value only | `{secret}` (string) |
| `{ServerName}TenantId` | Tenant ID only | `{tenantId}` (GUID) |

**Example for `WeatherForecast` server:**
- `mcp-WeatherForecast`
- `WeatherForecastClientId`
- `WeatherForecastClientSecret`
- `WeatherForecastTenantId`

### Agent Account Secrets

| Secret Name | Description | Format |
|---|---|---|
| `agent-{ServerName}` | Complete credentials | `{"ApplicationId":"{appId}","ClientSecret":"{secret}","TenantId":"{tenantId}"}` |

**Example for `WeatherForecast` agent:**
- `agent-WeatherForecast`

---

## Troubleshooting

### "You do not have Application Developer, Application Administrator, or Global Administrator role"

**Problem:** The role check failed.

**Solution:**
1. Verify your Entra ID roles in the [Azure Portal](https://portal.azure.com) under **Entra ID > Users > {YourName} > Assigned roles**
2. Contact your Azure AD administrator to assign one of the required roles
3. If recently assigned, sign out and sign back in: `az logout && az login`

### "Key Vault '{KeyVaultName}' not found or you do not have access"

**Problem:** Key Vault is missing or inaccessible.

**Solution:**
1. Verify the Key Vault name matches the environment name from `/setup-deployment`
2. Verify you have Key Vault Secrets Officer or higher role on the Key Vault
3. If using a different subscription, verify you set the correct SubscriptionId

### "App registration '{AppIdentifier}' not found"

**Problem:** The app registration does not exist or the name is wrong.

**Solution (for `/set-reply-uri`):**
1. Verify the display name or Application ID is correct
2. Use the Application ID (GUID) instead of the display name for a more reliable lookup
3. Check the [Azure Portal](https://portal.azure.com) under **Entra ID > App registrations** to find the correct name or ID

### "Insufficient privileges to complete operation"

**Problem:** The role check passed but a subsequent operation failed due to insufficient permissions.

**Possible causes:**
- You do not have permission to grant admin consent to Microsoft Graph permissions
- You do not have permission to add API scopes to the app
- You do not have permission to update the app registration in this tenant

**Solution:**
1. Contact your Azure AD administrator to complete the step in the Azure Portal
2. Or ask them to grant you higher permissions (Application Administrator or Global Administrator)

### "PrincipalNotFound" when creating a secret

**Problem:** Role assignment or app registration creation propagated slowly in Entra ID.

**Solution:**
1. Wait 30–60 seconds
2. Run the command again

### Secrets are in the wrong Key Vault

**Problem:** You created secrets in the wrong Key Vault.

**Solution:**
1. Delete the incorrect secrets in the old Key Vault
2. Run the `/create-mcp-account` or `/create-agent-account` command again with the correct Key Vault name

### Users see a consent prompt every time

**Problem:** Admin consent was not granted, or the delegated permissions were updated.

**Solution:**
1. Have a tenant administrator grant admin consent in the Azure Portal:
   - Go to **Entra ID > App registrations > {AppName} > API permissions**
   - Click **Grant admin consent for {TenantName}**
2. If permissions were recently updated, cached consent may need to be cleared (this happens automatically over time)

---

## Next Steps

After creating the app registrations and setting reply URIs:

1. **For MCP servers:** Run `/new-mcp-server` to scaffold the server code and Bicep deployment, which will reference the Key Vault secrets automatically
2. **For agents or client apps:** Use the agent app credentials in your authentication code to obtain access tokens
3. **For Copilot Studio connectors:** Register the MCP server as a custom connector using the OpenAPI definition and the MCP app credentials
