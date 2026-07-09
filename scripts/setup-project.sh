#!/bin/bash
# Quick setup: copy env template and verify prerequisites.

set -e

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KIT_ROOT"

echo "Laravel API Test Kit — setup"
echo "============================"

if [ ! -f config/test.env ]; then
  cp config/test.env.example config/test.env
  echo "Created config/test.env — edit PROJECT_ROOT before running tests"
else
  echo "config/test.env already exists"
fi

# shellcheck source=../config/bootstrap.sh
source config/bootstrap.sh

echo ""
echo "Project:  $PROJECT_ROOT"
echo "API URL:  $BASE_URL"
echo "Adapter:  $MINT_TOKEN_SCRIPT"
echo ""

missing=0
command -v curl >/dev/null || { echo "✗ curl not found"; missing=1; }
command -v php >/dev/null || { echo "✗ php not found"; missing=1; }
[ -f "$PROJECT_ROOT/artisan" ] || { echo "✗ Laravel app not found at PROJECT_ROOT"; missing=1; }

if [ $missing -eq 0 ]; then
  echo "✓ Prerequisites OK"
  echo ""
  echo "Run API tests:  ./api/run-all-api-tests.sh"
  echo "Run one suite:  ./api/test-workspace-api.sh"
  echo "Run E2E:        npm install && npx playwright test"
fi
