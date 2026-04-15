---
mode: agent
description: Scaffold a new MCP Server in this repository. Triggered by "/new-mcp-server".
---

# New MCP Server Scaffold

You are collecting the required inputs and invoking the scaffolding script. Do NOT create any files yourself — the script handles all file generation with token replacement and rollback-on-failure.

---

## Step 1 — Collect inputs

Call the `vscode_askQuestions` tool with exactly these four questions:

```json
{
  "questions": [
    {
      "header": "ServerName",
      "question": "PascalCase name of the new MCP server (e.g. WeatherForecast, PartnerCenter). Used for the folder, namespace, class names, and .csproj.",
      "allowFreeformInput": true
    },
    {
      "header": "AuthType",
      "question": "How does this server call its downstream API? (The MCP server itself is always protected by Entra ID JWT Bearer.)",
      "allowFreeformInput": false,
      "options": [
        {
          "label": "obo",
          "description": "Downstream API uses Entra ID — OBO token exchange on behalf of the signed-in user (e.g. Dynamics CRM, SharePoint, Power BI)"
        },
        {
          "label": "apikey",
          "description": "Downstream API uses a static API key sent as a request header",
          "recommended": true
        },
        {
          "label": "noauth",
          "description": "Downstream API has no authentication (open or internal API)"
        }
      ]
    },
    {
      "header": "ApiConfigSection",
      "question": "Configuration section prefix for the upstream API settings (used when AuthType = apikey or noauth, ignored for obo). Leave blank to auto-derive as {ServerName}Api, e.g. WeatherForecastApi.",
      "allowFreeformInput": true
    },
    {
      "header": "Port",
      "question": "HTTP port the container listens on inside Azure Container Apps. Leave blank to use the default 4547.",
      "allowFreeformInput": true
    }
  ]
}
```

Once the user answers:
- If **Port** is blank, use `4547`.
- If **AuthType** is `obo`, ignore **ApiConfigSection** entirely.
- If **ApiConfigSection** is blank and AuthType is `apikey` or `noauth`, auto-derive as `{ServerName}Api`.

Derive `{{servername}}` = ServerName in all-lowercase (e.g. `WeatherForecast` → `weatherforecast`).

Echo the resolved values in one line before proceeding:
> Scaffolding **{ServerName}** | auth: **{AuthType}** | port: **{Port}**{if apikey or noauth: | config section: {ApiConfigSection}}

---

## Step 2 — Run the scaffolding script

Run the following command in the terminal from the repository root. Build the argument list from the collected inputs:

**Always include:**
```powershell
.\scripts\New-McpServer.ps1 -ServerName {ServerName} -AuthType {AuthType} -Port {Port}
```

**Add `-ApiConfigSection` only when AuthType = `apikey` or `noauth` and the user provided a non-default value:**
```powershell
.\scripts\New-McpServer.ps1 -ServerName {ServerName} -AuthType {AuthType} -Port {Port} -ApiConfigSection {ApiConfigSection}
```

The script will:
- Validate inputs and check for conflicts (duplicate folders, existing files)
- Copy and process auth-variant templates from `.github/templates/mcp-server/`
- Replace all `{{ServerName}}`, `{{servername}}`, `{{Port}}`, and `{{ApiConfigSection}}` tokens
- Add the project to `MCPConcept.slnx`
- Update `.vscode/tasks.json` and `.vscode/launch.json`
- Roll back all created files automatically if any step fails

If the script exits with an error, report the error message to the user as-is — do not attempt to fix the files manually.

---

## Step 3 — Show the next steps

Once the script reports success, display the next steps printed by the script output.
