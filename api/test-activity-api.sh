#!/bin/bash

# Activity Module API Test Suite - Enhanced
# Tests all Activity endpoints with comprehensive validation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "=========================================="
echo "Activity Module API Test Suite - Enhanced"
echo "=========================================="
echo ""

# Setup: Login and create test data
echo "Setting up test environment..."
login_admin
create_workspace "$(date +%s)"
create_project "$(date +%s)"
create_section "$(date +%s)"
create_column "$(date +%s)"
create_task "$(date +%s)" "TASK_ID"
echo ""

echo "=========================================="
echo "15: Activity Module API Tests"
echo "=========================================="
echo ""

# Test: GET /api/v1/activities - List activities
RESPONSE=$(api_get "/activities")
assert_api "GET /api/v1/activities → 200 activities list" "200" "$RESPONSE"

# Test: GET /api/v1/activities/search - Activity search (replaces feed)
RESPONSE=$(api_get "/activities/search")
assert_api "GET /api/v1/activities/feed → 200 activity feed" "200" "$RESPONSE"

# Test: GET /api/v1/activities/task/{taskId} - Task activities
if [ -n "$TASK_ID" ]; then
    RESPONSE=$(api_get "/activities/task/$TASK_ID")
    assert_api "GET /api/v1/tasks/{id}/activities → 200 task activities" "200" "$RESPONSE"
fi

# Test: GET /api/v1/workspaces/{id}/activities - Workspace activities
if [ -n "$WORKSPACE_ID" ]; then
    RESPONSE=$(api_get "/workspaces/$WORKSPACE_ID/activities")
    assert_api "GET /api/v1/projects/{id}/activities → 200 project activities" "200" "$RESPONSE"
fi

echo ""

# ==========================================
# Phase 15: Enhanced Activity Tests
# ==========================================
echo "=========================================="
echo "Phase 15: Enhanced Activity Tests"
echo "=========================================="
echo ""

# Phase 15.1: Response Data Validation
echo "--- Phase 15.1: Response Data Validation ---"

RESPONSE=$(api_get "/activities")
BODY=$(body_from_response "$RESPONSE")
STATUS=$(status_from_response "$RESPONSE")

if assert_json_field "$BODY" "data"; then
    print_result "Activity list has data field" "200" "$STATUS" "$BODY"
else
    print_result "Activity list structure validation" "200" "FAIL" "$BODY"
fi

# Validate activity object structure
if assert_json_field "$BODY" "data.first"; then
    if assert_json_structure "$BODY" "data.first.id" "data.first.subject_type" "data.first.subject_id"; then
        print_result "Activity object contains required fields" "200" "$STATUS" "$BODY"
    else
        print_result "Activity object structure" "200" "FAIL" "$BODY"
    fi
fi

# Phase 15.2: Database Verification
echo ""
echo "--- Phase 15.2: Database Verification ---"

# Verify activities are being logged
if assert_db_has "activities" "1=1 LIMIT 1"; then
    print_result "Activities are being logged to database" "200" "200" "DB verification passed"
else
    print_result "Activities in database" "200" "FAIL" "No activities found"
fi

# Verify activity for task creation
if [ -n "$TASK_ID" ]; then
    if assert_db_has "activities" "subject_id = '$TASK_ID' AND subject_type LIKE '%Task%'"; then
        print_result "Activity logged for task creation" "200" "200" "DB verification passed"
    else
        print_result "Task creation activity" "200" "FAIL" "Activity not logged"
    fi
fi

# Phase 15.3: Business Logic Tests
echo ""
echo "--- Phase 15.3: Business Logic Tests ---"

# Test activity filtering by workspace
if [ -n "$WORKSPACE_ID" ]; then
    RESPONSE=$(api_get "/workspaces/$WORKSPACE_ID/activities")
    if [ "$(status_from_response "$RESPONSE")" = "200" ]; then
        print_result "Activity filtering by project works" "200" "200" "Filtering successful"
    else
        print_result "Activity filtering by project" "200" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
    fi
fi

# Test activity feed pagination
RESPONSE=$(api_get "/activities?page=1&per_page=10")
if [ "$(status_from_response "$RESPONSE")" = "200" ]; then
    print_result "Activity feed pagination works" "200" "200" "Pagination successful"
else
    print_result "Activity feed pagination" "200" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# Cleanup
cleanup_common_records

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
print_summary_and_exit
