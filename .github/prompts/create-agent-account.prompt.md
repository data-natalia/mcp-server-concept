---
mode: agent
description: Create or update the agent/client app registration for Copilot or APIM integration. Triggered by "/create-agent-account".
---

# Create Agent Account

You are creating an app registration for an agent or client application that calls the MCP server (for Copilot or APIM scenarios) and storing its credentials in Azure Key Vault by using repository scripts. This step is **only required** if you are integrating with Copilot or other clients that use APIM. Follow EVERY step exactly. Do NOT skip steps or reorder them.

Use only these scripts for execution logic:
- `scripts/Validate-ProvisioningEnvironment.ps1`
- `scripts/New-EntraAppRegistration.ps1`

Do not re-implement their Azure CLI logic inline in this prompt.

---

## Step 0 — Run prerequisite and access checks

Run:

```powershell
pwsh -NoProfile -File .\scripts\Validate-ProvisioningEnvironment.ps1
```

The script returns JSON. Parse it into `prereq`.

If command fails, or `prereq.success` is `false`, stop and print:
> ❌ {prereq.errorMessage}

If successful, capture:
- `currentSubscriptionName = prereq.currentSubscriptionName`
- `currentSubscriptionId = prereq.currentSubscriptionId`
- `directoryRoleNames = prereq.directoryRoleNames`
- `availableKeyVaults = prereq.availableKeyVaults`

Print:
> ✅ Azure CLI authenticated to subscription: **{currentSubscriptionName}** ({currentSubscriptionId})

Print:
> ✅ You have the required Entra ID role to create app registrations.

Print:
> ✅ Found {count} Key Vault(s) in current subscription

---

## Step 1 — Collect inputs

Call the `vscode_askQuestions` tool with exactly these four questions. Build the options for KeyVaultName from `availableKeyVaults` and mark the first one as recommended:

**Naming Convention**: Agent app names follow the pattern `agent-{ServerName}` and match an MCP app named `mcp-{ServerName}` (created by `/create-mcp-account`).

```json
{
  "questions": [
    {
      "header": "ServerName",
      "question": "Server name (e.g. WeatherForecast, PartnerCenter). Agent will be named agent-{ServerName} and must match the mcp-{ServerName} app from /create-mcp-account.",
      "allowFreeformInput": true
    },
    {
      "header": "McpAppId",
      "question": "Application ID (GUID) of the mcp-{ServerName} app registration created by /create-mcp-account.",
      "allowFreeformInput": true
    },
    {
      "header": "KeyVaultName",
      "question": "Azure Key Vault name where credentials will be stored (same as used in /create-mcp-account).",
      "allowFreeformInput": true,
      "options": [
        { "label": "{availableKeyVaults[0]}", "recommended": true },
        { "label": "{availableKeyVaults[1]}" },
        ...
      ]
    },
    {
      "header": "UseCurrentSubscription",
      "question": "Use the current Azure subscription {currentSubscriptionName} ({currentSubscriptionId})?",
      "allowFreeformInput": false,
      "options": [
        { "label": "Yes", "recommended": true, "description": "Use current subscription" },
        { "label": "No", "description": "Specify a different subscription" }
      ]
    }
  ]
}
```

After the user answers:

- If **UseCurrentSubscription** is "Yes", use `subscriptionId = {currentSubscriptionId}`.
- If **UseCurrentSubscription** is "No", ask for a subscription ID:
  ```json
  {
    "questions": [
      {
        "header": "SubscriptionId",
        "question": "Azure subscription ID (GUID) containing the Key Vault.",
        "allowFreeformInput": true
      }
    ]
  }
  ```
  Validate it is a valid GUID (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`). If not, stop and ask the user to correct it.

Validate the inputs:
- **ServerName** must be PascalCase or alphanumeric with no spaces. If it does not match `^[A-Za-z0-9]+$`, stop and ask the user to correct it.
- **McpAppId** must be a valid GUID. If it does not, stop and ask the user to correct it.
- **KeyVaultName** must match `^[a-z0-9-]{3,24}$`. If it does not, stop and ask the user to correct it.

---

## Step 2 — Execute provisioning script

Run:

```powershell
pwsh -NoProfile -File .\scripts\New-EntraAppRegistration.ps1 -ServerName "{ServerName}" -McpAppId "{McpAppId}" -KeyVaultName "{KeyVaultName}" -SubscriptionId "{subscriptionId}" -AccountType "agent"
```

The script returns JSON. Parse it into `result`.

If command fails, or `result.success` is `false`, stop and print:
> ❌ {result.errorMessage}

Capture from result:
- `agentAppId = result.agentAppId`
- `tenantId = result.tenantId`
- `resourceGroupName = result.resourceGroupName`
- `keyVaultSecretName = result.keyVaultSecretName`

Do not print secret values.

---

## Step 3 — Print completion checklist

Print:

```
✅ App registration 'agent-{ServerName}' configured
✅ Enterprise Application for '{agentAppId}' verified
✅ Description set
✅ Microsoft Graph delegated permissions added (User.Read, offline_access, profile)
✅ Delegated permission granted to MCP app scope api://{McpAppId}/mcp.tools
✅ Client secret created (10-year expiry)
✅ Key Vault secret stored in {KeyVaultName}
```

Print:
> ✅ Key Vault secret created: {keyVaultSecretName}
> 
> **Note:** Agent app has delegated access to both Microsoft Graph and the MCP server scope.

Print next steps:

> **Next step:** If this is a Copilot client app, run **/set-reply-uri** to add the client's redirect URI. Then users will need to consent to the delegated permissions the next time they authenticate.
