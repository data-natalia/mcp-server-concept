---
mode: agent
description: Provision the shared MCP environment and store credentials as GitHub Actions secrets. Triggered by "/setup-deployment".
---

# Setup Deployment

You are provisioning the shared MCP infrastructure for this repository and wiring it to GitHub Actions. Follow EVERY step exactly. Do NOT skip steps or reorder them.

---

## Step 1 — Collect inputs

Call the `vscode_askQuestions` tool with exactly these three questions:

```json
{
  "questions": [
    {
      "header": "EnvironmentName",
      "question": "Short name for this deployment ring (e.g. mymcpenv). Rules: 5–22 characters, lowercase letters and digits only, no hyphens or underscores. This name is used directly as the ACR name, Key Vault name, Container Apps environment name, and Log Analytics name. A 'st' prefix is added for the Storage Account name, so the effective Storage Account name will be 'st{EnvironmentName}' (max 24 chars).",
      "allowFreeformInput": true
    },
    {
      "header": "Location",
      "question": "Azure region to deploy into.",
      "allowFreeformInput": true,
      "options": [
        { "label": "westeurope", "recommended": true },
        { "label": "northeurope" },
        { "label": "eastus" },
        { "label": "eastus2" },
        { "label": "swedencentral" }
      ]
    },
    {
      "header": "SubscriptionId",
      "question": "Azure subscription ID (GUID) to deploy resources into.",
      "allowFreeformInput": true
    }
  ]
}
```

Validate the inputs:
- **EnvironmentName** must match `^[a-z0-9]{5,22}$`. If it does not, stop and ask the user to correct it.
- **SubscriptionId** must be a valid GUID (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`). If it does not look like a GUID, stop and ask the user to correct it.

Derive the remaining resource names:

| Parameter | Value |
|---|---|
| `acrName` | `{EnvironmentName}` |
| `containerAppsEnvName` | `{EnvironmentName}` |
| `keyVaultName` | `{EnvironmentName}` |
| `logAnalyticsName` | `{EnvironmentName}` |
| `storageAccountName` | `st{EnvironmentName}` |
| `resourceGroupName` | `rg-{EnvironmentName}` |

Echo the resolved values before proceeding:
> Provisioning **{EnvironmentName}** in **{Location}** — subscription `{SubscriptionId}`

---

## Step 2 — Verify prerequisites

Run `az version` and `gh --version`. If either command is not found, stop and tell the user which tool to install with a link:
- Azure CLI: https://learn.microsoft.com/cli/azure/install-azure-cli
- GitHub CLI: https://cli.github.com/

Verify an active Azure login by running:

```
az account show --query "name" -o tsv
```

If the command fails or returns nothing, stop and tell the user to run `az login` first.

Verify the GitHub CLI is authenticated by running:

```
gh auth status
```

If not authenticated, stop and tell the user to run `gh auth login` first.

---

## Step 3 — Set active subscription

```
az account set --subscription {SubscriptionId}
```

---

## Step 4 — Update Infrastructure/dev.bicepparam

Read `Infrastructure/dev.bicepparam`. Replace the entire file contents with the following, substituting the resolved values:

```bicep
using 'main.bicep'

param acrName             = '{EnvironmentName}'
param containerAppsEnvName = '{EnvironmentName}'
param keyVaultName        = '{EnvironmentName}'
param logAnalyticsName    = '{EnvironmentName}'
param location            = '{Location}'
param resourceGroupName   = 'rg-{EnvironmentName}'
param storageAccountName  = 'st{EnvironmentName}'
```

---

## Step 5 — Deploy shared infrastructure

```
az deployment sub create --name mcp-shared-env --location {Location} --template-file Infrastructure/main.bicep --parameters Infrastructure/dev.bicepparam
```

This deploys the resource group and the following shared resources: Azure Container Registry, Log Analytics Workspace, Application Insights, Container Apps Environment, Key Vault, Storage Account, and User-Assigned Managed Identity.

This command may take several minutes. Wait for it to complete before continuing.

---

## Step 6 — Create service principal

Run the following command and **capture the JSON output into a variable**. Do NOT print the JSON to the terminal or display it in the chat — it contains the client secret.

```
az ad sp create-for-rbac --name "sp-mcp-{EnvironmentName}" --json-auth --output json
```

Store the complete JSON output in a shell variable named `SP_JSON`. Do not write it to disk.

> **Note:** If your Azure CLI version does not support `--json-auth`, use `--sdk-auth` instead — it produces the same output.

---

## Step 7 — Assign AcrPush on the Container Registry

Extract the `clientId` field from `SP_JSON` and assign the `AcrPush` role to the service principal on the ACR resource:

```
az role assignment create --assignee {clientId from SP_JSON} --role AcrPush --scope $(az acr show --name {EnvironmentName} --query id -o tsv)
```

---

## Step 8 — Assign Contributor on the subscription

Assign the `Contributor` role to the service principal at subscription scope so it can run the Bicep deployments from GitHub Actions:

```
az role assignment create --assignee {clientId from SP_JSON} --role Contributor --scope /subscriptions/{SubscriptionId}
```

---

## Step 9 — Store credentials in GitHub

Pipe `SP_JSON` directly to the GitHub CLI without writing to disk or displaying in the terminal. This keeps the client secret entirely out of terminal history and the file system:

```
echo {SP_JSON} | gh secret set AZURE_CREDENTIALS --app actions
```

Set the ACR name as GitHub Actions repository variables for both environments (both pointing to the same registry — split them into separate environments later if needed):

```
gh variable set ACR_NAME_DEV --body "{EnvironmentName}"
gh variable set ACR_NAME_PROD --body "{EnvironmentName}"
```

Clear `SP_JSON` from the shell variable after use.

---

## Step 10 — Print completion checklist

Print a checklist of every action completed. Mark each item ✅:

```
✅ Infrastructure/dev.bicepparam updated
✅ Shared infrastructure deployed to rg-{EnvironmentName}
   — ACR: {EnvironmentName}.azurecr.io
   — Container Apps Environment: {EnvironmentName}
   — Key Vault: {EnvironmentName}
✅ Service principal sp-mcp-{EnvironmentName} created
✅ AcrPush role assigned to SP on {EnvironmentName} ACR
✅ Contributor role assigned to SP on subscription {SubscriptionId}
✅ AZURE_CREDENTIALS secret set in GitHub Actions
✅ ACR_NAME_DEV variable set to {EnvironmentName}
✅ ACR_NAME_PROD variable set to {EnvironmentName}
```

Then print:
> **Next step:** run **/new-mcp-server** to scaffold your first MCP server.
