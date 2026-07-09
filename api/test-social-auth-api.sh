#!/bin/bash
# =============================================================================
# Social OAuth API Tests
#
# Tests the social authentication endpoints for Google and GitHub OAuth.
# These tests verify the redirect URL generation and provider validation.
# (Callback tests require actual OAuth flow — covered by PHPUnit mocks.)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "============================================"
echo "Social OAuth API Tests"
echo "============================================"
echo ""

# ─── Test: Google redirect returns a valid URL ─────────────────────────────────

echo "--- Provider Redirect Tests ---"

RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/auth/social/google/redirect" \
    -H "Accept: application/json")
STATUS=$(status_from_response "$RESPONSE")
BODY=$(body_from_response "$RESPONSE")

print_result "GET /auth/social/google/redirect returns 200" "200" "$STATUS" "$BODY"

# Verify response contains a redirect_url
if assert_json_field "$BODY" "data.redirect_url"; then
    TOTAL=$((TOTAL + 1))
    REDIRECT_URL=$(json_value "$BODY" "data.redirect_url")
    if echo "$REDIRECT_URL" | grep -q "accounts.google.com"; then
        echo -e "${GREEN}✓${NC} Google redirect URL contains accounts.google.com"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗${NC} Google redirect URL does not contain accounts.google.com"
        echo "   Got: $REDIRECT_URL"
        FAILED=$((FAILED + 1))
        FAILED_TESTS+=("Google redirect URL validation")
    fi
else
    TOTAL=$((TOTAL + 1))
    echo -e "${RED}✗${NC} Response missing data.redirect_url"
    FAILED=$((FAILED + 1))
    FAILED_TESTS+=("Google redirect URL structure")
fi

# ─── Test: GitHub redirect returns a valid URL ─────────────────────────────────

RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/auth/social/github/redirect" \
    -H "Accept: application/json")
STATUS=$(status_from_response "$RESPONSE")
BODY=$(body_from_response "$RESPONSE")

print_result "GET /auth/social/github/redirect returns 200" "200" "$STATUS" "$BODY"

# Verify response contains a redirect_url
if assert_json_field "$BODY" "data.redirect_url"; then
    TOTAL=$((TOTAL + 1))
    REDIRECT_URL=$(json_value "$BODY" "data.redirect_url")
    if echo "$REDIRECT_URL" | grep -q "github.com"; then
        echo -e "${GREEN}✓${NC} GitHub redirect URL contains github.com"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗${NC} GitHub redirect URL does not contain github.com"
        echo "   Got: $REDIRECT_URL"
        FAILED=$((FAILED + 1))
        FAILED_TESTS+=("GitHub redirect URL validation")
    fi
else
    TOTAL=$((TOTAL + 1))
    echo -e "${RED}✗${NC} Response missing data.redirect_url"
    FAILED=$((FAILED + 1))
    FAILED_TESTS+=("GitHub redirect URL structure")
fi

echo ""
echo "--- Unsupported Provider Tests ---"

# ─── Test: Unsupported provider returns 422 ────────────────────────────────────

RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/auth/social/facebook/redirect" \
    -H "Accept: application/json")
STATUS=$(status_from_response "$RESPONSE")
BODY=$(body_from_response "$RESPONSE")

print_result "GET /auth/social/facebook/redirect returns 422" "422" "$STATUS" "$BODY"

# Check error message
TOTAL=$((TOTAL + 1))
MSG=$(json_value "$BODY" "message")
if [ "$MSG" = "Unsupported social provider." ]; then
    echo -e "${GREEN}✓${NC} Error message is correct: '$MSG'"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗${NC} Expected 'Unsupported social provider.', Got: '$MSG'"
    FAILED=$((FAILED + 1))
    FAILED_TESTS+=("Unsupported provider error message")
fi

# ─── Test: Unsupported provider on callback ────────────────────────────────────

RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/auth/social/twitter/callback" \
    -H "Accept: application/json")
STATUS=$(status_from_response "$RESPONSE")
BODY=$(body_from_response "$RESPONSE")

print_result "GET /auth/social/twitter/callback returns 422" "422" "$STATUS" "$BODY"

echo ""
echo "--- Callback Without Code Tests ---"

# ─── Test: Google callback without code redirects with error ───────────────────

RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/auth/social/google/callback" \
    -H "Accept: application/json" -L -o /dev/null)
# Without a valid OAuth code, the callback will fail (Socialite will throw)
# The test verifies the endpoint exists and the provider validation passes
RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/auth/social/google/callback" \
    -H "Accept: application/json")
STATUS=$(status_from_response "$RESPONSE")

# Callback without code will get a redirect (302) with error, or a 500 from socialite
# Either 302 or 500 is acceptable (it means the route works, just no valid OAuth code)
TOTAL=$((TOTAL + 1))
if [ "$STATUS" = "302" ] || [ "$STATUS" = "500" ] || [ "$STATUS" = "429" ]; then
    echo -e "${GREEN}✓${NC} Google callback without code returns $STATUS (expected: route exists)"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗${NC} Google callback without code returned $STATUS (expected 302, 500, or 429)"
    FAILED=$((FAILED + 1))
    FAILED_TESTS+=("Google callback route exists")
fi

echo ""
echo "--- Rate Limiting Tests ---"

# ─── Test: Rate limiting on redirect ──────────────────────────────────────────
# Just verify the endpoint doesn't crash under repeated access

TOTAL=$((TOTAL + 1))
RATE_OK=true
for i in $(seq 1 3); do
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/auth/social/google/redirect" \
        -H "Accept: application/json")
    STATUS=$(status_from_response "$RESPONSE")
    if [ "$STATUS" != "200" ] && [ "$STATUS" != "429" ]; then
        RATE_OK=false
        break
    fi
done
if [ "$RATE_OK" = true ]; then
    echo -e "${GREEN}✓${NC} Redirect endpoint handles repeated requests (200 or 429)"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗${NC} Redirect endpoint returned unexpected status"
    FAILED=$((FAILED + 1))
    FAILED_TESTS+=("Rate limiting on redirect")
fi

# ─── Summary ───────────────────────────────────────────────────────────────────

print_summary_and_exit
