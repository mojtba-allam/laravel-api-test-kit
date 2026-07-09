# Auth Adapters

The test kit authenticates without driving fragile UI/email flows by default. An **adapter** is a small PHP script that boots your Laravel app and mints a Sanctum personal access token.

## Included adapters

| Adapter | Path | Use when |
|---------|------|----------|
| Generic | `generic/mint-token.php` | Standard Laravel + `App\Models\User` |
| Laravel modules | `laravel-modules/mint-token.php` | Modular apps (`Modules\User\Models\User`, etc.) |

## Create your adapter

1. Copy `generic/mint-token.php` → `your-app/mint-token.php`
2. Set `User` model namespace and any role/admin logic
3. Point `MINT_TOKEN_SCRIPT` in `config/test.env`

## CLI

```bash
PROJECT_ROOT=/path/to/app php scripts/adapters/generic/mint-token.php \
  --email=qa@example.com --admin --json
```

## Shell integration

`api-test-helpers.sh` calls this script via `mint_token_for <email> [admin]`.

For HTTP-based auth instead, set `AUTH_STRATEGY=http_login` in `config/test.env`.
