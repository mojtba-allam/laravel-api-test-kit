#!/bin/bash

# Project Module API Test Suite - Enhanced
# Tests all Project endpoints with comprehensive validation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "=========================================="
echo "Project Module API Test Suite - Enhanced"
echo "=========================================="
echo ""

# Setup: Login with existing admin user
echo "Setting up test environment..."
login_admin
echo ""

echo "=========================================="
echo "10G: Project Module API Tests"
echo "=========================================="
echo ""

# Create workspace for testing
create_workspace "$(date +%s)"

# Test: GET /api/v1/projects - List projects
RESPONSE=$(api_get "/projects")
assert_api "GET /api/v1/projects → 200 paginated project list" "200" "$RESPONSE"

# Test: POST /api/v1/projects - Create project
PROJECT_NAME="TestProject-$(date +%s)"
RESPONSE=$(api_json POST "/projects" "{\"name\":\"$PROJECT_NAME\",\"description\":\"Test project\",\"workspace_id\":\"$WORKSPACE_ID\"}")
PROJECT_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$PROJECT_ID" ] && PROJECT_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")
assert_api "POST /api/v1/projects → 201 creates project" "201" "$RESPONSE"

# Test: GET /api/v1/projects/{project} - Show project
if [ -n "$PROJECT_ID" ]; then
    RESPONSE=$(api_get "/projects/$PROJECT_ID")
    assert_api "GET /api/v1/projects/{project} → 200 project details" "200" "$RESPONSE"
fi

# Test: PUT /api/v1/projects/{project} - Update project
if [ -n "$PROJECT_ID" ]; then
    UPDATED_NAME="UpdatedProject-$(date +%s)"
    RESPONSE=$(api_json PUT "/projects/$PROJECT_ID" "{\"name\":\"$UPDATED_NAME\"}")
    assert_api "PUT /api/v1/projects/{project} → 200 updates project" "200" "$RESPONSE"
fi

# Test: POST /api/v1/projects/{id}/archive - Archive project
if [ -n "$PROJECT_ID" ]; then
    RESPONSE=$(api_json POST "/projects/$PROJECT_ID/archive" '{}')
    assert_api "POST /api/v1/projects/{id}/archive → 200 archives project" "200" "$RESPONSE"
fi

# Test: POST /api/v1/projects/{id}/restore - Restore project
if [ -n "$PROJECT_ID" ]; then
    RESPONSE=$(api_json POST "/projects/$PROJECT_ID/restore" '{}')
    assert_api "POST /api/v1/projects/{id}/restore → 200 restores project" "200" "$RESPONSE"
fi

# Test: GET /api/v1/projects/{id}/watchers - Get watchers
if [ -n "$PROJECT_ID" ]; then
    RESPONSE=$(api_get "/projects/$PROJECT_ID/watchers")
    assert_api "GET /api/v1/projects/{id}/watchers → 200 project watchers" "200" "$RESPONSE"
fi

# Test: POST /api/v1/projects/{id}/watchers/me - Watch project
if [ -n "$PROJECT_ID" ]; then
    RESPONSE=$(api_json POST "/projects/$PROJECT_ID/watchers/me" '{}')
    assert_api "POST /api/v1/projects/{id}/watchers/me → 200 watch project" "200 201" "$RESPONSE"
fi

# Test: DELETE /api/v1/projects/{id}/watchers/me - Unwatch project
if [ -n "$PROJECT_ID" ]; then
    RESPONSE=$(api_delete "/projects/$PROJECT_ID/watchers/me")
    assert_api "DELETE /api/v1/projects/{id}/watchers/me → 200 unwatch project" "200" "$RESPONSE"
fi

echo ""

# ==========================================
# Phase 4: Enhanced Project Module Tests
# ==========================================
echo "=========================================="
echo "Phase 4: Enhanced Project Module Tests"
echo "=========================================="
echo ""

# Phase 4.1: Response Data Validation
echo "--- Phase 4.1: Response Data Validation ---"

RESPONSE=$(api_get "/projects")
BODY=$(body_from_response "$RESPONSE")
STATUS=$(status_from_response "$RESPONSE")

# Validate response structure
if assert_json_field "$BODY" "data"; then
    print_result "Project list has data field" "200" "$STATUS" "$BODY"
else
    print_result "Project list structure validation" "200" "FAIL" "$BODY"
fi

# Validate first project object structure (if exists)
if assert_json_field "$BODY" "data.first"; then
    if assert_json_structure "$BODY" "data.first.id" "data.first.name" "data.first.workspace_id"; then
        print_result "Project object contains required fields" "200" "$STATUS" "$BODY"
    else
        print_result "Project object structure validation" "200" "FAIL" "$BODY"
    fi
fi

# Phase 4.2: Database Verification
echo ""
echo "--- Phase 4.2: Database Verification ---"

# Create project for database verification
PROJ_NAME="DBTest-$(date +%s)-$RANDOM"
RESPONSE=$(api_json POST "/projects" "{\"name\":\"$PROJ_NAME\",\"workspace_id\":\"$WORKSPACE_ID\"}")
DB_PROJ_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$DB_PROJ_ID" ] && DB_PROJ_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")

if [ -n "$DB_PROJ_ID" ]; then
    # Verify project exists in database
    if assert_db_has "projects" "id = '$DB_PROJ_ID'"; then
        print_result "Project exists in database after creation" "201" "201" "DB verification passed"
    else
        print_result "Project in database" "201" "FAIL" "DB verification failed"
    fi
    
    # Verify project belongs to correct workspace
    if assert_db_field_value "projects" "$DB_PROJ_ID" "workspace_id" "$WORKSPACE_ID"; then
        print_result "Project belongs to correct workspace" "200" "200" "DB verification passed"
    else
        print_result "Project workspace relationship" "200" "FAIL" "DB verification failed"
    fi
    
    # Verify timestamps are set
    if assert_db_timestamp "projects" "$DB_PROJ_ID" "created_at"; then
        print_result "Project created_at timestamp is set" "200" "200" "DB verification passed"
    else
        print_result "Project created_at timestamp" "200" "FAIL" "DB verification failed"
    fi
    
    # Test archive and verify archived_at timestamp
    api_json POST "/projects/$DB_PROJ_ID/archive" '{}' > /dev/null
    if assert_db_timestamp "projects" "$DB_PROJ_ID" "archived_at"; then
        print_result "Project archive sets archived_at timestamp" "200" "200" "DB verification passed"
    else
        print_result "Project archive timestamp" "200" "FAIL" "DB verification failed"
    fi
    
    # Test restore and verify archived_at is cleared
    api_json POST "/projects/$DB_PROJ_ID/restore" '{}' > /dev/null
    ARCHIVED_AT=$(cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="echo DB::table('projects')->where('id', '$DB_PROJ_ID')->value('archived_at');" 2>/dev/null || echo "")
    if [ -z "$ARCHIVED_AT" ] || [ "$ARCHIVED_AT" = "null" ]; then
        print_result "Project restore clears archived_at timestamp" "200" "200" "DB verification passed"
    else
        print_result "Project restore clears archived_at" "200" "FAIL" "DB verification failed"
    fi
    
    # Update project and verify changes persisted
    RESPONSE=$(api_json PUT "/projects/$DB_PROJ_ID" '{"name":"UpdatedName"}')
    if assert_db_field_value "projects" "$DB_PROJ_ID" "name" "UpdatedName"; then
        print_result "Project update persisted to database" "200" "200" "DB verification passed"
    else
        print_result "Project update in database" "200" "FAIL" "DB verification failed"
    fi
    
    # Cleanup
    api_delete "/projects/$DB_PROJ_ID" > /dev/null 2>&1 || true
fi

# Phase 4.3: Validation & Error Tests
echo ""
echo "--- Phase 4.3: Validation & Error Tests ---"

# Test creating project without required fields
RESPONSE=$(api_json POST "/projects" '{}')
if assert_validation_error "$RESPONSE"; then
    print_result "Create project without required fields → 422" "422" "422" "Validation error"
else
    print_result "Create project without required fields" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# Test creating project without name
RESPONSE=$(api_json POST "/projects" "{\"workspace_id\":\"$WORKSPACE_ID\"}")
if assert_validation_error "$RESPONSE"; then
    print_result "Create project without name → 422" "422" "422" "Validation error"
else
    print_result "Create project without name" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# Test creating project without workspace_id (now allowed - standalone project)
RESPONSE=$(api_json POST "/projects" '{"name":"Standalone Test Project","status":"active","priority":"medium"}')
STATUS=$(status_from_response "$RESPONSE")
if [ "$STATUS" = "201" ]; then
    print_result "Create project without workspace_id → 201 (standalone)" "201" "$STATUS" "Created"
else
    print_result "Create project without workspace_id" "201" "$STATUS" "$(body_from_response "$RESPONSE")"
fi

# Test creating project with invalid workspace_id
RESPONSE=$(api_json POST "/projects" '{"name":"Test","workspace_id":"99999999"}')
STATUS=$(status_from_response "$RESPONSE")
if [ "$STATUS" = "422" ] || [ "$STATUS" = "404" ]; then
    print_result "Create project with invalid workspace_id → 422/404" "422" "$STATUS" "Validation error"
else
    print_result "Create project with invalid workspace_id" "422" "$STATUS" "$(body_from_response "$RESPONSE")"
fi

# Test updating non-existent project
RESPONSE=$(api_json PUT "/projects/99999999" '{"name":"Test"}')
assert_api "Update non-existent project → 404" "404" "$RESPONSE"

# Test accessing project without authentication
OLD_TOKEN="$TOKEN"
TOKEN=""
RESPONSE=$(api_get "/projects")
if assert_unauthorized "$RESPONSE"; then
    print_result "Access projects without auth → 401" "401" "401" "Unauthorized"
else
    print_result "Access projects without auth → 401" "401" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi
TOKEN="$OLD_TOKEN"

# Phase 4.4: Business Logic Tests
echo ""
echo "--- Phase 4.4: Business Logic Tests ---"

# Test archiving project
ARCH_PROJ_NAME="ArchiveTest-$(date +%s)-$RANDOM"
RESPONSE=$(api_json POST "/projects" "{\"name\":\"$ARCH_PROJ_NAME\",\"workspace_id\":\"$WORKSPACE_ID\"}")
ARCH_PROJ_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$ARCH_PROJ_ID" ] && ARCH_PROJ_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")

if [ -n "$ARCH_PROJ_ID" ]; then
    # Archive project
    RESPONSE=$(api_json POST "/projects/$ARCH_PROJ_ID/archive" '{}')
    if [ "$(status_from_response "$RESPONSE")" = "200" ]; then
        print_result "Archiving project succeeds" "200" "200" "Archive successful"
    else
        print_result "Archiving project" "200" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
    fi
    
    # Restore project
    RESPONSE=$(api_json POST "/projects/$ARCH_PROJ_ID/restore" '{}')
    if [ "$(status_from_response "$RESPONSE")" = "200" ]; then
        print_result "Restoring project succeeds" "200" "200" "Restore successful"
    else
        print_result "Restoring project" "200" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
    fi
    
    api_delete "/projects/$ARCH_PROJ_ID" > /dev/null 2>&1 || true
fi

# Test project visibility rules
VISIBILITY_PROJ_NAME="VisibilityTest-$(date +%s)-$RANDOM"
RESPONSE=$(api_json POST "/projects" "{\"name\":\"$VISIBILITY_PROJ_NAME\",\"workspace_id\":\"$WORKSPACE_ID\",\"visibility\":\"private\"}")
VIS_PROJ_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$VIS_PROJ_ID" ] && VIS_PROJ_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")

if [ -n "$VIS_PROJ_ID" ]; then
    # Verify visibility saved correctly
    if assert_db_field_value "projects" "$VIS_PROJ_ID" "visibility" "private"; then
        print_result "Project visibility saved correctly" "201" "201" "DB verification passed"
    else
        print_result "Project visibility in database" "201" "FAIL" "DB verification failed"
    fi
    
    api_delete "/projects/$VIS_PROJ_ID" > /dev/null 2>&1 || true
fi

# Phase 4.5: Project Teams Tests
echo ""
echo "--- Phase 4.5: Project Teams Tests ---"

TEAM_PROJ_NAME="TeamTest-$(date +%s)-$RANDOM"
RESPONSE=$(api_json POST "/projects" "{\"name\":\"$TEAM_PROJ_NAME\",\"workspace_id\":\"$WORKSPACE_ID\"}")
TEAM_PROJ_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$TEAM_PROJ_ID" ] && TEAM_PROJ_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")

if [ -n "$TEAM_PROJ_ID" ]; then
    # Test project watchers
    RESPONSE=$(api_get "/projects/$TEAM_PROJ_ID/watchers")
    if [ "$(status_from_response "$RESPONSE")" = "200" ]; then
        print_result "Get project watchers succeeds" "200" "200" "Watchers retrieved"
    else
        print_result "Get project watchers" "200" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
    fi
    
    # Test watching project
    RESPONSE=$(api_json POST "/projects/$TEAM_PROJ_ID/watchers/me" '{}')
    STATUS=$(status_from_response "$RESPONSE")
    if [ "$STATUS" = "200" ] || [ "$STATUS" = "201" ]; then
        print_result "Watch project succeeds" "200" "$STATUS" "Watch successful"
        
        # Verify watcher relationship created in database
        if assert_db_has "project_watchers" "project_id = '$TEAM_PROJ_ID' AND user_id = '$USER_ID'"; then
            print_result "Project watcher relationship created in database" "200" "200" "DB verification passed"
        else
            print_result "Project watcher in database" "200" "FAIL" "DB verification failed"
        fi
        
        # Test unwatching project
        RESPONSE=$(api_delete "/projects/$TEAM_PROJ_ID/watchers/me")
        if [ "$(status_from_response "$RESPONSE")" = "200" ]; then
            print_result "Unwatch project succeeds" "200" "200" "Unwatch successful"
            
            # Verify watcher relationship removed
            if assert_db_missing "project_watchers" "project_id = '$TEAM_PROJ_ID' AND user_id = '$USER_ID'"; then
                print_result "Project watcher relationship removed from database" "200" "200" "DB verification passed"
            else
                print_result "Project watcher removal from database" "200" "FAIL" "DB verification failed"
            fi
        else
            print_result "Unwatch project" "200" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
        fi
    else
        print_result "Watch project" "200" "$STATUS" "$(body_from_response "$RESPONSE")"
    fi
    
    api_delete "/projects/$TEAM_PROJ_ID" > /dev/null 2>&1 || true
fi

# Cleanup
if [ -n "$PROJECT_ID" ]; then
    api_delete "/projects/$PROJECT_ID" > /dev/null 2>&1 || true
fi

cleanup_common_records

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
print_summary_and_exit
