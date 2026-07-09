#!/bin/bash

# Finolo Integration (CI/CD) API Test Suite
# Tests CRUD for integrations, provider listing, test connection, and runs endpoints.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "=========================================="
echo "Integration (CI/CD) API Test Suite"
echo "=========================================="
echo ""

login_admin
create_workspace "intg"
create_project "intg"
echo ""

# ==========================================
# Phase 1: Provider Listing
# ==========================================
echo "--- Phase 1: Provider Listing ---"

RESPONSE=$(api_get "/integrations/providers")
assert_api "GET /api/v1/integrations/providers → 200" "200" "$RESPONSE"

BODY=$(body_from_response "$RESPONSE")
if assert_json_field "$BODY" "data"; then
    print_result "Providers response has data field" "200" "200" "Structure valid"
else
    print_result "Providers response structure" "200" "FAIL" "$BODY"
fi

# ==========================================
# Phase 2: Create Integration
# ==========================================
echo ""
echo "--- Phase 2: Create Integration ---"

RESPONSE=$(api_json POST "/projects/$PROJECT_ID/integrations" "{\"provider\":\"github_actions\",\"name\":\"Test CI\",\"repository\":\"testorg/testrepo\",\"token\":\"ghp_faketoken123456\"}")
assert_api "POST /api/v1/projects/{id}/integrations → 201" "201" "$RESPONSE"

BODY=$(body_from_response "$RESPONSE")
INTEGRATION_ID=$(json_value "$BODY" "data.id")

if [ -n "$INTEGRATION_ID" ]; then
    print_result "Integration created with id" "201" "201" "ID: $INTEGRATION_ID"
else
    print_result "Integration created" "201" "FAIL" "No id returned"
fi

if assert_json_value "$BODY" "data.provider" "github_actions"; then
    print_result "Provider is github_actions" "201" "201" "Correct"
else
    print_result "Provider check" "201" "FAIL" "$BODY"
fi

if assert_json_value "$BODY" "data.repository" "testorg/testrepo"; then
    print_result "Repository saved correctly" "201" "201" "Correct"
else
    print_result "Repository check" "201" "FAIL" "$BODY"
fi

# Verify token is NOT in response
if echo "$BODY" | grep -q "ghp_faketoken"; then
    print_result "Token not exposed in response" "201" "FAIL" "Token is visible"
else
    print_result "Token not exposed in response" "201" "201" "Token hidden"
fi

# ==========================================
# Phase 3: List Project Integrations
# ==========================================
echo ""
echo "--- Phase 3: List Integrations ---"

RESPONSE=$(api_get "/projects/$PROJECT_ID/integrations")
assert_api "GET /api/v1/projects/{id}/integrations → 200" "200" "$RESPONSE"

BODY=$(body_from_response "$RESPONSE")
if assert_json_field "$BODY" "data"; then
    print_result "Integrations list has data" "200" "200" "Structure valid"
else
    print_result "Integrations list structure" "200" "FAIL" "$BODY"
fi

# ==========================================
# Phase 4: Show Integration
# ==========================================
echo ""
echo "--- Phase 4: Show Integration ---"

if [ -n "$INTEGRATION_ID" ]; then
    RESPONSE=$(api_get "/integrations/$INTEGRATION_ID")
    assert_api "GET /api/v1/integrations/{id} → 200" "200" "$RESPONSE"

    BODY=$(body_from_response "$RESPONSE")
    if assert_json_value "$BODY" "data.id" "$INTEGRATION_ID"; then
        print_result "Show returns correct integration" "200" "200" "Correct"
    else
        print_result "Show integration" "200" "FAIL" "$BODY"
    fi
fi

# ==========================================
# Phase 5: Update Integration
# ==========================================
echo ""
echo "--- Phase 5: Update Integration ---"

if [ -n "$INTEGRATION_ID" ]; then
    RESPONSE=$(api_json PUT "/integrations/$INTEGRATION_ID" '{"name":"Updated CI","repository":"neworg/newrepo"}')
    assert_api "PUT /api/v1/integrations/{id} → 200" "200" "$RESPONSE"

    BODY=$(body_from_response "$RESPONSE")
    if assert_json_value "$BODY" "data.name" "Updated CI"; then
        print_result "Name updated correctly" "200" "200" "Correct"
    else
        print_result "Name update" "200" "FAIL" "$BODY"
    fi

    if assert_json_value "$BODY" "data.repository" "neworg/newrepo"; then
        print_result "Repository updated correctly" "200" "200" "Correct"
    else
        print_result "Repository update" "200" "FAIL" "$BODY"
    fi
fi

# ==========================================
# Phase 6: Validation Tests
# ==========================================
echo ""
echo "--- Phase 6: Validation Tests ---"

# Missing required fields
RESPONSE=$(api_json POST "/projects/$PROJECT_ID/integrations" '{}')
if assert_validation_error "$RESPONSE"; then
    print_result "Create without required fields → 422" "422" "422" "Validation error"
else
    print_result "Create without required fields" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# Invalid provider
RESPONSE=$(api_json POST "/projects/$PROJECT_ID/integrations" '{"provider":"invalid","name":"X","repository":"a/b","token":"tok"}')
if assert_validation_error "$RESPONSE"; then
    print_result "Invalid provider → 422" "422" "422" "Validation error"
else
    print_result "Invalid provider" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# ==========================================
# Phase 7: Get Runs (will return empty since no real token)
# ==========================================
echo ""
echo "--- Phase 7: CI/CD Runs ---"

if [ -n "$INTEGRATION_ID" ]; then
    RESPONSE=$(api_get "/integrations/$INTEGRATION_ID/runs")
    assert_api "GET /api/v1/integrations/{id}/runs → 200" "200" "$RESPONSE"

    BODY=$(body_from_response "$RESPONSE")
    if assert_json_field "$BODY" "data"; then
        print_result "Runs response has data field" "200" "200" "Structure valid"
    else
        print_result "Runs response structure" "200" "FAIL" "$BODY"
    fi

    if assert_json_field "$BODY" "meta.provider"; then
        print_result "Runs response has meta.provider" "200" "200" "Structure valid"
    else
        print_result "Runs meta structure" "200" "FAIL" "$BODY"
    fi
fi

# ==========================================
# Phase 8: Test Connection
# ==========================================
echo ""
echo "--- Phase 8: Test Connection ---"

if [ -n "$INTEGRATION_ID" ]; then
    RESPONSE=$(api_json POST "/integrations/$INTEGRATION_ID/test" '{}')
    assert_api "POST /api/v1/integrations/{id}/test → 200" "200" "$RESPONSE"

    BODY=$(body_from_response "$RESPONSE")
    if assert_json_field "$BODY" "success"; then
        print_result "Test connection has success field" "200" "200" "Structure valid"
    else
        print_result "Test connection structure" "200" "FAIL" "$BODY"
    fi
fi

# ==========================================
# Phase 9: Authorization Tests
# ==========================================
echo ""
echo "--- Phase 9: Authorization Tests ---"

# Unauthenticated access
OLD_TOKEN="$TOKEN"
TOKEN=""
RESPONSE=$(api_get "/projects/$PROJECT_ID/integrations")
if assert_unauthorized "$RESPONSE"; then
    print_result "Unauthenticated → 401" "401" "401" "Blocked"
else
    print_result "Unauthenticated access" "401" "$(status_from_response "$RESPONSE")" ""
fi
TOKEN="$OLD_TOKEN"

# ==========================================
# Phase 10: Delete Integration
# ==========================================
echo ""
echo "--- Phase 10: Delete Integration ---"

if [ -n "$INTEGRATION_ID" ]; then
    RESPONSE=$(api_delete "/integrations/$INTEGRATION_ID")
    assert_api "DELETE /api/v1/integrations/{id} → 200" "200" "$RESPONSE"

    # Verify soft deleted
    RESPONSE=$(api_get "/integrations/$INTEGRATION_ID")
    STATUS=$(status_from_response "$RESPONSE")
    if [ "$STATUS" = "404" ]; then
        print_result "Deleted integration returns 404" "404" "404" "Soft deleted"
    else
        print_result "Deleted integration access" "404" "$STATUS" ""
    fi
fi

# ==========================================
# Phase 11: Not Found
# ==========================================
echo ""
echo "--- Phase 11: Not Found ---"

RESPONSE=$(api_get "/integrations/non-existent-uuid")
assert_api "GET non-existent integration → 404" "404" "$RESPONSE"

# Cleanup
cleanup_common_records

echo ""
print_summary_and_exit
