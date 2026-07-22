# Postman kit (portable)

Generate **Postman Collection v2.1** JSON, a local **environment**, and **flow** collections from one PHP config. Use alongside the curl suites in `api/` — Postman for interactive regression and MCP sync; shell for CI.

## Quick start

```bash
cd /path/to/laravel-api-test-kit

cp postman/config.example.php postman/config.php
# Edit modules, paths, bodies, flows for your Laravel API

npm run postman:generate
# or: php postman/generate-collections.php
```

Outputs:

| Path | Purpose |
|------|---------|
| `postman/collections/api.json` | Main nested collection (Public / Setup / Protected / Flows) |
| `postman/environments/local.environment.json` | Variables (`base_url`, `access_token`, …) |
| `postman/flows/flow-*.json` | Standalone multi-step collections for Collection Runner |

## Import / run

1. Postman → Import the three artifact types above (or sync via [Postman MCP](../docs/POSTMAN_MCP.md)).
2. Select the generated **Local** environment.
3. Set `access_token` (or add a Setup mint request in `config.php`).
4. Run a **Flows** folder or a standalone `flows/*.json` with **Collection Runner**.

> **Localhost + Flows canvas:** Postman cloud Flows cannot call `127.0.0.1`. Use **Collection Runner** in the desktop app, or a tunnel. See [docs/POSTMAN.md](../docs/POSTMAN.md).

## Customize for a new project

See [docs/POSTMAN.md](../docs/POSTMAN.md) and [docs/POSTMAN_CUSTOMIZATION.md](../docs/POSTMAN_CUSTOMIZATION.md).

In short: edit `postman/config.php` (routes, bodies, happy/negative cases, flows) → regenerate → re-import or `putCollection` via MCP.

## Docs index

| Doc | Contents |
|-----|----------|
| [POSTMAN.md](../docs/POSTMAN.md) | Layout, generate commands, runner, tests |
| [POSTMAN_CUSTOMIZATION.md](../docs/POSTMAN_CUSTOMIZATION.md) | Adapt to any Laravel API |
| [POSTMAN_MCP.md](../docs/POSTMAN_MCP.md) | Postman MCP best practices |
| [POSTMAN_JSON_CONTRACT.md](../docs/POSTMAN_JSON_CONTRACT.md) | JSON success/error conventions for assertions |
