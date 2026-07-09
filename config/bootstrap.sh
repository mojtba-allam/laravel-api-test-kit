#!/bin/bash
# =============================================================================
# bootstrap.sh — Load test-kit configuration before any suite runs.
#
# Usage (from api/*.sh):
#   source "$(dirname "${BASH_SOURCE[0]}")/../config/bootstrap.sh"
#
# Or from api-test-helpers.sh (auto-sourced).
# =============================================================================

if [ -n "${TEST_KIT_BOOTSTRAPPED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
TEST_KIT_BOOTSTRAPPED=1

# Resolve test-kit root from this file's location (config/bootstrap.sh → parent dir)
_BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_KIT_ROOT="$(cd "$_BOOTSTRAP_DIR/.." && pwd)"
unset _BOOTSTRAP_DIR

# Load project-specific env (copy test.env.example → test.env first)
if [ -f "$TEST_KIT_ROOT/config/test.env" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$TEST_KIT_ROOT/config/test.env"
    set +a
fi

# Required: path to the Laravel application under test
if [ -z "${PROJECT_ROOT:-}" ]; then
    echo "ERROR: PROJECT_ROOT is not set." >&2
    echo "  1. cp config/test.env.example config/test.env" >&2
    echo "  2. Set PROJECT_ROOT=/path/to/your/laravel-app" >&2
    exit 1
fi

if [ ! -f "$PROJECT_ROOT/artisan" ]; then
    echo "ERROR: PROJECT_ROOT ($PROJECT_ROOT) does not look like a Laravel app (artisan missing)." >&2
    exit 1
fi

# Defaults (override in config/test.env)
export TEST_KIT_ROOT
export PROJECT_ROOT
export BASE_URL="${BASE_URL:-http://127.0.0.1:8000/api/v1}"
export APP_URL="${APP_URL:-${BASE_URL%/api/v*}}"
export API_PREFIX="${API_PREFIX:-/api/v1}"
export PHP_BIN="${PHP_BIN:-php}"
export TEST_EMAIL_DOMAIN="${TEST_EMAIL_DOMAIN:-test.example.com}"
export AUTH_STRATEGY="${AUTH_STRATEGY:-mint_token}"
export MINT_TOKEN_SCRIPT="${MINT_TOKEN_SCRIPT:-$TEST_KIT_ROOT/scripts/adapters/finolo/mint-token.php}"
export JSON_ID_PATH="${JSON_ID_PATH:-data.id}"
export SEED_COMMAND="${SEED_COMMAND:-db:seed}"
export CURL_INSECURE="${CURL_INSECURE:-1}"

# Curl TLS flag (-k when testing local/self-signed)
if [ "$CURL_INSECURE" = "1" ]; then
    export CURL_TLS_FLAG="-k"
else
    export CURL_TLS_FLAG=""
fi
