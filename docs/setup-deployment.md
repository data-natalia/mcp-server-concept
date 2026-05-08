# Setup Deployment

This guide explains what the `/setup-deployment` Copilot agent command does and walks through each step.

Run it **once** to provision the full shared Azure infrastructure — a dedicated registry resource group plus separate dev and prod environment resource groups — and wire everything to GitHub Actions.

---

## What it does

`/setup-deployment` provisions the shared resources that every MCP server in this repository depends on:

| Resource | Resource Group | Purpose |
|---|---|---|
| Azure Container Registry (ACR) | `rg-{AcrName}` (shared) | Stores the Docker images built by CI\CD — shared by dev and prod |
| Container Apps Environment | `rg-{DevEnv}` / `rg-{ProdEnv}` | Runs all MCP server containers (one per environment) |
| Log Analytics Workspace | `rg-{DevEnv}` / `rg-{ProdEnv}` | Collects logs from all containers |
| Application Insights | `rg-{DevEnv}` / `rg-{ProdEnv}` | Distributed traces and metrics |
| Key Vault | `rg-{DevEnv}` / `rg-{ProdEnv}` | Stores per-server secrets |
| Storage Account (ADLS Gen2) | `rg-{DevEnv}` / `rg-{ProdEnv}` | Optional blob export destination |
| User-Assigned Managed Identity | `rg-{DevEnv}` / `rg-{ProdEnv}` | Grants containers access to Key Vault |

This results in **three resource groups**:
- `rg-{AcrName}` — shared Container Registry (created once, reused by both environments)
- `rg-{DevEnv}` — all dev environment resources
- `rg-{ProdEnv}` — all prod environment resources

After provisioning, the agent creates a service principal with the right roles and stores its credentials as GitHub Actions secrets and variables so CI/CD can push images and deploy containers without any manual token management.

---

## Inputs

| Input | Rules | Example |
|---|---|---|
| `DevEnvironmentName` | 5–22 characters, **lowercase letters and digits only**, no hyphens or underscores. Used as the Key Vault name, Container Apps environment name, Log Analytics name, and Storage Account prefix for the dev environment. | `mymcpdev` |
| `ProdEnvironmentName` | Same rules as dev name, must be different. Used for the prod environment resources. | `mymcpprod` |
| `AcrName` | 5–50 alphanumeric characters. Globally unique — used directly as the Azure Container Registry name. A `rg-` prefix is used for the registry resource group. | `mymcpacr` |
| `Location` | Any valid Azure region identifier. | `westeurope` |
| `SubscriptionId` | The GUID of the Azure subscription to deploy into. | `xxxxxxxx-...` |

### Why the naming constraints?

Each environment name is used for Key Vault, Container Apps environment, Log Analytics, and Storage Account (with a `st` prefix). The most restrictive intersection is:

- **Storage Account**: max 24 chars — `st` + name, so max 22 chars for the base
- **Key Vault**: 3–24 alphanumeric and hyphens
- **Container Apps environment**: 2–32 alphanumeric and hyphens

Using 5–22 lowercase alphanumeric characters satisfies all constraints simultaneously. The ACR name has a wider range (5–50 alphanumeric) and is independent of the environment names.

---

## Step-by-step walkthrough

### Step 1 — Collect inputs

The agent asks for `DevEnvironmentName`, `ProdEnvironmentName`, `AcrName`, `Location`, and `SubscriptionId`, then validates them before proceeding.

All other resource names are derived automatically:

| Bicep parameter | Value |
|---|---|
| `acrName` | `{AcrName}` |
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

### Step 2 — Verify prerequisites

The agent checks that `az` (Azure CLI) and `gh` (GitHub CLI) are installed and that both are authenticated (`az account show`, `gh auth status`).

If either check fails the agent stops with instructions — nothing is deployed until prerequisites are met.

### Step 3 — Set active subscription

```
az account set --subscription {SubscriptionId}
```

Ensures subsequent `az` commands target the correct subscription.

### Step 4 — Update Infrastructure/dev.bicepparam and Infrastructure/prod.bicepparam

The agent writes your resolved values into both `Infrastructure/dev.bicepparam` and `Infrastructure/prod.bicepparam`. Both files are committed to the repository and serve as the permanent record of the shared environment configuration. Both reference the same `acrName` and `acrResourceGroupName` to point at the shared registry.

### Step 5 — Deploy shared infrastructure

The GitHub Actions workflow (`.github/workflows/deploy-bicep.yml`) deploys `Infrastructure/main.bicep` **twice** on every push to the `Infrastructure/` folder: once with `dev.bicepparam` and once with `prod.bicepparam`. This creates or updates all three resource groups in a single CI/CD run.

On first run, the dev deployment creates the shared ACR resource group and the ACR itself; the prod deployment reuses the same ACR and adds the prod Container Apps environment identity as an `AcrPull` assignee. Both identity role assignments are idempotent — re-running either deployment never removes the other environment’s access.

You can also run a deployment manually:

```
az deployment sub create \
  --name mcp-dev \
  --location {Location} \
  --template-file Infrastructure/main.bicep \
  --parameters Infrastructure/dev.bicepparam

az deployment sub create \
  --name mcp-prod \
  --location {Location} \
  --template-file Infrastructure/main.bicep \
  --parameters Infrastructure/prod.bicepparam
```

Each deployment takes 3–8 minutes on first run. Uses [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/) for all resources.

### Step 6 — Create service principal

```
az ad sp create-for-rbac --name "sp-mcp-{AcrName}" --json-auth --output json
```

Creates a service principal with client credentials. The `--json-auth` flag produces the JSON structure that `azure/login` and `azure/docker-login` GitHub Actions expect.

The agent captures the JSON **into a shell variable without printing it to the terminal**.

### Step 7 — Assign Owner on the subscription

```
az role assignment create \
  --assignee {clientId} \
  --role Owner \
  --scope /subscriptions/{SubscriptionId}
```

Grants the service principal permission to create resource groups, deploy Bicep templates, and assign roles during deployment (the Bicep template grants `AcrPull` and `AcrPush` inline using `deployer().objectId`).

### Step 8 — Store credentials in GitHub

The service principal JSON is piped **directly** from the shell variable to the GitHub CLI:

```
echo $SP_JSON | gh secret set AZURE_CREDENTIALS --app actions
```

The shared ACR name is stored as a repository variable for both environments (both point to the same registry):

```
gh variable set ACR_NAME --body "{AcrName}"
```

The CI/CD docker-publish template uses the shared `ACR_NAME` variable to push images to the registry for all environments.

### Step 9 — Completion checklist

The agent prints a summary of everything that was done and prompts you to run `/new-mcp-server` next.

---

## Troubleshooting

### Deployment fails with AuthorizationFailed

Your account needs the `Owner` role at subscription scope to create resource groups and assign roles. Check with:

```
az role assignment list --assignee $(az ad signed-in-user show --query id -o tsv) --scope /subscriptions/{SubscriptionId} -o table
```

### Key Vault name is already taken

Key Vault names are globally unique. Choose a different dev or prod environment name. Soft-deleted Key Vaults also reserve the name — you may need to purge a previously deleted vault with:

```
az keyvault purge --name {EnvironmentName} --location {Location}
```

### ACR name is already taken

ACR names are globally unique. Choose a different `AcrName`.

### Role assignment fails with `PrincipalNotFound`

Service principal creation propagates asynchronously in Entra ID. Wait 30–60 seconds and retry.

### `gh secret set` fails

Ensure the GitHub CLI is authenticated to the correct account and organisation with `gh auth status`. If the repository is in an organisation, you may need to grant the CLI access to the org: `gh auth refresh -s admin:org`.

### Container Apps Environment takes too long

The Container Apps Environment provisioning can take up to 10 minutes on first creation. The deployment command waits automatically — do not cancel it.
