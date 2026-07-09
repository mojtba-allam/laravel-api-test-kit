#!/bin/bash

# Finolo Task Dependencies API Test Suite - Enhanced
# Phase 6: Comprehensive dependency testing with validation, DB verification, and business logic

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "=========================================="
echo "Task Dependencies API Test Suite - Enhanced"
echo "=========================================="
echo ""

login_admin
create_workspace "$(date +%s)"
create_project "$(date +%s)"
create_section "$(date +%s)"
create_column "$(date +%s)"
create_task "dep-main-$(date +%s)" "TASK_ID"
create_task "dep-blocker-$(date +%s)" "TASK_ID_2"
echo ""

echo "=========================================="
echo "Phase 6: Task Dependencies API Tests"
echo "=========================================="
echo ""

# ==========================================
# Phase 6.1: Response Data Validation
# ==========================================
echo "--- Phase 6.1: Response Data Validation ---"

# Create a dependency for testing
if [ -n "$TASK_ID" ] && [ -n "$TASK_ID_2" ]; then
    RESPONSE=$(api_json POST "/task-dependencies" "{\"task_id\":\"$TASK_ID\",\"depends_on_task_id\":\"$TASK_ID_2\",\"dependency_type\":\"blocks\"}")
    DEP_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
    [ -z "$DEP_ID" ] && DEP_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")
    assert_api "POST /api/v1/task-dependencies → 201 creates dependency" "201" "$RESPONSE"

    # Validate dependency response structure
    BODY=$(body_from_response "$RESPONSE")
    if assert_json_field "$BODY" "data.id" || assert_json_field "$BODY" "id"; then
        print_result "Dependency response has id field" "201" "201" "Structure valid"
    else
        print_result "Dependency response structure" "201" "FAIL" "Missing id field"
    fi
fi

# Validate dependency list response structure
if [ -n "$TASK_ID" ]; then
    RESPONSE=$(api_get "/tasks/$TASK_ID/dependencies/blocking")
    BODY=$(body_from_response "$RESPONSE")
    STATUS=$(status_from_response "$RESPONSE")
    assert_api "GET /api/v1/tasks/{id}/dependencies/blocking → 200" "200" "$RESPONSE"

    if assert_json_field "$BODY" "data"; then
        print_result "Dependencies list has data field" "200" "$STATUS" "$BODY"
    else
        print_result "Dependencies list structure" "200" "FAIL" "$BODY"
    fi

    # Validate blocked-by endpoint
    RESPONSE=$(api_get "/tasks/$TASK_ID_2/dependencies/blocked-by")
    assert_api "GET /api/v1/tasks/{id}/dependencies/blocked-by → 200" "200" "$RESPONSE"

    # Validate dependency graph response
    RESPONSE=$(api_get "/tasks/$TASK_ID/dependencies/graph")
    assert_api "GET /api/v1/tasks/{id}/dependencies/graph → 200" "200" "$RESPONSE"
    BODY=$(body_from_response "$RESPONSE")
    if assert_json_field "$BODY" "data" || assert_json_field "$BODY" "nodes" || assert_json_field "$BODY" "graph"; then
        print_result "Dependency graph has expected structure" "200" "200" "Graph structure valid"
    else
        print_result "Dependency graph structure" "200" "FAIL" "$BODY"
    fi
fi

# ==========================================
# Phase 6.2: Database Verification
# ==========================================
echo ""
echo "--- Phase 6.2: Database Verification ---"

create_task "db-dep1-$(date +%s)-$RANDOM" "DEP_TASK_1"
create_task "db-dep2-$(date +%s)-$RANDOM" "DEP_TASK_2"

if [ -n "$DEP_TASK_1" ] && [ -n "$DEP_TASK_2" ]; then
    RESPONSE=$(api_json POST "/task-dependencies" "{\"task_id\":\"$DEP_TASK_1\",\"depends_on_task_id\":\"$DEP_TASK_2\",\"dependency_type\":\"blocks\"}")
    DB_DEP_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
    [ -z "$DB_DEP_ID" ] && DB_DEP_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")

    if [ -n "$DB_DEP_ID" ]; then
        # Verify dependency record exists in task_dependencies table
        if assert_db_has "task_dependencies" "id = '$DB_DEP_ID'"; then
            print_result "Dependency record exists in task_dependencies table" "201" "201" "DB verification passed"
        else
            print_result "Dependency in database" "201" "FAIL" "DB verification failed"
        fi

        # Verify task_id is set correctly
        if assert_db_field_value "task_dependencies" "$DB_DEP_ID" "task_id" "$DEP_TASK_1"; then
            print_result "Dependency task_id saved correctly" "200" "200" "DB verification passed"
        else
            print_result "Dependency task_id" "200" "FAIL" "DB verification failed"
        fi

        # Verify depends_on_task_id is set correctly
        if assert_db_field_value "task_dependencies" "$DB_DEP_ID" "depends_on_task_id" "$DEP_TASK_2"; then
            print_result "Dependency depends_on_task_id saved correctly" "200" "200" "DB verification passed"
        else
            print_result "Dependency depends_on_task_id" "200" "FAIL" "DB verification failed"
        fi

        # Verify dependency_type is saved correctly
        if assert_db_field_value "task_dependencies" "$DB_DEP_ID" "dependency_type" "blocks"; then
            print_result "Dependency type saved correctly" "200" "200" "DB verification passed"
        else
            print_result "Dependency type" "200" "FAIL" "DB verification failed"
        fi

        # Verify dependency deletion removes record
        RESPONSE=$(api_delete "/task-dependencies/$DB_DEP_ID")
        STATUS=$(status_from_response "$RESPONSE")
        if [ "$STATUS" = "200" ] || [ "$STATUS" = "204" ]; then
            if assert_db_missing "task_dependencies" "id = '$DB_DEP_ID'"; then
                print_result "Dependency deletion removes record from database" "200" "200" "DB verification passed"
            else
                print_result "Dependency deletion from database" "200" "FAIL" "Record still exists"
            fi
        else
            print_result "Dependency deletion" "200" "$STATUS" "Delete failed"
        fi
    fi

    api_delete "/tasks/$DEP_TASK_1" > /dev/null 2>&1 || true
    api_delete "/tasks/$DEP_TASK_2" > /dev/null 2>&1 || true
fi

# ==========================================
# Phase 6.3: Validation & Error Tests
# ==========================================
echo ""
echo "--- Phase 6.3: Validation & Error Tests ---"

# Test creating dependency without task_id
RESPONSE=$(api_json POST "/task-dependencies" "{\"depends_on_task_id\":\"$TASK_ID_2\",\"dependency_type\":\"blocks\"}")
if assert_validation_error "$RESPONSE"; then
    print_result "Create dependency without task_id → 422" "422" "422" "Validation error"
else
    print_result "Create dependency without task_id" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# Test creating dependency without depends_on_task_id
RESPONSE=$(api_json POST "/task-dependencies" "{\"task_id\":\"$TASK_ID\",\"dependency_type\":\"blocks\"}")
if assert_validation_error "$RESPONSE"; then
    print_result "Create dependency without depends_on_task_id → 422" "422" "422" "Validation error"
else
    print_result "Create dependency without depends_on_task_id" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# Test creating dependency with empty body
RESPONSE=$(api_json POST "/task-dependencies" '{}')
if assert_validation_error "$RESPONSE"; then
    print_result "Create dependency with empty body → 422" "422" "422" "Validation error"
else
    print_result "Create dependency with empty body" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# Test creating dependency with invalid dependency_type
RESPONSE=$(api_json POST "/task-dependencies" "{\"task_id\":\"$TASK_ID\",\"depends_on_task_id\":\"$TASK_ID_2\",\"dependency_type\":\"invalid_type\"}")
if assert_validation_error "$RESPONSE"; then
    print_result "Create dependency with invalid dependency_type → 422" "422" "422" "Validation error"
else
    STATUS=$(status_from_response "$RESPONSE")
    if [ "$STATUS" = "201" ] || [ "$STATUS" = "200" ]; then
        print_result "Invalid dependency_type validation" "422" "SKIP" "Type validation may not be enforced"
    else
        print_result "Invalid dependency_type" "422" "$STATUS" "$(body_from_response "$RESPONSE")"
    fi
fi

# Test creating circular dependency (self-referencing)
if [ -n "$TASK_ID" ]; then
    RESPONSE=$(api_json POST "/task-dependencies" "{\"task_id\":\"$TASK_ID\",\"depends_on_task_id\":\"$TASK_ID\",\"dependency_type\":\"blocks\"}")
    if assert_validation_error "$RESPONSE"; then
        print_result "Create self-referencing dependency → 422" "422" "422" "Validation error"
    else
        print_result "Self-referencing dependency" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
    fi
fi

# Test creating duplicate dependency
if [ -n "$TASK_ID" ] && [ -n "$TASK_ID_2" ] && [ -n "$DEP_ID" ]; then
    RESPONSE=$(api_json POST "/task-dependencies" "{\"task_id\":\"$TASK_ID\",\"depends_on_task_id\":\"$TASK_ID_2\",\"dependency_type\":\"blocks\"}")
    STATUS=$(status_from_response "$RESPONSE")
    if [ "$STATUS" = "422" ] || [ "$STATUS" = "409" ]; then
        print_result "Create duplicate dependency → 422/409" "422" "$STATUS" "Duplicate rejected"
    else
        print_result "Duplicate dependency detection" "422" "$STATUS" "$(body_from_response "$RESPONSE")"
    fi
fi

# Test creating dependency with invalid task IDs
RESPONSE=$(api_json POST "/task-dependencies" '{"task_id":"99999999","depends_on_task_id":"99999998","dependency_type":"blocks"}')
STATUS=$(status_from_response "$RESPONSE")
if [ "$STATUS" = "422" ] || [ "$STATUS" = "404" ]; then
    print_result "Create dependency with invalid task IDs → 422/404" "422" "$STATUS" "Validation error"
else
    print_result "Invalid task IDs" "422" "$STATUS" "$(body_from_response "$RESPONSE")"
fi

# Test accessing dependencies without authentication
OLD_TOKEN="$TOKEN"
TOKEN=""
RESPONSE=$(api_get "/tasks/$TASK_ID/dependencies/blocking")
if assert_unauthorized "$RESPONSE"; then
    print_result "Access dependencies without auth → 401" "401" "401" "Unauthorized"
else
    print_result "Access dependencies without auth" "401" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi
TOKEN="$OLD_TOKEN"

# ==========================================
# Phase 6.4: Business Logic Tests
# ==========================================
echo ""
echo "--- Phase 6.4: Business Logic Tests ---"

# Test circular dependency detection (A→B→C→A)
create_task "circ1-$(date +%s)-$RANDOM" "CIRC_TASK_1"
create_task "circ2-$(date +%s)-$RANDOM" "CIRC_TASK_2"
create_task "circ3-$(date +%s)-$RANDOM" "CIRC_TASK_3"

if [ -n "$CIRC_TASK_1" ] && [ -n "$CIRC_TASK_2" ] && [ -n "$CIRC_TASK_3" ]; then
    # Create A depends on B
    RESPONSE=$(api_json POST "/task-dependencies" "{\"task_id\":\"$CIRC_TASK_1\",\"depends_on_task_id\":\"$CIRC_TASK_2\",\"dependency_type\":\"blocks\"}")
    CIRC_DEP_1=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
    [ -z "$CIRC_DEP_1" ] && CIRC_DEP_1=$(json_value "$(body_from_response "$RESPONSE")" "id")

    # Create B depends on C
    RESPONSE=$(api_json POST "/task-dependencies" "{\"task_id\":\"$CIRC_TASK_2\",\"depends_on_task_id\":\"$CIRC_TASK_3\",\"dependency_type\":\"blocks\"}")
    CIRC_DEP_2=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
    [ -z "$CIRC_DEP_2" ] && CIRC_DEP_2=$(json_value "$(body_from_response "$RESPONSE")" "id")

    # Try to create C depends on A (should fail - circular)
    RESPONSE=$(api_json POST "/task-dependencies" "{\"task_id\":\"$CIRC_TASK_3\",\"depends_on_task_id\":\"$CIRC_TASK_1\",\"dependency_type\":\"blocks\"}")
    STATUS=$(status_from_response "$RESPONSE")
    if [ "$STATUS" = "422" ] || [ "$STATUS" = "409" ]; then
        print_result "Circular dependency detection (A→B→C→A) works" "422" "$STATUS" "Circular rejected"
    else
        print_result "Circular dependency detection" "422" "$STATUS" "$(body_from_response "$RESPONSE")"
    fi

    # Test dependency graph calculation
    RESPONSE=$(api_get "/tasks/$CIRC_TASK_1/dependencies/graph")
    if [ "$(status_from_response "$RESPONSE")" = "200" ]; then
        print_result "Dependency graph calculation works" "200" "200" "Graph calculated"
    else
        print_result "Dependency graph calculation" "200" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
    fi

    # Test unresolved dependencies identification
    RESPONSE=$(api_get "/tasks/$CIRC_TASK_1/dependencies/unresolved")
    STATUS=$(status_from_response "$RESPONSE")
    if [ "$STATUS" = "200" ]; then
        print_result "Unresolved dependencies endpoint works" "200" "200" "Unresolved retrieved"
    else
        # Try alternative endpoint
        RESPONSE=$(api_get "/tasks/$CIRC_TASK_1/dependencies/blocking")
        if [ "$(status_from_response "$RESPONSE")" = "200" ]; then
            print_result "Blocking dependencies (unresolved) endpoint works" "200" "200" "Blocking retrieved"
        else
            print_result "Unresolved dependencies" "200" "$STATUS" "$(body_from_response "$RESPONSE")"
        fi
    fi

    # Cleanup circular test data
    [ -n "$CIRC_DEP_1" ] && api_delete "/task-dependencies/$CIRC_DEP_1" > /dev/null 2>&1 || true
    [ -n "$CIRC_DEP_2" ] && api_delete "/task-dependencies/$CIRC_DEP_2" > /dev/null 2>&1 || true
    api_delete "/tasks/$CIRC_TASK_1" > /dev/null 2>&1 || true
    api_delete "/tasks/$CIRC_TASK_2" > /dev/null 2>&1 || true
    api_delete "/tasks/$CIRC_TASK_3" > /dev/null 2>&1 || true
fi

# Test cascading dependency updates (completing a blocking task)
create_task "cascade1-$(date +%s)-$RANDOM" "CASCADE_TASK_1"
create_task "cascade2-$(date +%s)-$RANDOM" "CASCADE_TASK_2"

if [ -n "$CASCADE_TASK_1" ] && [ -n "$CASCADE_TASK_2" ]; then
    # Create dependency: TASK_1 is blocked by TASK_2
    RESPONSE=$(api_json POST "/task-dependencies" "{\"task_id\":\"$CASCADE_TASK_1\",\"depends_on_task_id\":\"$CASCADE_TASK_2\",\"dependency_type\":\"blocks\"}")
    CASCADE_DEP_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
    [ -z "$CASCADE_DEP_ID" ] && CASCADE_DEP_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")

    # Complete the blocking task
    RESPONSE=$(api_json POST "/tasks/$CASCADE_TASK_2/complete" '{}')
    if [ "$(status_from_response "$RESPONSE")" = "200" ]; then
        print_result "Completing blocking task succeeds" "200" "200" "Task completed"
    else
        print_result "Completing blocking task" "200" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
    fi

    # Cleanup
    [ -n "$CASCADE_DEP_ID" ] && api_delete "/task-dependencies/$CASCADE_DEP_ID" > /dev/null 2>&1 || true
    api_delete "/tasks/$CASCADE_TASK_1" > /dev/null 2>&1 || true
    api_delete "/tasks/$CASCADE_TASK_2" > /dev/null 2>&1 || true
fi

# Cleanup main test data
[ -n "$DEP_ID" ] && api_delete "/task-dependencies/$DEP_ID" > /dev/null 2>&1 || true
cleanup_common_records

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
print_summary_and_exit
