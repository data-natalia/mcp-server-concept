# Setup Deployment

This guide explains what the `/setup-deployment` Copilot agent command does and walks through each step.

Run it **once** to provision the full shared Azure infrastructure — a dedicated registry resource group plus separate dev and prod environment resource groups — and wire everything to GitHub Actions.

---

## Prerequisites

Before running `/setup-deployment`, ensure you are working in **your own repository** — not `atea/mcp-server-concept`.

The source project lives at `atea/mcp-server-concept`. All deployments must target a separate repository in your own organisation (e.g. `acme/mcp-server-concept` or `acme/my-mcp-project`). The setup agent automatically detects the target repository from the current working directory. If it resolves to `atea/mcp-server-concept`, you will be prompted to provide the correct `org/repo-name` before any deployment or credential step proceeds. The value `atea/mcp-server-concept` is rejected as a target at every step — in both the prompt and the scripts.

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

The agent checks that `az` (Azure CLI) and `gh` (GitHub CLI) are installed and that both are authenticated (`az account show`, `gh auth status`). It also verifies you have an Entra ID role (Application Developer, Application Administrator, or Global Administrator) in the current tenant.

It also detects the target GitHub repository from the current directory using `gh repo view`. If the detected repository is `atea/mcp-server-concept` or cannot be determined, you will be asked to enter your organisation's repository (`org/repo-name`) before proceeding. The value `atea/mcp-server-concept` is never accepted as a deployment target.

If either check fails the agent stops with instructions — nothing is deployed until prerequisites are met.

### Step 3 — Configure Bicep parameter files

Runs `scripts/Set-BicepParams.ps1`, which:

1. Sets the active Azure subscription: `az account set --subscription {SubscriptionId}`
2. Writes the resolved values into `Infrastructure/dev.bicepparam` and `Infrastructure/prod.bicepparam`

Both files are committed to the repository and serve as the permanent record of the shared environment configuration. Both reference the same `acrName` and `acrResourceGroupName` so dev and prod share a single registry.

### Step 4 — Create service principal and store credentials

Runs `scripts/Set-DeploymentCredentials.ps1 -AcrName {AcrName} -SubscriptionId {SubscriptionId} -RepoNameWithOwner {RepoNameWithOwner}`, which:

1. **Creates or resets** the service principal `sp-mcp-{AcrName}` — idempotent: reuses an existing SP and resets its credentials if one already exists
2. **Assigns Owner** role on subscription `{SubscriptionId}` — skipped if already assigned
3. **Stores credentials** in your repository, explicitly pinned to `{RepoNameWithOwner}`:

```
gh secret set AZURE_CREDENTIALS --app actions --repo {RepoNameWithOwner}
gh variable set ACR_NAME --body "{AcrName}" --repo {RepoNameWithOwner}
```

Credentials are piped directly from memory — never written to disk or printed to the terminal. The Owner role is required because the Bicep template assigns `AcrPull` and `AcrPush` roles inline during deployment using `deployer().objectId`.

### Step 5 — Copy workflow templates

Copies the three GitHub Actions workflow templates from `.github/templates/` to `.github/workflows/`:

| Template | Purpose |
|---|---|
| `deploy-bicep.yml` | Deploys Bicep infrastructure on pushes to `Infrastructure/` |
| `docker-publish-template.yml` | Builds and pushes Docker images to ACR |
| `docker-deploy-containerapp-template.yml` | Updates Container App revisions |

### Step 6 — Commit and push to trigger deployment

```
git add Infrastructure/dev.bicepparam Infrastructure/prod.bicepparam .github/workflows/
git commit -m "Configure MCP environments: {DevEnvironmentName} (dev) and {ProdEnvironmentName} (prod) with shared registry {AcrName}"
git push origin main
```

This pushes to your own repository (`{RepoNameWithOwner}`), not the source repository. It triggers the **Deploy Bicep Template** workflow, which deploys `Infrastructure/main.bicep` twice — once with `dev.bicepparam` and once with `prod.bicepparam` — creating all three resource groups.

On first run, the dev deployment creates the shared ACR and its resource group; the prod deployment reuses the same ACR and adds the prod Container Apps identity as an `AcrPull` assignee. Both role assignments are idempotent — re-running never removes the other environment's access.

Each deployment takes 3–8 minutes on first run. Uses [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/) for all resources.

### Step 7 — Completion checklist

The agent prints a summary of every action completed:

```
✅ Infrastructure/dev.bicepparam updated
✅ Infrastructure/prod.bicepparam updated
✅ Service principal sp-mcp-{AcrName} created or updated
✅ Owner role assigned to SP on subscription {SubscriptionId}
✅ AZURE_CREDENTIALS secret set in GitHub Actions
✅ ACR_NAME variable set to {AcrName}
✅ Workflow templates copied to .github/workflows/
✅ Changes committed and pushed to main branch
```

#### Manual deployment option

If you need to deploy infrastructure without pushing to GitHub:

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
