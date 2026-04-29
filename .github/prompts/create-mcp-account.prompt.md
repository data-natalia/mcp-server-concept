---
mode: agent
description: Create or update the MCP app registration and store credentials in Key Vault. Triggered by "/create-mcp-account".
---

# Create MCP Account

You are creating an app registration for MCP server authentication and storing its credentials in Azure Key Vault by using repository scripts. Follow EVERY step exactly. Do NOT skip steps or reorder them.

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
- `suggestedEnvironmentName = prereq.suggestedEnvironmentName`

Print:
> ✅ Azure CLI authenticated to subscription: **{currentSubscriptionName}** ({currentSubscriptionId})

Print:
> ✅ You have the required Entra ID role to create app registrations.

Print:
> ✅ Found {count} Key Vault(s) in current subscription

If `suggestedEnvironmentName` is non-empty, print:
> ℹ️ Detected environment name from configuration: **{suggestedEnvironmentName}**

---

## Step 1 — Collect inputs

Call the `vscode_askQuestions` tool with exactly these three questions. Build the options for KeyVaultName from `availableKeyVaults` and mark the first one as recommended:

```json
{
  "questions": [
    {
      "header": "ServerName",
      "question": "Server name for the MCP account (e.g. WeatherForecast, PartnerCenter). Used in app display name and Key Vault secret names.",
      "allowFreeformInput": true
    },
    {
      "header": "KeyVaultName",
      "question": "Azure Key Vault name where credentials will be stored.",
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

Validate **ServerName**:
- Must be PascalCase or alphanumeric with no spaces. If it does not match `^[A-Za-z0-9]+$`, stop and ask the user to correct it.

Validate **KeyVaultName**:
- Must match `^[a-z0-9-]{3,24}$`. If it does not, stop and ask the user to correct it.

---

## Step 2 — Execute provisioning script

Run:

```powershell
pwsh -NoProfile -File .\scripts\New-EntraAppRegistration.ps1 -ServerName "{ServerName}" -KeyVaultName "{KeyVaultName}" -SubscriptionId "{subscriptionId}" -AccountType "mcp"
```

The script returns JSON. Parse it into `result`.

If command fails, or `result.success` is `false`, stop and print:
> ❌ {result.errorMessage}

Capture from result:
- `appId = result.appId`
- `tenantId = result.tenantId`
- `resourceGroupName = result.resourceGroupName`
- `secrets = result.secrets`

Do not print secret values.

---

## Step 3 — Print completion checklist

Print:

```
✅ App registration 'mcp-{ServerName}' configured
✅ Enterprise Application for '{appId}' verified
✅ Application ID URI: api://{appId}
✅ API scope api://{appId}/mcp.tools exposed
✅ Microsoft Graph delegated permissions added (User.Read, offline_access, profile)
✅ Admin consent granted
✅ Client secret created (10-year expiry)
✅ Key Vault secrets stored in {KeyVaultName}
```

Print:
> ✅ Key Vault secrets created:
> - {secrets[0]}
> - {secrets[1]}
> - {secrets[2]}
> - {secrets[3]}

Print next steps:

> **Next step:** 
> - If you are integrating this MCP server with **Copilot or APIM clients**, run **/create-agent-account** to create an agent app registration with delegated permissions.
> - If you have a **web client application**, run **/set-reply-uri** to add its OAuth 2.0 redirect URI.
