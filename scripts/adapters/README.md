# Auth Adapters

The test kit authenticates without driving fragile UI/email flows by default. An **adapter** is a small PHP script that boots your Laravel app and mints a Sanctum personal access token.

## Included adapters

| Adapter | Path | Use when |
|---------|------|----------|
| Finolo | `finolo/mint-token.php` | Finolo modular Laravel app |
| Generic template | `generic/mint-token.php` | Starting point for any Sanctum app |

## Create your adapter

1. Copy `generic/mint-token.php` → `your-app/mint-token.php`
2. Set `User` model namespace and any role/admin logic
3. Point `MINT_TOKEN_SCRIPT` in `config/test.env`

## CLI

```bash
PROJECT_ROOT=/path/to/app php scripts/adapters/finolo/mint-token.php \
  --email=qa@example.com --admin --json
```

## Shell integration

`api-test-helpers.sh` calls this script via `mint_token_for <email> [admin]`.

For HTTP-based auth instead, set `AUTH_STRATEGY=http_login` in `config/test.env`.
