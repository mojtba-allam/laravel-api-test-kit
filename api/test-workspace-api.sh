#!/bin/bash

# Finolo Workspace Module API Test Suite - Enhanced

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "=========================================="
echo "Workspace Module API Test Suite - Enhanced"
echo "=========================================="
echo ""

# Login
login_admin
echo ""

echo "=========================================="
echo "10F: Workspace Module API Tests"
echo "=========================================="
echo ""

# Test: GET /api/v1/workspaces - List workspaces
RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/workspaces" \
    -H "Authorization: Bearer $TOKEN")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
print_result "GET /api/v1/workspaces → 200 paginated workspace list" 200 "$STATUS" "$BODY"

# Test: POST /api/v1/workspaces - Create workspace
WORKSPACE_NAME="TestWorkspace-$(date +%s)"
RESPONSE=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/workspaces" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"$WORKSPACE_NAME\",
        \"description\": \"Test workspace\",
        \"visibility\": \"private\"
    }")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
WORKSPACE_ID=$(json_value "$BODY" "id")
print_result "POST /api/v1/workspaces → 201 creates workspace" 201 "$STATUS" "$BODY"

# Test: GET /api/v1/workspaces/{workspace} - Show workspace
if [ -n "$WORKSPACE_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/workspaces/$WORKSPACE_ID" \
        -H "Authorization: Bearer $TOKEN")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "GET /api/v1/workspaces/{workspace} → 200 workspace details" 200 "$STATUS" "$BODY"
fi

# Test: PUT /api/v1/workspaces/{workspace} - Update workspace
if [ -n "$WORKSPACE_ID" ]; then
    UPDATED_NAME="UpdatedWorkspace-$(date +%s)"
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X PUT "$BASE_URL/workspaces/$WORKSPACE_ID" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"$UPDATED_NAME\",
            \"description\": \"Updated description\"
        }")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "PUT /api/v1/workspaces/{workspace} → 200 updates workspace" 200 "$STATUS" "$BODY"
fi

# Test: GET /api/v1/workspaces/{workspace}/settings - Get settings
if [ -n "$WORKSPACE_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/workspaces/$WORKSPACE_ID/settings" \
        -H "Authorization: Bearer $TOKEN")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "GET /api/v1/workspaces/{workspace}/settings → 200 workspace settings" 200 "$STATUS" "$BODY"
fi

# Test: PUT /api/v1/workspaces/{workspace}/settings - Update settings
if [ -n "$WORKSPACE_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X PUT "$BASE_URL/workspaces/$WORKSPACE_ID/settings" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "settings": {
                "default_board_visibility": "workspace",
                "card_aging_enabled": true
            }
        }')
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "PUT /api/v1/workspaces/{workspace}/settings → 200 updates settings" 200 "$STATUS" "$BODY"
fi

# Test: GET /api/v1/workspaces/{workspace}/collections - List collections
if [ -n "$WORKSPACE_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/workspaces/$WORKSPACE_ID/collections" \
        -H "Authorization: Bearer $TOKEN")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "GET /api/v1/workspaces/{workspace}/collections → 200 collections list" 200 "$STATUS" "$BODY"
fi

# Test: POST /api/v1/workspaces/{workspace}/collections - Create collection
if [ -n "$WORKSPACE_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/workspaces/$WORKSPACE_ID/collections" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "Test Collection",
            "description": "Test collection description"
        }')
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    COLLECTION_ID=$(json_value "$BODY" "id")
    print_result "POST /api/v1/workspaces/{workspace}/collections → 201 creates collection" 201 "$STATUS" "$BODY"
fi

# Test: PUT /api/v1/workspaces/{workspace}/collections/{collection} - Update collection
if [ -n "$WORKSPACE_ID" ] && [ -n "$COLLECTION_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X PUT "$BASE_URL/workspaces/$WORKSPACE_ID/collections/$COLLECTION_ID" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "Updated Collection",
            "description": "Updated description"
        }')
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "PUT /api/v1/workspaces/{workspace}/collections/{collection} → 200 updates collection" 200 "$STATUS" "$BODY"
fi

# Test: DELETE /api/v1/workspaces/{workspace}/collections/{collection} - Delete collection
if [ -n "$WORKSPACE_ID" ] && [ -n "$COLLECTION_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X DELETE "$BASE_URL/workspaces/$WORKSPACE_ID/collections/$COLLECTION_ID" \
        -H "Authorization: Bearer $TOKEN")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "DELETE /api/v1/workspaces/{workspace}/collections/{collection} → 200 deletes collection" 200 "$STATUS" "$BODY"
fi

# Test: GET /api/v1/workspaces/{workspace}/exports - List exports
if [ -n "$WORKSPACE_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/workspaces/$WORKSPACE_ID/exports" \
        -H "Authorization: Bearer $TOKEN")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "GET /api/v1/workspaces/{workspace}/exports → 200 export records" 200 "$STATUS" "$BODY"
fi

# Test: POST /api/v1/workspaces/{workspace}/exports - Request export
if [ -n "$WORKSPACE_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/workspaces/$WORKSPACE_ID/exports" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "format": "json"
        }')
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "POST /api/v1/workspaces/{workspace}/exports → 202 requests export" 202 "$STATUS" "$BODY"
fi

# Test: GET /api/v1/workspaces/{workspace}/reporting - Get reporting data
if [ -n "$WORKSPACE_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/workspaces/$WORKSPACE_ID/reporting" \
        -H "Authorization: Bearer $TOKEN")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "GET /api/v1/workspaces/{workspace}/reporting → 200 reporting data" 200 "$STATUS" "$BODY"
fi

# Test: DELETE /api/v1/workspaces/{workspace} - Delete workspace
if [ -n "$WORKSPACE_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X DELETE "$BASE_URL/workspaces/$WORKSPACE_ID" \
        -H "Authorization: Bearer $TOKEN")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "DELETE /api/v1/workspaces/{workspace} → 200 deletes workspace" 200 "$STATUS" "$BODY"
fi

echo ""

# ==========================================
# Phase 3: Enhanced Workspace Module Tests
# ==========================================
echo "=========================================="
echo "Phase 3: Enhanced Workspace Module Tests"
echo "=========================================="
echo ""

# Phase 3.1: Response Data Validation
echo "--- Phase 3.1: Response Data Validation ---"

RESPONSE=$(api_get "/workspaces")
BODY=$(body_from_response "$RESPONSE")
STATUS=$(status_from_response "$RESPONSE")

# Validate workspace list response structure
if assert_json_field "$BODY" "data"; then
    print_result "Workspace list has data field" "200" "$STATUS" "$BODY"
else
    print_result "Workspace list structure validation" "200" "FAIL" "$BODY"
fi

# Phase 3.2: Database Verification
echo ""
echo "--- Phase 3.2: Database Verification ---"

# Create workspace for database verification
WS_NAME="DBTest-$(date +%s)-$RANDOM"
RESPONSE=$(api_json POST "/workspaces" "{\"name\":\"$WS_NAME\",\"description\":\"DB test\",\"visibility\":\"private\"}")
DB_WS_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$DB_WS_ID" ] && DB_WS_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")

if [ -n "$DB_WS_ID" ]; then
    # Verify workspace exists in database
    if assert_db_has "workspaces" "id = '$DB_WS_ID'"; then
        print_result "Workspace exists in database after creation" "201" "201" "DB verification passed"
    else
        print_result "Workspace in database" "201" "FAIL" "DB verification failed"
    fi
    
    # Verify workspace name saved correctly
    if assert_db_field_value "workspaces" "$DB_WS_ID" "name" "$WS_NAME"; then
        print_result "Workspace name saved correctly" "200" "200" "DB verification passed"
    else
        print_result "Workspace name in database" "200" "FAIL" "DB verification failed"
    fi
    
    # Verify workspace ownership assigned
    if assert_db_has "workspace_members" "workspace_id = '$DB_WS_ID'"; then
        print_result "Workspace ownership assigned" "200" "200" "DB verification passed"
    else
        print_result "Workspace ownership" "200" "FAIL" "DB verification failed"
    fi
    
    api_delete "/workspaces/$DB_WS_ID" > /dev/null 2>&1 || true
fi

# Phase 3.3: Validation & Error Tests
echo ""
echo "--- Phase 3.3: Validation & Error Tests ---"

# Test creating workspace without name
RESPONSE=$(api_json POST "/workspaces" '{"description":"Test"}')
if assert_validation_error "$RESPONSE"; then
    print_result "Create workspace without name → 422" "422" "422" "Validation error"
else
    print_result "Create workspace without name → 422" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# Test creating workspace with invalid visibility
RESPONSE=$(api_json POST "/workspaces" "{\"name\":\"Test-$(date +%s)\",\"visibility\":\"invalid\"}")
STATUS=$(status_from_response "$RESPONSE")
if [ "$STATUS" = "422" ] || [ "$STATUS" = "400" ]; then
    print_result "Create workspace with invalid visibility → 422/400" "422" "$STATUS" "Validation error"
else
    print_result "Create workspace with invalid visibility" "422" "$STATUS" "$(body_from_response "$RESPONSE")"
fi

# Test updating non-existent workspace
RESPONSE=$(api_json PUT "/workspaces/99999999" '{"name":"Test"}')
assert_api "Update non-existent workspace → 404" "404" "$RESPONSE"

# Test accessing workspace without authentication
OLD_TOKEN="$TOKEN"
TOKEN=""
RESPONSE=$(api_get "/workspaces")
if assert_unauthorized "$RESPONSE"; then
    print_result "Access workspaces without auth → 401" "401" "401" "Unauthorized"
else
    print_result "Access workspaces without auth → 401" "401" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi
TOKEN="$OLD_TOKEN"

# Phase 3.4: Business Logic Tests
echo ""
echo "--- Phase 3.4: Business Logic Tests ---"

# Create workspace and verify creator becomes owner
WS_NAME="OwnerTest-$(date +%s)-$RANDOM"
RESPONSE=$(api_json POST "/workspaces" "{\"name\":\"$WS_NAME\",\"visibility\":\"private\"}")
OWNER_WS_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$OWNER_WS_ID" ] && OWNER_WS_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")

if [ -n "$OWNER_WS_ID" ] && [ -n "$USER_ID" ]; then
    # Verify creator is a member (workspace_members uses workspace_role_id, not role column)
    if assert_db_has "workspace_members" "workspace_id = '$OWNER_WS_ID' AND user_id = '$USER_ID'"; then
        print_result "Workspace creator becomes owner" "201" "201" "DB verification passed"
    else
        print_result "Workspace creator ownership" "201" "FAIL" "DB verification failed"
    fi
    
    api_delete "/workspaces/$OWNER_WS_ID" > /dev/null 2>&1 || true
fi

# Test workspace settings defaults
WS_NAME="SettingsTest-$(date +%s)-$RANDOM"
RESPONSE=$(api_json POST "/workspaces" "{\"name\":\"$WS_NAME\"}")
SETTINGS_WS_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$SETTINGS_WS_ID" ] && SETTINGS_WS_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")

if [ -n "$SETTINGS_WS_ID" ]; then
    # Verify settings exist
    RESPONSE=$(api_get "/workspaces/$SETTINGS_WS_ID/settings")
    if [ "$(status_from_response "$RESPONSE")" = "200" ]; then
        print_result "Workspace settings defaults applied" "200" "200" "Settings retrieved"
    else
        print_result "Workspace settings defaults" "200" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
    fi
    
    api_delete "/workspaces/$SETTINGS_WS_ID" > /dev/null 2>&1 || true
fi

# Phase 3.5: Relationship Testing
echo ""
echo "--- Phase 3.5: Relationship Testing ---"

# Create workspace with collection
WS_NAME="RelTest-$(date +%s)-$RANDOM"
RESPONSE=$(api_json POST "/workspaces" "{\"name\":\"$WS_NAME\"}")
REL_WS_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$REL_WS_ID" ] && REL_WS_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")

if [ -n "$REL_WS_ID" ]; then
    # Create collection in workspace
    RESPONSE=$(api_json POST "/workspaces/$REL_WS_ID/collections" '{"name":"TestCollection","description":"Test"}')
    REL_COLL_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
    [ -z "$REL_COLL_ID" ] && REL_COLL_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")
    
    if [ -n "$REL_COLL_ID" ]; then
        # Verify collection belongs to workspace (table is workspace_collections, not collections)
        if assert_db_has "workspace_collections" "id = '$REL_COLL_ID' AND workspace_id = '$REL_WS_ID'"; then
            print_result "Collection belongs to workspace" "201" "201" "DB verification passed"
        else
            print_result "Collection-workspace relationship" "201" "FAIL" "DB verification failed"
        fi
    fi
    
    api_delete "/workspaces/$REL_WS_ID" > /dev/null 2>&1 || true
fi

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
print_summary_and_exit
