# Postman MCP — best practices

Use the [Postman MCP Server](https://learning.postman.com/docs/developer/postman-api/postman-mcp-server/overview/) from Cursor (or another MCP client) to manage workspaces, collections, and environments without leaving the editor.

## Connect (Cursor)

1. Create an API key: Postman → Settings → API keys.
2. Add to `~/.cursor/mcp.json` (or project MCP config):

```json
{
  "mcpServers": {
    "postman": {
      "url": "https://mcp.postman.com/mcp",
      "headers": {
        "Authorization": "Bearer PMAK-xxxxxxxx"
      }
    }
  }
}
```

3. Reload MCP tools; confirm server status is ready.
4. Prefer **full** mode (`https://mcp.postman.com/mcp`) when creating workspaces and replacing collections.

Never commit API keys. Rotate if pasted into chat logs.

## Recommended workflow with this kit

```text
edit postman/config.php
        ↓
npm run postman:generate
        ↓
MCP: createWorkspace (once) / createEnvironment / createCollection or putCollection
        ↓
Human: Collection Runner against local artisan serve
```

| Task | MCP tool | Notes |
|------|----------|-------|
| New workspace | `createWorkspace` | `type: personal` (or `team` if plan allows) |
| List workspaces | `getWorkspaces` | Always pass workspace IDs explicitly later |
| Upload env | `createEnvironment` | Pass `workspace` + `name` + `values` |
| First upload collection | `createCollection` | Schema is strict; large nested collections often fail validation |
| Replace collection | `putCollection` | Prefer after create; or use Postman REST API with full JSON |
| Verify | `getCollections` / `getEnvironments` | Confirm names in the target workspace |

### Large generated collections

MCP `createCollection` / `putCollection` schemas often reject deep Collection v2.1 trees (`additionalProperties` constraints). Practical pattern:

1. `createWorkspace` via MCP.
2. Upload `collections/api.json` and `environments/*.json` with the **Postman REST API** (`POST https://api.getpostman.com/collections?workspace=…` + `X-Api-Key`), still using the same API key as MCP.
3. Use MCP afterward for list / rename / comment / delete.

Keep **flow runner sequences** as Collection folders or standalone collections — MCP has **no** `createFlow` for the visual Flows product, and cloud Flows cannot hit localhost.

## Do / don't

**Do**

- Generate from `config.php`, then sync — don’t hand-edit huge JSON in Postman as source of truth
- Scope every call with a `workspace` id
- Put secrets only in environment `type: secret` values
- Re-run generate + replace after route changes

**Don't**

- Expect visual **Flows** to appear from importing collection JSON
- Run cloud Flows against `127.0.0.1` (error: *localhost request not supported*)
- Store the API key in the test-kit repo
- Duplicate product names into the kit — keep `collection_name` / modules generic or project-local in *your* `config.php`

## Localhost testing reminder

| Surface | Hits localhost? |
|---------|-----------------|
| Postman Desktop → Collection Runner | Yes |
| Postman Desktop → single request | Yes |
| Postman web / cloud Flows runtime | No — use tunnel or Runner |

## Prompt examples for the agent

- “Using Postman MCP, create a personal workspace named API Test Kit and list its id.”
- “Replace collection X in workspace Y with `postman/collections/api.json`.”
- “Create environment Local in workspace Y from `postman/environments/local.environment.json`.”
