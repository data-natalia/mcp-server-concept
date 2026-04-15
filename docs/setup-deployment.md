# Setup Deployment

This guide explains what the `/setup-deployment` Copilot agent command does and walks through each step.

Run it once per deployment ring to provision the shared Azure infrastructure and wire it to GitHub Actions.

---

## What it does

`/setup-deployment` provisions the shared resources that every MCP server in this repository depends on:

| Resource | Purpose |
|---|---|
| Resource Group | Container for all environment resources |
| Azure Container Registry (ACR) | Stores the Docker images built by CI/CD |
| Container Apps Environment | Runs all MCP server containers |
| Log Analytics Workspace | Collects logs from all containers |
| Application Insights | Distributed traces and metrics (linked to Log Analytics) |
| Key Vault | Stores per-server secrets (API keys, client credentials) |
| Storage Account (ADLS Gen2) | Optional blob export destination for MCP tools |
| User-Assigned Managed Identity | Used by Container Apps to pull secrets from Key Vault |

After provisioning, it creates a service principal with the right roles and stores its credentials as GitHub Actions secrets and variables so CI/CD can push images and deploy containers without any manual token management.

---

## Inputs

| Input | Rules | Example |
|---|---|---|
| `EnvironmentName` | 5–22 characters, **lowercase letters and digits only**, no hyphens or underscores. Used directly as the ACR name, Key Vault name, Container Apps environment name, and Log Analytics name. A `st` prefix is prepended for the Storage Account name (`st{EnvironmentName}` — max 24 chars total). | `mymcpenv` |
| `Location` | Any valid Azure region identifier. | `westeurope` |
| `SubscriptionId` | The GUID of the Azure subscription to deploy into. | `xxxxxxxx-...` |

### Why the naming constraint?

The same short name is used as-is for several resource types that each have different naming rules. The most restrictive intersection is:

- **ACR**: 5–50 alphanumeric (minimum 5 chars)
- **Storage Account**: 3–24 lowercase alphanumeric (max 24 chars, but `st` + name is used here, so max 22 chars for the base name)
- **Key Vault**: 3–24 alphanumeric and hyphens

Using 5–22 lowercase alphanumeric characters satisfies all constraints simultaneously.

---

## Step-by-step walkthrough

### Step 1 — Collect inputs

The agent asks for `EnvironmentName`, `Location`, and `SubscriptionId`, then validates them before proceeding.

All other resource names are derived automatically:

| Bicep parameter | Value |
|---|---|
| `acrName` | `{EnvironmentName}` |
| `containerAppsEnvName` | `{EnvironmentName}` |
| `keyVaultName` | `{EnvironmentName}` |
| `logAnalyticsName` | `{EnvironmentName}` |
| `storageAccountName` | `st{EnvironmentName}` |
| `resourceGroupName` | `rg-{EnvironmentName}` |

### Step 2 — Verify prerequisites

The agent checks that `az` (Azure CLI) and `gh` (GitHub CLI) are installed and that both are authenticated (`az account show`, `gh auth status`).

If either check fails the agent stops with instructions — nothing is deployed until prerequisites are met.

### Step 3 — Set active subscription

```
az account set --subscription {SubscriptionId}
```

Ensures subsequent `az` commands target the correct subscription.

### Step 4 — Update Infrastructure/dev.bicepparam

The agent writes your resolved values into `Infrastructure/dev.bicepparam`. This file is committed to the repository and serves as the permanent record of the shared environment configuration.

### Step 5 — Deploy shared infrastructure

```
az deployment sub create \
  --name mcp-shared-env \
  --location {Location} \
  --template-file Infrastructure/main.bicep \
  --parameters Infrastructure/dev.bicepparam
```

Subscription-scope Bicep deployment. Takes 3–8 minutes on first run. Uses [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/) for all resources.

### Step 6 — Create service principal

```
az ad sp create-for-rbac --name "sp-mcp-{EnvironmentName}" --json-auth --output json
```

Creates a service principal with client credentials. The `--json-auth` flag (previously `--sdk-auth` in older Azure CLI versions) produces the JSON structure that `azure/login` and `azure/docker-login` GitHub Actions expect.

The agent captures the JSON **into a shell variable without printing it to the terminal**. This prevents the client secret from appearing in terminal history or VS Code output panels.

### Step 7 — Assign AcrPush on the Container Registry

```
az role assignment create \
  --assignee {clientId} \
  --role AcrPush \
  --scope {acrResourceId}
```

Grants the service principal permission to push Docker images to the ACR. This is the only permission needed for image builds.

### Step 8 — Assign Contributor on the subscription

```
az role assignment create \
  --assignee {clientId} \
  --role Contributor \
  --scope /subscriptions/{SubscriptionId}
```

Grants the service principal permission to create and update Container App resources via Bicep deployments. Scoped to the subscription so it can create resource groups and deployments.

### Step 9 — Store credentials in GitHub

This is the most security-sensitive step. The service principal JSON (containing the client secret) is piped **directly** from the shell variable to the GitHub CLI:

```
echo $SP_JSON | gh secret set AZURE_CREDENTIALS --app actions
```

**Why piping is secure:** The credentials travel from the in-memory shell variable, through a pipe, directly to the GitHub CLI which encrypts and uploads them. They are never written to disk, never printed to the terminal, and never appear in shell history. The `SP_JSON` variable is cleared immediately after.

The ACR name is also stored as a repository variable for both environments:

```
gh variable set ACR_NAME_DEV --body "{EnvironmentName}"
gh variable set ACR_NAME_PROD --body "{EnvironmentName}"
```

The CI/CD template selects the right ACR automatically: branches named `main` use `ACR_NAME_PROD`, all other branches use `ACR_NAME_DEV`.

### Step 10 — Completion checklist

The agent prints a summary of everything that was done and prompts you to run `/new-mcp-server` next.

---

## Troubleshooting

### `az deployment sub create` fails with AuthorizationFailed

Your account needs the `Owner` or `Contributor` role at subscription scope to create resource groups and assign roles. Check with:

```
az role assignment list --assignee $(az ad signed-in-user show --query id -o tsv) --scope /subscriptions/{SubscriptionId} -o table
```

### Key Vault name is already taken

Key Vault names are globally unique. If `{EnvironmentName}` is taken, choose a different environment name. Soft-deleted Key Vaults also reserve the name — you may need to purge a previously deleted vault with:

```
az keyvault purge --name {EnvironmentName} --location {Location}
```

### ACR name is already taken

ACR names are globally unique. Choose a different environment name.

### Role assignment fails with `PrincipalNotFound`

Service principal creation propagates asynchronously in Entra ID. Wait 30–60 seconds after Step 6 and retry the role assignment step.

### `gh secret set` fails

Ensure the GitHub CLI is authenticated to the correct account and organisation with `gh auth status`. If the repository is in an organisation, you may need to grant the CLI access to the org: `gh auth refresh -s admin:org`.

### Container Apps Environment takes too long

The Container Apps Environment provisioning can take up to 10 minutes on first creation. The `az deployment sub create` command waits automatically — do not cancel it.
