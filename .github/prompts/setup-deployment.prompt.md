---
mode: agent
description: Provision the shared MCP environment and store credentials as GitHub Actions secrets. Triggered by "/setup-deployment".
---

# Setup Deployment

You are provisioning the shared MCP infrastructure for this repository and wiring it to GitHub Actions. Follow EVERY step exactly. Do NOT skip steps or reorder them.

---

## Step 1 — Collect inputs

Call the `vscode_askQuestions` tool with exactly these five questions:

```json
{
  "questions": [
    {
      "header": "DevEnvironmentName",
      "question": "Short name for the dev environment (e.g. mymcpdev). Rules: 5–22 characters, lowercase letters and digits only, no hyphens or underscores. Used as the Key Vault name, Container Apps environment name, Log Analytics name, and Storage Account prefix for the dev environment.",
      "allowFreeformInput": true
    },
    {
      "header": "ProdEnvironmentName",
      "question": "Short name for the prod environment (e.g. mymcpprod). Same rules as the dev name. Must be different from the dev name.",
      "allowFreeformInput": true
    },
    {
      "header": "AcrName",
      "question": "Short name for the shared Azure Container Registry (e.g. mymcpacr). Rules: 5–50 characters, alphanumeric only. Globally unique — this ACR is shared by both dev and prod. A 'rg-' prefix is used for the registry resource group name.",
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
- **DevEnvironmentName** must match `^[a-z0-9]{5,22}$`. If it does not, stop and ask the user to correct it.
- **ProdEnvironmentName** must match `^[a-z0-9]{5,22}$` and must differ from **DevEnvironmentName**. If it does not, stop and ask the user to correct it.
- **AcrName** must match `^[a-z0-9]{5,50}$`. If it does not, stop and ask the user to correct it.
- **SubscriptionId** must be a valid GUID (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`). If it does not look like a GUID, stop and ask the user to correct it.

Derive the remaining resource names:

| Parameter | Value |
|---|---|
| `acrName` | `{AcrName}` (shared across dev and prod) |
| `acrResourceGroupName` | `rg-{AcrName}` |
| Dev `containerAppsEnvName` | `{DevEnvironmentName}` |
| Dev `keyVaultName` | `{DevEnvironmentName}` |
| Dev `logAnalyticsName` | `{DevEnvironmentName}` |
| Dev `storageAccountName` | `st{DevEnvironmentName}` |
| Dev `resourceGroupName` | `rg-{DevEnvironmentName}` |
| Prod `containerAppsEnvName` | `{ProdEnvironmentName}` |
| Prod `keyVaultName` | `{ProdEnvironmentName}` |
| Prod `logAnalyticsName` | `{ProdEnvironmentName}` |
| Prod `storageAccountName` | `st{ProdEnvironmentName}` |
| Prod `resourceGroupName` | `rg-{ProdEnvironmentName}` |

Echo the resolved values before proceeding:
> Provisioning **{DevEnvironmentName}** (dev) and **{ProdEnvironmentName}** (prod) with shared registry **{AcrName}** in **{Location}** — subscription `{SubscriptionId}`

---

## Step 2 — Verify prerequisites

Run the validation script:

```powershell
.\scripts\Validate-ProvisioningEnvironment.ps1 -CheckGitHubCli -SkipKeyVaultCheck
```

Parse the JSON output. If `success` is `false`, stop and show the user the `errorMessage`.

---

## Step 3 — Configure bicep parameter files

Run the bicep params script (this also sets the active subscription):

```powershell
.\scripts\Set-BicepParams.ps1 `
  -DevEnvironmentName '{DevEnvironmentName}' `
  -ProdEnvironmentName '{ProdEnvironmentName}' `
  -AcrName '{AcrName}' `
  -Location '{Location}' `
  -SubscriptionId '{SubscriptionId}'
```

Parse the JSON output. If `success` is `false`, stop and show the user the `errorMessage`.

This writes `Infrastructure/dev.bicepparam` and `Infrastructure/prod.bicepparam` with the resolved values.

---

## Step 4 — Create service principal and store credentials

Run the credentials script:

```powershell
.\scripts\Set-DeploymentCredentials.ps1 `
  -AcrName '{AcrName}' `
  -SubscriptionId '{SubscriptionId}'
```

Parse the JSON output. If `success` is `false`, stop and show the user the `errorMessage`.

This script (idempotent):
- Creates or resets service principal `sp-mcp-{AcrName}`
- Assigns Owner role on subscription `{SubscriptionId}` (skipped if already assigned)
- Stores credentials as `AZURE_CREDENTIALS` GitHub Actions secret
- Sets `ACR_NAME` GitHub Actions variable to `{AcrName}`

---

## Step 5 — Copy workflow templates to workflows folder

Copy the three GitHub Actions workflow templates from `.github/templates/` to `.github/workflows/`:

```
cp .github/templates/deploy-bicep.yml .github/workflows/
cp .github/templates/docker-deploy-containerapp-template.yml .github/workflows/
cp .github/templates/docker-publish-template.yml .github/workflows/
```

---

## Step 6 — Print completion checklist

Print a checklist of every action completed. Mark each item ✅:

```
✅ Infrastructure/dev.bicepparam updated
✅ Infrastructure/prod.bicepparam updated
✅ Service principal sp-mcp-{AcrName} created or updated
✅ Owner role assigned to SP on subscription {SubscriptionId}
✅ AZURE_CREDENTIALS secret set in GitHub Actions
✅ ACR_NAME variable set to {AcrName}
✅ Workflow templates copied to .github/workflows/
```

---

## Step 7 — Commit and push to trigger deployment

Review your changes:

```
git status
```

You should see `Infrastructure/dev.bicepparam` and `Infrastructure/prod.bicepparam` modified and the three workflow files in `.github/workflows/`. Commit and push the changes:

```
git add Infrastructure/dev.bicepparam Infrastructure/prod.bicepparam .github/workflows/
git commit -m "Configure MCP environments: {DevEnvironmentName} (dev) and {ProdEnvironmentName} (prod) with shared registry {AcrName}"
git push
```

This will trigger the **Deploy Bicep Template** workflow in GitHub Actions. The workflow will:
1. Deploy the shared infrastructure to Azure (ACR, Container Apps Environment, Key Vault, Log Analytics, etc.)

Monitor the workflow in the **Actions** tab of your repository.

Then print:
> **Next step:** Once the GitHub Actions workflow completes successfully, run **/new-mcp-server** to scaffold your first MCP server.
