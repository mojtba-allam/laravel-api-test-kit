#!/bin/bash
# Full email-verification flow test — runs ON the server with local DB access.
# Mirrors the Playwright "verified user can access protected pages" test
# without needing a browser. Proves the complete signup → verify → access flow.

set -e

BASE_URL="${BASE_URL:-https://127.0.0.1}"
PHP_BIN="${PHP_BIN:-/usr/local/php82/bin/php}"
APP_DIR="${APP_DIR:-/home/admin/domains/example.com}"
PASS=0
FAIL=0

green() { echo -e "\033[0;32m✓ $1\033[0m"; }
red() { echo -e "\033[0;31m✗ $1\033[0m"; }

assert_status() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then green "$name (HTTP $actual)"; PASS=$((PASS+1));
    else red "$name (expected $expected, got $actual)"; FAIL=$((FAIL+1)); fi
}

EMAIL="flow-test-$(date +%s)-$RANDOM@test.example.com"
PASSWORD="StrongPass123!"

echo "=========================================="
echo "Email Verification Flow — Server Test"
echo "  Email: $EMAIL"
echo "=========================================="

# 1. Register
REG=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/api/v1/auth/register" \
    -H "Accept: application/json" -H "Content-Type: application/json" \
    -d "{\"name\":\"Flow Test\",\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"password_confirmation\":\"$PASSWORD\",\"timezone\":\"UTC\"}")
REG_STATUS=$(echo "$REG" | tail -1)
REG_BODY=$(echo "$REG" | sed '$d')
assert_status "Register new user → 201" "201" "$REG_STATUS"

TOKEN=$(echo "$REG_BODY" | php -r '$d=json_decode(file_get_contents("php://stdin"),true);echo $d["data"]["token"]??"";')
echo "  Token: ${TOKEN:0:12}..."

# 2. Confirm unverified user is BLOCKED from protected endpoint (403)
BLOCKED=$(curl -sk -o /dev/null -w "%{http_code}" -X GET "$BASE_URL/api/v1/projects" \
    -H "Accept: application/json" -H "Authorization: Bearer $TOKEN")
assert_status "Unverified user blocked from /projects → 403" "403" "$BLOCKED"

# 3. /auth/me should still work (no verification required)
ME=$(curl -sk -o /dev/null -w "%{http_code}" -X GET "$BASE_URL/api/v1/auth/me" \
    -H "Accept: application/json" -H "Authorization: Bearer $TOKEN")
assert_status "Unverified user can access /auth/me → 200" "200" "$ME"

# 4. Read the verification code directly from the local database
CODE=$(cd "$APP_DIR" && $PHP_BIN artisan tinker --execute="echo Modules\\User\\Models\\User::where('email','$EMAIL')->value('verification_code');" 2>/dev/null | tr -d '[:space:]' | grep -oE '[0-9]{6}' | head -1)
echo "  Verification code: $CODE"
if [ -n "$CODE" ]; then green "Verification code retrieved from DB"; PASS=$((PASS+1)); else red "Could not read verification code"; FAIL=$((FAIL+1)); fi

# 5. Verify the email with the code
VERIFY=$(curl -sk -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/api/v1/auth/verify-email-code" \
    -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
    -d "{\"code\":\"$CODE\"}")
assert_status "Verify email with code → 200" "200" "$VERIFY"

# 6. Now the verified user CAN access protected endpoints
ALLOWED=$(curl -sk -o /dev/null -w "%{http_code}" -X GET "$BASE_URL/api/v1/projects" \
    -H "Accept: application/json" -H "Authorization: Bearer $TOKEN")
assert_status "Verified user can access /projects → 200" "200" "$ALLOWED"

# 7. Login should now succeed (was blocked before verification)
LOGIN=$(curl -sk -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/api/v1/auth/login" \
    -H "Accept: application/json" -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
assert_status "Verified user can login → 200" "200" "$LOGIN"

# Cleanup: remove the test user
cd "$APP_DIR" && $PHP_BIN artisan tinker --execute="Modules\\User\\Models\\User::where('email','$EMAIL')->forceDelete();" >/dev/null 2>&1

echo "=========================================="
echo "Passed: $PASS  Failed: $FAIL"
echo "=========================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
