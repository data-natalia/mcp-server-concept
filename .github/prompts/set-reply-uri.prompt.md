---
mode: agent
description: Add a reply URI (web redirect URI) to an app registration. Triggered by "/set-reply-uri".
---

# Set Reply URI

You are adding a web reply URI (redirect URI) to an app registration for OAuth 2.0 flows. Follow EVERY step exactly. Do NOT skip steps or reorder them.

Use only these scripts for execution logic:
- `scripts/Validate-ProvisioningEnvironment.ps1`
- `scripts/Set-ReplyUri.ps1`

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

Print:
> ✅ Azure CLI authenticated to subscription: **{currentSubscriptionName}** ({currentSubscriptionId})

Print:
> ✅ You have the required Entra ID role to update app registrations.

---

## Step 1 — Collect inputs

Call the `vscode_askQuestions` tool with exactly these two questions:

```json
{
  "questions": [
    {
      "header": "AppDisplayName",
      "question": "Display name of the app registration to update (e.g. agent-WeatherForecast, mcp-PartnerCenter).",
      "allowFreeformInput": true
    },
    {
      "header": "ReplyUri",
      "question": "Web reply URI to add (e.g. https://myapp.azurewebsites.net/auth/callback).",
      "allowFreeformInput": true
    }
  ]
}
```

Validate the inputs:
- **AppDisplayName** must be a non-empty string. If empty, stop and ask the user to provide one.
- **ReplyUri** must start with `https://`. If it does not, stop and ask the user to correct it.

### Look up app registrations by display name

Run:

```powershell
az ad app list --filter "displayName eq '{AppDisplayName}'" --query "[].{appId:appId, displayName:displayName, objectId:id}" -o json
```

Parse the result as `matchingApps`.

- If **0 results**: stop and print:
  > ❌ No app registration found with display name '{AppDisplayName}'. Verify the name and try again.

- If **1 result**: use `matchingApps[0].appId` as `appId` and `matchingApps[0].displayName` as `resolvedDisplayName`.

- If **more than 1 result**: call `vscode_askQuestions` to disambiguate. Build options from `matchingApps`, showing display name and appId for each:

  ```json
  {
    "questions": [
      {
        "header": "TargetApp",
        "question": "Multiple app registrations found with that name. Which one do you want to update?",
        "allowFreeformInput": false,
        "options": [
          { "label": "{matchingApps[0].displayName} ({matchingApps[0].appId})" },
          { "label": "{matchingApps[1].displayName} ({matchingApps[1].appId})" },
          ...
        ]
      }
    ]
  }
  ```

  Extract the GUID from the selected option and use it as `appId`.

---

## Step 2 — Execute script

Run:

```powershell
pwsh -NoProfile -File .\scripts\Set-ReplyUri.ps1 -AppId "{appId}" -ReplyUri "{ReplyUri}"
```

The script returns JSON. Parse it into `result`.

If command fails, or `result.success` is `false`, stop and print:
> ❌ {result.errorMessage}

Capture from result:
- `status = result.status`
- `displayName = result.displayName`
- `redirectUris = result.redirectUris`

---

## Step 3 — Print completion

If `status` is `already_exists`, print:
> ℹ️ Reply URI '{ReplyUri}' already exists on '{displayName}'. No changes made.

If `status` is `added`, print:

```
✅ Reply URI added to app registration '{displayName}' ({appId})
```

Then print the full updated list:
```
Web reply URIs:
```
Followed by each URI in `redirectUris` as a bullet point.

Print:
> **Next step:** Users will be redirected to '{ReplyUri}' when they complete OAuth 2.0 authentication.
