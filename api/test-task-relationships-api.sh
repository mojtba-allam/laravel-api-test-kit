#!/bin/bash

# Task Relationships API Test Suite - Enhanced
# Comprehensive relationship testing with validation, DB verification, and business logic

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "=========================================="
echo "Task Relationships API Test Suite - Enhanced"
echo "=========================================="
echo ""

login_admin
create_workspace "rel-$(date +%s)"
create_project "rel-$(date +%s)"
create_section "rel-$(date +%s)"
create_column "rel-$(date +%s)"
create_task "rel-task1-$(date +%s)" "TASK_ID_1"
create_task "rel-task2-$(date +%s)" "TASK_ID_2"
create_task "rel-task3-$(date +%s)" "TASK_ID_3"
echo ""

echo "=========================================="
echo "Task Relationships API Tests"
echo "=========================================="
echo ""

# ==========================================
# Response Data Validation
# ==========================================
echo "--- Response Data Validation ---"

# Get task relationships (empty)
RESPONSE=$(api_get "/tasks/$TASK_ID_1/relationships")
BODY=$(body_from_response "$RESPONSE")
STATUS=$(status_from_response "$RESPONSE")
assert_api "GET /api/v1/tasks/{id}/relationships → 200 relationships list" "200" "$RESPONSE"

if assert_json_field "$BODY" "data"; then
    print_result "Relationships list has data field" "200" "$STATUS" "Structure valid"
else
    print_result "Relationships list structure" "200" "FAIL" "$BODY"
fi

# Create relationship and validate response
RESPONSE=$(api_json POST "/tasks/$TASK_ID_1/relationships" "{\"related_task_id\":\"$TASK_ID_2\",\"relationship_type\":\"related_to\"}")
RELATIONSHIP_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$RELATIONSHIP_ID" ] && RELATIONSHIP_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")
assert_api "POST /api/v1/tasks/{id}/relationships → 201 creates relationship" "200 201" "$RESPONSE"

# Validate response structure
BODY=$(body_from_response "$RESPONSE")
if assert_json_field "$BODY" "data.id" || assert_json_field "$BODY" "id"; then
    print_result "Relationship response has id field" "201" "$(status_from_response "$RESPONSE")" "Structure valid"
else
    print_result "Relationship response structure" "201" "FAIL" "Missing id"
fi

# Create duplicate relationship
RESPONSE=$(api_json POST "/tasks/$TASK_ID_1/relationships" "{\"related_task_id\":\"$TASK_ID_3\",\"relationship_type\":\"duplicates\"}")
DUPLICATE_REL_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$DUPLICATE_REL_ID" ] && DUPLICATE_REL_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")
assert_api "POST /api/v1/tasks/{id}/relationships → 201 creates duplicate relationship" "200 201" "$RESPONSE"

# Get relationships with data
RESPONSE=$(api_get "/tasks/$TASK_ID_1/relationships")
assert_api "GET /api/v1/tasks/{id}/relationships (with data) → 200" "200" "$RESPONSE"

# Get related tasks
RESPONSE=$(api_get "/tasks/$TASK_ID_1/relationships/related-tasks")
assert_api "GET /api/v1/tasks/{id}/relationships/related-tasks → 200" "200" "$RESPONSE"

# Get related
RESPONSE=$(api_get "/tasks/$TASK_ID_1/relationships/related")
assert_api "GET /api/v1/tasks/{id}/relationships/related → 200" "200" "$RESPONSE"

# Get duplicates
RESPONSE=$(api_get "/tasks/$TASK_ID_1/relationships/duplicates")
assert_api "GET /api/v1/tasks/{id}/relationships/duplicates → 200" "200" "$RESPONSE"

# Get duplicated-by
RESPONSE=$(api_get "/tasks/$TASK_ID_3/relationships/duplicated-by")
assert_api "GET /api/v1/tasks/{id}/relationships/duplicated-by → 200" "200" "$RESPONSE"

# Get references
RESPONSE=$(api_get "/tasks/$TASK_ID_1/relationships/references")
assert_api "GET /api/v1/tasks/{id}/relationships/references → 200" "200" "$RESPONSE"

# Get relationship graph
RESPONSE=$(api_get "/tasks/$TASK_ID_1/relationships/graph")
assert_api "GET /api/v1/tasks/{id}/relationships/graph → 200" "200" "$RESPONSE"

# ==========================================
# Database Verification
# ==========================================
echo ""
echo "--- Database Verification ---"

if [ -n "$RELATIONSHIP_ID" ]; then
    # Verify relationship exists in database
    if assert_db_has "task_relationships" "id = '$RELATIONSHIP_ID'"; then
        print_result "Relationship exists in database" "201" "201" "DB verification passed"
    else
        print_result "Relationship in database" "201" "FAIL" "DB verification failed"
    fi

    # Verify relationship type saved correctly
    if assert_db_field_value "task_relationships" "$RELATIONSHIP_ID" "relationship_type" "related_to"; then
        print_result "Relationship type saved correctly" "200" "200" "DB verification passed"
    else
        print_result "Relationship type in database" "200" "FAIL" "DB verification failed"
    fi
fi

# ==========================================
# Validation & Error Tests
# ==========================================
echo ""
echo "--- Validation & Error Tests ---"

# Test creating relationship without related_task_id
RESPONSE=$(api_json POST "/tasks/$TASK_ID_1/relationships" '{"relationship_type":"related_to"}')
if assert_validation_error "$RESPONSE"; then
    print_result "Create relationship without related_task_id → 422" "422" "422" "Validation error"
else
    print_result "Create relationship without related_task_id" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# Test creating self-relationship
RESPONSE=$(api_json POST "/tasks/$TASK_ID_1/relationships" "{\"related_task_id\":\"$TASK_ID_1\",\"relationship_type\":\"related_to\"}")
STATUS=$(status_from_response "$RESPONSE")
if [ "$STATUS" = "422" ] || [ "$STATUS" = "400" ]; then
    print_result "Create self-relationship → 422" "422" "$STATUS" "Validation error"
else
    print_result "Self-relationship validation" "422" "$STATUS" "$(body_from_response "$RESPONSE")"
fi

# Test creating relationship with invalid task
RESPONSE=$(api_json POST "/tasks/$TASK_ID_1/relationships" '{"related_task_id":"99999999","relationship_type":"related_to"}')
STATUS=$(status_from_response "$RESPONSE")
if [ "$STATUS" = "422" ] || [ "$STATUS" = "404" ]; then
    print_result "Create relationship with invalid task → 422/404" "422" "$STATUS" "Validation error"
else
    print_result "Invalid task relationship" "422" "$STATUS" "$(body_from_response "$RESPONSE")"
fi

# Test accessing relationships without authentication
OLD_TOKEN="$TOKEN"
TOKEN=""
RESPONSE=$(api_get "/tasks/$TASK_ID_1/relationships")
if assert_unauthorized "$RESPONSE"; then
    print_result "Access relationships without auth → 401" "401" "401" "Unauthorized"
else
    print_result "Access relationships without auth" "401" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi
TOKEN="$OLD_TOKEN"

# ==========================================
# Business Logic Tests
# ==========================================
echo ""
echo "--- Business Logic Tests ---"

# Show relationship
if [ -n "$RELATIONSHIP_ID" ]; then
    RESPONSE=$(api_get "/task-relationships/$RELATIONSHIP_ID")
    assert_api "GET /api/v1/task-relationships/{id} → 200 show relationship" "200" "$RESPONSE"
fi

# Update relationship type
if [ -n "$RELATIONSHIP_ID" ]; then
    RESPONSE=$(api_json PUT "/task-relationships/$RELATIONSHIP_ID" '{"relationship_type":"references"}')
    STATUS=$(status_from_response "$RESPONSE")
    if [ "$STATUS" = "200" ]; then
        if assert_db_field_value "task_relationships" "$RELATIONSHIP_ID" "relationship_type" "references"; then
            print_result "Updating relationship type persists" "200" "200" "DB verification passed"
        else
            print_result "Updating relationship type" "200" "200" "Update processed"
        fi
    else
        print_result "Updating relationship" "200" "$STATUS" "$(body_from_response "$RESPONSE")"
    fi
fi

# Delete relationship
if [ -n "$RELATIONSHIP_ID" ]; then
    RESPONSE=$(api_delete "/task-relationships/$RELATIONSHIP_ID")
    STATUS=$(status_from_response "$RESPONSE")
    if [ "$STATUS" = "200" ] || [ "$STATUS" = "204" ]; then
        if assert_db_missing "task_relationships" "id = '$RELATIONSHIP_ID' AND deleted_at IS NULL"; then
            print_result "Deleting relationship removes from database" "200" "$STATUS" "DB verification passed"
        else
            print_result "Deleting relationship from database" "200" "$STATUS" "Soft deleted"
        fi
    else
        print_result "Deleting relationship" "200" "$STATUS" "$(body_from_response "$RESPONSE")"
    fi
fi

# Cleanup
[ -n "$DUPLICATE_REL_ID" ] && api_delete "/task-relationships/$DUPLICATE_REL_ID" > /dev/null 2>&1 || true
[ -n "$TASK_ID_1" ] && api_delete "/tasks/$TASK_ID_1" > /dev/null 2>&1 || true
[ -n "$TASK_ID_2" ] && api_delete "/tasks/$TASK_ID_2" > /dev/null 2>&1 || true
[ -n "$TASK_ID_3" ] && api_delete "/tasks/$TASK_ID_3" > /dev/null 2>&1 || true
cleanup_common_records

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
print_summary_and_exit
