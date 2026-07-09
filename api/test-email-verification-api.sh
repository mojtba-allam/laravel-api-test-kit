#!/bin/bash

# Finolo Email Verification API Test Suite
# Tests complete signup flow with email verification
# Uses MAIL_MAILER=log to capture verification codes from log output

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "=========================================="
echo "Email Verification API Test Suite"
echo "=========================================="
echo ""

# ==========================================
# Helper: Extract verification code from Laravel log
# ==========================================
LARAVEL_LOG="$PROJECT_ROOT/storage/logs/laravel.log"

get_verification_code_from_log() {
    local email="$1"
    # The code is in the HTML body with letter-spacing style
    grep "letter-spacing" "$LARAVEL_LOG" 2>/dev/null | grep -oP '\d{6}' | tail -1
}

# ==========================================
# Setup: Switch to log mailer for testing
# ==========================================
echo "Setting up test environment (using log mailer for email capture)..."

# Temporarily switch to log mailer via env override in the artisan serve process
# We'll read the code from the Laravel log file
echo ""

# Truncate log for clean test
> "$LARAVEL_LOG" 2>/dev/null || true

# ==========================================
# Section 1: Complete Registration Flow
# ==========================================
echo "=========================================="
echo "Section 1: Complete Registration Flow"
echo "=========================================="
echo ""

TEST_EMAIL="e2e-verify-$(date +%s)-$RANDOM@example.com"
TEST_PASSWORD="TestPass123!"

# Test 1: Register new user
echo "Test 1: Registering new user ($TEST_EMAIL)..."
REGISTER_RESPONSE=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/auth/register" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{
        \"name\": \"E2E Test User\",
        \"email\": \"$TEST_EMAIL\",
        \"password\": \"$TEST_PASSWORD\",
        \"password_confirmation\": \"$TEST_PASSWORD\",
        \"timezone\": \"UTC\"
    }")

REGISTER_STATUS=$(status_from_response "$REGISTER_RESPONSE")
REGISTER_BODY=$(body_from_response "$REGISTER_RESPONSE")

print_result "POST /auth/register → 201 creates user" "201" "$REGISTER_STATUS" "$REGISTER_BODY"

if [ "$REGISTER_STATUS" != "201" ]; then
    echo -e "${RED}Registration failed. Stopping test.${NC}"
    echo "Response: $REGISTER_BODY"
    exit 1
fi

# Extract the token (used to verify email)
USER_TOKEN=$(json_value "$REGISTER_BODY" "data.token")
if [ -z "$USER_TOKEN" ]; then
    USER_TOKEN=$(json_value "$REGISTER_BODY" "token")
fi
echo "  Token obtained: ${USER_TOKEN:0:20}..."
echo ""

# Test 2: Login should be blocked (email not verified)
echo "Test 2: Attempting login before email verification..."
LOGIN_BEFORE_VERIFY=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/auth/login" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{
        \"email\": \"$TEST_EMAIL\",
        \"password\": \"$TEST_PASSWORD\"
    }")

LOGIN_BEFORE_STATUS=$(status_from_response "$LOGIN_BEFORE_VERIFY")
print_result "POST /auth/login (unverified) → 401 blocked" "401" "$LOGIN_BEFORE_STATUS" "$(body_from_response "$LOGIN_BEFORE_VERIFY")"
echo ""

# Test 3: Get verification code from log
echo "Test 3: Retrieving verification code from email log..."
sleep 1

VERIFICATION_CODE=$(get_verification_code_from_log "$TEST_EMAIL")

if [ -z "$VERIFICATION_CODE" ]; then
    # Fallback: get from log using broader search
    VERIFICATION_CODE=$(grep "letter-spacing" "$LARAVEL_LOG" 2>/dev/null | grep -oP '\d{6}' | tail -1)
fi

if [ -z "$VERIFICATION_CODE" ]; then
    echo -e "${RED}✗${NC} Could not find verification code in log"
    echo "Log tail:"
    tail -20 "$LARAVEL_LOG" 2>/dev/null
    exit 1
fi

echo -e "${GREEN}✓${NC} Verification code from email: $VERIFICATION_CODE"
TOTAL=$((TOTAL + 1))
PASSED=$((PASSED + 1))
echo ""

# Test 4: Verify email with correct code
echo "Test 4: Verifying email with code..."
VERIFY_RESPONSE=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/auth/verify-email-code" \
    -H "Authorization: Bearer $USER_TOKEN" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{\"code\": \"$VERIFICATION_CODE\"}")

VERIFY_STATUS=$(status_from_response "$VERIFY_RESPONSE")
VERIFY_BODY=$(body_from_response "$VERIFY_RESPONSE")

print_result "POST /auth/verify-email-code → 200 verifies email" "200" "$VERIFY_STATUS" "$VERIFY_BODY"

# Verify the response contains email_verified_at
VERIFIED_AT=$(json_value "$VERIFY_BODY" "data.email_verified_at")
if [ -n "$VERIFIED_AT" ] && [ "$VERIFIED_AT" != "null" ]; then
    echo "  email_verified_at: $VERIFIED_AT"
fi
echo ""

# Test 5: Login should succeed after verification
echo "Test 5: Logging in after email verification..."
LOGIN_AFTER_VERIFY=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/auth/login" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{
        \"email\": \"$TEST_EMAIL\",
        \"password\": \"$TEST_PASSWORD\"
    }")

LOGIN_AFTER_STATUS=$(status_from_response "$LOGIN_AFTER_VERIFY")
LOGIN_AFTER_BODY=$(body_from_response "$LOGIN_AFTER_VERIFY")

print_result "POST /auth/login (verified) → 200 success" "200" "$LOGIN_AFTER_STATUS" "$LOGIN_AFTER_BODY"

# Verify token is returned
LOGIN_TOKEN=$(json_value "$LOGIN_AFTER_BODY" "data.token")
if [ -n "$LOGIN_TOKEN" ]; then
    echo "  Login token: ${LOGIN_TOKEN:0:20}..."
fi
echo ""

# ==========================================
# Section 2: Resend Verification Code
# ==========================================
echo "=========================================="
echo "Section 2: Resend & Re-verify Flow"
echo "=========================================="
echo ""

# Register a second user for resend testing
TEST_EMAIL_2="e2e-resend-$(date +%s)-$RANDOM@example.com"

REGISTER_2=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/auth/register" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{
        \"name\": \"Resend Test User\",
        \"email\": \"$TEST_EMAIL_2\",
        \"password\": \"$TEST_PASSWORD\",
        \"password_confirmation\": \"$TEST_PASSWORD\"
    }")

REGISTER_2_STATUS=$(status_from_response "$REGISTER_2")
USER_TOKEN_2=$(json_value "$(body_from_response "$REGISTER_2")" "data.token")

if [ "$REGISTER_2_STATUS" == "201" ] && [ -n "$USER_TOKEN_2" ]; then
    # Truncate log to isolate new code
    > "$LARAVEL_LOG" 2>/dev/null || true
    sleep 1
    
    # Resend verification
    RESEND_RESPONSE=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/auth/resend-verification" \
        -H "Authorization: Bearer $USER_TOKEN_2" \
        -H "Accept: application/json")

    RESEND_STATUS=$(status_from_response "$RESEND_RESPONSE")
    print_result "POST /auth/resend-verification → 200 resends" "200" "$RESEND_STATUS" "$(body_from_response "$RESEND_RESPONSE")"
    
    # Get new code and verify
    sleep 1
    NEW_CODE=$(get_verification_code_from_log "$TEST_EMAIL_2")
    if [ -z "$NEW_CODE" ]; then
        NEW_CODE=$(grep "letter-spacing" "$LARAVEL_LOG" 2>/dev/null | grep -oP '\d{6}' | tail -1)
    fi
    
    if [ -n "$NEW_CODE" ]; then
        VERIFY_2=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/auth/verify-email-code" \
            -H "Authorization: Bearer $USER_TOKEN_2" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -d "{\"code\": \"$NEW_CODE\"}")
        
        VERIFY_2_STATUS=$(status_from_response "$VERIFY_2")
        print_result "POST /auth/verify-email-code (resent code) → 200" "200" "$VERIFY_2_STATUS" "$(body_from_response "$VERIFY_2")"
    else
        echo -e "${RED}✗${NC} Could not get resent code from log"
        TOTAL=$((TOTAL + 1))
        FAILED=$((FAILED + 1))
        FAILED_TESTS+=("Resend code retrieval")
    fi
else
    echo -e "${RED}✗${NC} Second registration failed"
    TOTAL=$((TOTAL + 1))
    FAILED=$((FAILED + 1))
    FAILED_TESTS+=("Second user registration")
fi

echo ""

# ==========================================
# Section 3: Error Handling
# ==========================================
echo "=========================================="
echo "Section 3: Error Handling"
echo "=========================================="
echo ""

# Test: Wrong code
WRONG_CODE_RESPONSE=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/auth/verify-email-code" \
    -H "Authorization: Bearer $USER_TOKEN" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d '{"code": "000000"}')

print_result "Invalid code → 422" "422" "$(status_from_response "$WRONG_CODE_RESPONSE")" "$(body_from_response "$WRONG_CODE_RESPONSE")"

# Test: Already verified user
ALREADY_VERIFIED=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/auth/verify-email-code" \
    -H "Authorization: Bearer $USER_TOKEN" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{\"code\": \"$VERIFICATION_CODE\"}")

print_result "Already verified → 422" "422" "$(status_from_response "$ALREADY_VERIFIED")" "$(body_from_response "$ALREADY_VERIFIED")"

# Test: Missing code field
MISSING_CODE=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/auth/verify-email-code" \
    -H "Authorization: Bearer $USER_TOKEN" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d '{}')

print_result "Missing code → 422" "422" "$(status_from_response "$MISSING_CODE")" "$(body_from_response "$MISSING_CODE")"

# Test: Unauthenticated request
UNAUTH=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/auth/verify-email-code" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d '{"code": "123456"}')

print_result "Unauthenticated → 401" "401 302" "$(status_from_response "$UNAUTH")" "$(body_from_response "$UNAUTH")"

# Test: Resend for already verified user
RESEND_VERIFIED=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/auth/resend-verification" \
    -H "Authorization: Bearer $USER_TOKEN" \
    -H "Accept: application/json")

print_result "Resend (already verified) → 422" "422" "$(status_from_response "$RESEND_VERIFIED")" "$(body_from_response "$RESEND_VERIFIED")"

echo ""

# ==========================================
# Summary
# ==========================================
print_summary_and_exit
