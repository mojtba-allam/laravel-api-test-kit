#!/bin/bash

# Finolo Task Module API Test Suite - Enhanced
# Tests all Task endpoints with comprehensive validation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "=========================================="
echo "Task Module API Test Suite - Enhanced"
echo "=========================================="
echo ""

# Setup: Login and create test environment
echo "Setting up test environment..."
login_admin
create_workspace "$(date +%s)"
create_project "$(date +%s)"
create_section "$(date +%s)"
create_column "$(date +%s)"
echo ""

echo "=========================================="
echo "10H: Task Module API Tests"
echo "=========================================="
echo ""

# Test: GET /api/v1/tasks - List tasks
RESPONSE=$(api_get "/tasks")
assert_api "GET /api/v1/tasks → 200 paginated task list" "200" "$RESPONSE"

# Test: POST /api/v1/tasks - Create task
TASK_TITLE="TestTask-$(date +%s)"
RESPONSE=$(api_json POST "/tasks" "{\"title\":\"$TASK_TITLE\",\"column_id\":\"$COLUMN_ID\",\"priority\":\"medium\"}")
TASK_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$TASK_ID" ] && TASK_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")
assert_api "POST /api/v1/tasks → 201 creates task" "201" "$RESPONSE"

# Test: GET /api/v1/tasks/{id} - Show task
if [ -n "$TASK_ID" ]; then
    RESPONSE=$(api_get "/tasks/$TASK_ID")
    assert_api "GET /api/v1/tasks/{id} → 200 task details" "200" "$RESPONSE"
fi

# Test: PUT /api/v1/tasks/{id} - Update task
if [ -n "$TASK_ID" ]; then
    RESPONSE=$(api_json PUT "/tasks/$TASK_ID" '{"title":"Updated Task"}')
    assert_api "PUT /api/v1/tasks/{id} → 200 updates task" "200" "$RESPONSE"
fi

# Test: POST /api/v1/tasks/{id}/complete - Complete task
if [ -n "$TASK_ID" ]; then
    RESPONSE=$(api_json POST "/tasks/$TASK_ID/complete" '{}')
    assert_api "POST /api/v1/tasks/{id}/complete → 200 completes task" "200" "$RESPONSE"
fi

# Test: POST /api/v1/tasks/{id}/archive - Archive task
if [ -n "$TASK_ID" ]; then
    RESPONSE=$(api_json POST "/tasks/$TASK_ID/archive" '{}')
    assert_api "POST /api/v1/tasks/{id}/archive → 200 archives task" "200" "$RESPONSE"
fi

# Test: POST /api/v1/tasks/{id}/restore - Restore task
if [ -n "$TASK_ID" ]; then
    RESPONSE=$(api_json POST "/tasks/$TASK_ID/restore" '{}')
    assert_api "POST /api/v1/tasks/{id}/restore → 200 restores task" "200" "$RESPONSE"
fi

# Test: GET /api/v1/tasks/{id}/watchers - Get watchers
if [ -n "$TASK_ID" ]; then
    RESPONSE=$(api_get "/tasks/$TASK_ID/watchers")
    assert_api "GET /api/v1/tasks/{id}/watchers → 200 task watchers" "200" "$RESPONSE"
fi

# Test: POST /api/v1/tasks/{id}/watchers/me - Watch task
if [ -n "$TASK_ID" ]; then
    RESPONSE=$(api_json POST "/tasks/$TASK_ID/watchers/me" '{}')
    assert_api "POST /api/v1/tasks/{id}/watchers/me → 200 watch task" "200 201" "$RESPONSE"
fi

# Test: DELETE /api/v1/tasks/{id}/watchers/me - Unwatch task
if [ -n "$TASK_ID" ]; then
    RESPONSE=$(api_delete "/tasks/$TASK_ID/watchers/me")
    assert_api "DELETE /api/v1/tasks/{id}/watchers/me → 200 unwatch task" "200" "$RESPONSE"
fi

# Test: GET /api/v1/tasks/overdue - Overdue tasks
RESPONSE=$(api_get "/tasks/overdue")
assert_api "GET /api/v1/tasks/overdue → 200 overdue tasks" "200" "$RESPONSE"

echo ""

# ==========================================
# Phase 5: Enhanced Task Module Tests
# ==========================================
echo "=========================================="
echo "Phase 5: Enhanced Task Module Tests"
echo "=========================================="
echo ""

# Phase 5.1: Response Data Validation
echo "--- Phase 5.1: Response Data Validation ---"

RESPONSE=$(api_get "/tasks")
BODY=$(body_from_response "$RESPONSE")
STATUS=$(status_from_response "$RESPONSE")

if assert_json_field "$BODY" "data"; then
    print_result "Task list has data field" "200" "$STATUS" "$BODY"
else
    print_result "Task list structure validation" "200" "FAIL" "$BODY"
fi

# Phase 5.2: Database Verification
echo ""
echo "--- Phase 5.2: Database Verification ---"

DB_TASK_TITLE="DBTest-$(date +%s)-$RANDOM"
RESPONSE=$(api_json POST "/tasks" "{\"title\":\"$DB_TASK_TITLE\",\"column_id\":\"$COLUMN_ID\",\"priority\":\"high\"}")
DB_TASK_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$DB_TASK_ID" ] && DB_TASK_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")

if [ -n "$DB_TASK_ID" ]; then
    if assert_db_has "tasks" "id = '$DB_TASK_ID'"; then
        print_result "Task exists in database after creation" "201" "201" "DB verification passed"
    else
        print_result "Task in database" "201" "FAIL" "DB verification failed"
    fi
    
    if assert_db_field_value "tasks" "$DB_TASK_ID" "column_id" "$COLUMN_ID"; then
        print_result "Task belongs to correct column" "200" "200" "DB verification passed"
    else
        print_result "Task column relationship" "200" "FAIL" "DB verification failed"
    fi
    
    if assert_db_timestamp "tasks" "$DB_TASK_ID" "created_at"; then
        print_result "Task created_at timestamp is set" "200" "200" "DB verification passed"
    else
        print_result "Task created_at timestamp" "200" "FAIL" "DB verification failed"
    fi
    
    api_delete "/tasks/$DB_TASK_ID" > /dev/null 2>&1 || true
fi

# Phase 5.3: Validation & Error Tests
echo ""
echo "--- Phase 5.3: Validation & Error Tests ---"

RESPONSE=$(api_json POST "/tasks" '{}')
if assert_validation_error "$RESPONSE"; then
    print_result "Create task without required fields → 422" "422" "422" "Validation error"
else
    print_result "Create task without required fields" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

RESPONSE=$(api_json POST "/tasks" '{"title":"Test"}')
if assert_validation_error "$RESPONSE"; then
    print_result "Create task without column_id → 422" "422" "422" "Validation error"
else
    print_result "Create task without column_id" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

RESPONSE=$(api_json POST "/tasks" '{"title":"Test","column_id":"99999999"}')
STATUS=$(status_from_response "$RESPONSE")
if [ "$STATUS" = "422" ] || [ "$STATUS" = "404" ]; then
    print_result "Create task with invalid column_id → 422/404" "422" "$STATUS" "Validation error"
else
    print_result "Create task with invalid column_id" "422" "$STATUS" "$(body_from_response "$RESPONSE")"
fi

RESPONSE=$(api_json POST "/tasks" "{\"title\":\"Test\",\"column_id\":\"$COLUMN_ID\",\"priority\":\"invalid\"}")
if assert_validation_error "$RESPONSE"; then
    print_result "Create task with invalid priority → 422" "422" "422" "Validation error"
else
    print_result "Create task with invalid priority" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

RESPONSE=$(api_json POST "/tasks" "{\"title\":\"Test\",\"column_id\":\"$COLUMN_ID\",\"status\":\"invalid\"}")
if assert_validation_error "$RESPONSE"; then
    print_result "Create task with invalid status → 422" "422" "422" "Validation error"
else
    print_result "Create task with invalid status" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

RESPONSE=$(api_json POST "/tasks" "{\"title\":\"Test\",\"column_id\":\"$COLUMN_ID\",\"due_date\":\"invalid-date\"}")
if assert_validation_error "$RESPONSE"; then
    print_result "Create task with invalid due_date → 422" "422" "422" "Validation error"
else
    print_result "Create task with invalid due_date" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

RESPONSE=$(api_json PUT "/tasks/99999999" '{"title":"Test"}')
assert_api "Update non-existent task → 404" "404" "$RESPONSE"

OLD_TOKEN="$TOKEN"
TOKEN=""
RESPONSE=$(api_get "/tasks")
if assert_unauthorized "$RESPONSE"; then
    print_result "Access tasks without auth → 401" "401" "401" "Unauthorized"
else
    print_result "Access tasks without auth → 401" "401" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi
TOKEN="$OLD_TOKEN"

# Phase 5.4: Business Logic Tests
echo ""
echo "--- Phase 5.4: Business Logic Tests ---"

COMPLETE_TASK_TITLE="CompleteTest-$(date +%s)-$RANDOM"
RESPONSE=$(api_json POST "/tasks" "{\"title\":\"$COMPLETE_TASK_TITLE\",\"column_id\":\"$COLUMN_ID\"}")
COMPLETE_TASK_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$COMPLETE_TASK_ID" ] && COMPLETE_TASK_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")

if [ -n "$COMPLETE_TASK_ID" ]; then
    RESPONSE=$(api_json POST "/tasks/$COMPLETE_TASK_ID/complete" '{}')
    if [ "$(status_from_response "$RESPONSE")" = "200" ]; then
        if assert_db_timestamp "tasks" "$COMPLETE_TASK_ID" "completed_at"; then
            print_result "Completing task sets completed_at timestamp" "200" "200" "DB verification passed"
        else
            print_result "Task completion timestamp" "200" "FAIL" "DB verification failed"
        fi
        
        STATUS_VALUE=$(cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="echo DB::table('tasks')->where('id', '$COMPLETE_TASK_ID')->value('status');" 2>/dev/null || echo "")
        if [ "$STATUS_VALUE" = "completed" ]; then
            print_result "Completing task updates status to completed" "200" "200" "DB verification passed"
        else
            print_result "Task completion status update" "200" "FAIL" "DB verification failed"
        fi
    fi
    
    api_delete "/tasks/$COMPLETE_TASK_ID" > /dev/null 2>&1 || true
fi

ARCHIVE_TASK_TITLE="ArchiveTest-$(date +%s)-$RANDOM"
RESPONSE=$(api_json POST "/tasks" "{\"title\":\"$ARCHIVE_TASK_TITLE\",\"column_id\":\"$COLUMN_ID\"}")
ARCHIVE_TASK_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$ARCHIVE_TASK_ID" ] && ARCHIVE_TASK_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")

if [ -n "$ARCHIVE_TASK_ID" ]; then
    api_json POST "/tasks/$ARCHIVE_TASK_ID/archive" '{}' > /dev/null
    ARCHIVE_STATUS=$(cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="echo DB::table('tasks')->where('id', '$ARCHIVE_TASK_ID')->value('status');" 2>/dev/null || echo "")
    if [ "$ARCHIVE_STATUS" = "archived" ]; then
        print_result "Archiving task sets status to archived" "200" "200" "DB verification passed"
    else
        print_result "Task archive status" "200" "FAIL" "DB verification failed"
    fi
    
    api_delete "/tasks/$ARCHIVE_TASK_ID" > /dev/null 2>&1 || true
fi

# Phase 5.5: Side Effects Verification
echo ""
echo "--- Phase 5.5: Side Effects Verification ---"

ACTIVITY_TASK_TITLE="ActivityTest-$(date +%s)-$RANDOM"
RESPONSE=$(api_json POST "/tasks" "{\"title\":\"$ACTIVITY_TASK_TITLE\",\"column_id\":\"$COLUMN_ID\"}")
ACTIVITY_TASK_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$ACTIVITY_TASK_ID" ] && ACTIVITY_TASK_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")

if [ -n "$ACTIVITY_TASK_ID" ]; then
    if assert_db_has "activities" "subject_id = '$ACTIVITY_TASK_ID' AND subject_type LIKE '%Task%'"; then
        print_result "Activity log created on task creation" "201" "201" "DB verification passed"
    else
        print_result "Activity log for task creation" "201" "FAIL" "DB verification failed"
    fi
    
    api_delete "/tasks/$ACTIVITY_TASK_ID" > /dev/null 2>&1 || true
fi

# Phase 5.6: Query Parameters & Filters
echo ""
echo "--- Phase 5.6: Query Parameters & Filters ---"

RESPONSE=$(api_get "/tasks?page=1&per_page=10")
assert_api "Task list with pagination" "200" "$RESPONSE"

RESPONSE=$(api_get "/tasks?column_id=$COLUMN_ID")
assert_api "Tasks filtered by column_id" "200" "$RESPONSE"

RESPONSE=$(api_get "/tasks?priority=high")
assert_api "Tasks filtered by priority" "200" "$RESPONSE"

RESPONSE=$(api_get "/tasks?status=todo")
assert_api "Tasks filtered by status" "200" "$RESPONSE"

RESPONSE=$(api_get "/tasks?search=test")
assert_api "Tasks with search parameter" "200" "$RESPONSE"

RESPONSE=$(api_get "/tasks?sort=priority")
assert_api "Tasks sorted by priority" "200" "$RESPONSE"

RESPONSE=$(api_get "/tasks/overdue")
assert_api "Overdue tasks endpoint" "200" "$RESPONSE"

# Cleanup
if [ -n "$TASK_ID" ]; then
    api_delete "/tasks/$TASK_ID" > /dev/null 2>&1 || true
fi

cleanup_common_records

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
print_summary_and_exit
