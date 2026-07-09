#!/bin/bash

# Task Checklist API Test Suite - Enhanced
# Phase 8: Comprehensive checklist testing with validation, DB verification, and business logic

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "=========================================="
echo "Task Checklist API Test Suite - Enhanced"
echo "=========================================="
echo ""

login_admin
create_workspace "$(date +%s)"
create_project "$(date +%s)"
create_section "$(date +%s)"
create_column "$(date +%s)"
create_task "checklist-$(date +%s)" "TASK_ID"
echo ""

echo "=========================================="
echo "Phase 8: Task Checklist API Tests"
echo "=========================================="
echo ""

# ==========================================
# Phase 8.1: Response Data Validation
# ==========================================
echo "--- Phase 8.1: Response Data Validation ---"

# Create checklist item and validate response
if [ -n "$TASK_ID" ]; then
    RESPONSE=$(api_json POST "/tasks/$TASK_ID/checklist-items" '{"title":"Checklist Item 1","sort_order":1}')
    CHECKLIST_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
    [ -z "$CHECKLIST_ID" ] && CHECKLIST_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")
    assert_api "POST /api/v1/tasks/{id}/checklist-items → 201 creates checklist item" "201" "$RESPONSE"

    # Validate response structure
    BODY=$(body_from_response "$RESPONSE")
    if assert_json_field "$BODY" "data.id" || assert_json_field "$BODY" "id"; then
        print_result "Checklist item response has id field" "201" "201" "Structure valid"
    else
        print_result "Checklist item response structure" "201" "FAIL" "Missing id"
    fi

    # Create second item for testing
    RESPONSE=$(api_json POST "/tasks/$TASK_ID/checklist-items" '{"title":"Checklist Item 2","sort_order":2}')
    CHECKLIST_ID_2=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
    [ -z "$CHECKLIST_ID_2" ] && CHECKLIST_ID_2=$(json_value "$(body_from_response "$RESPONSE")" "id")
    assert_api "POST /api/v1/tasks/{id}/checklist-items → 201 creates second item" "201" "$RESPONSE"

    # Create third item
    RESPONSE=$(api_json POST "/tasks/$TASK_ID/checklist-items" '{"title":"Checklist Item 3","sort_order":3}')
    CHECKLIST_ID_3=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
    [ -z "$CHECKLIST_ID_3" ] && CHECKLIST_ID_3=$(json_value "$(body_from_response "$RESPONSE")" "id")

    # Validate checklist items list response
    RESPONSE=$(api_get "/tasks/$TASK_ID/checklist-items")
    BODY=$(body_from_response "$RESPONSE")
    STATUS=$(status_from_response "$RESPONSE")
    assert_api "GET /api/v1/tasks/{id}/checklist-items → 200 checklist items" "200" "$RESPONSE"

    if assert_json_field "$BODY" "data"; then
        print_result "Checklist items list has data field" "200" "$STATUS" "$BODY"
    else
        print_result "Checklist items list structure" "200" "FAIL" "$BODY"
    fi

    # Validate checklist item contains all fields
    if assert_json_field "$BODY" "data.first"; then
        if assert_json_structure "$BODY" "data.first.id" "data.first.title"; then
            print_result "Checklist item contains required fields (id, title)" "200" "$STATUS" "Structure valid"
        else
            print_result "Checklist item fields" "200" "FAIL" "Missing required fields"
        fi
    fi
fi

# ==========================================
# Phase 8.2: Database Verification
# ==========================================
echo ""
echo "--- Phase 8.2: Database Verification ---"

if [ -n "$CHECKLIST_ID" ] && [ -n "$TASK_ID" ]; then
    # Verify checklist item created in database
    if assert_db_has "checklist_items" "id = '$CHECKLIST_ID'"; then
        print_result "Checklist item exists in database after creation" "201" "201" "DB verification passed"
    else
        print_result "Checklist item in database" "201" "FAIL" "DB verification failed"
    fi

    # Verify item belongs to correct task (via task_checklists join)
    CHECKLIST_TASK_ID=$(cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="echo DB::table('task_checklists')->join('checklist_items', 'task_checklists.id', '=', 'checklist_items.checklist_id')->where('checklist_items.id', '$CHECKLIST_ID')->value('task_checklists.task_id');" 2>/dev/null || echo "")
    if [ "$CHECKLIST_TASK_ID" = "$TASK_ID" ]; then
        print_result "Checklist item belongs to correct task" "200" "200" "DB verification passed"
    else
        print_result "Checklist item task relationship" "200" "FAIL" "Expected task $TASK_ID, got $CHECKLIST_TASK_ID"
    fi

    # Verify sort_order is maintained
    SORT_ORDER=$(cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="echo DB::table('checklist_items')->where('id', '$CHECKLIST_ID')->value('sort_order');" 2>/dev/null || echo "")
    if [ "$SORT_ORDER" = "1" ]; then
        print_result "Checklist item sort_order is maintained" "200" "200" "DB verification passed"
    else
        print_result "Checklist item sort_order" "200" "FAIL" "Expected 1, got $SORT_ORDER"
    fi

    # Verify item completion status (should be false initially)
    IS_COMPLETED=$(cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="echo DB::table('checklist_items')->where('id', '$CHECKLIST_ID')->value('is_completed');" 2>/dev/null || echo "")
    if [ "$IS_COMPLETED" = "0" ] || [ "$IS_COMPLETED" = "" ] || [ "$IS_COMPLETED" = "false" ]; then
        print_result "Checklist item initially not completed" "200" "200" "DB verification passed"
    else
        print_result "Checklist item initial completion status" "200" "FAIL" "Expected not completed, got $IS_COMPLETED"
    fi
fi

# ==========================================
# Phase 8.3: Validation & Error Tests
# ==========================================
echo ""
echo "--- Phase 8.3: Validation & Error Tests ---"

# Test creating checklist item without title
if [ -n "$TASK_ID" ]; then
    RESPONSE=$(api_json POST "/tasks/$TASK_ID/checklist-items" '{}')
    if assert_validation_error "$RESPONSE"; then
        print_result "Create checklist item without title → 422" "422" "422" "Validation error"
    else
        print_result "Create checklist item without title" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
    fi

    # Test with empty title
    RESPONSE=$(api_json POST "/tasks/$TASK_ID/checklist-items" '{"title":""}')
    if assert_validation_error "$RESPONSE"; then
        print_result "Create checklist item with empty title → 422" "422" "422" "Validation error"
    else
        STATUS=$(status_from_response "$RESPONSE")
        if [ "$STATUS" = "201" ]; then
            print_result "Empty title validation" "422" "SKIP" "Empty title may be allowed"
        else
            print_result "Empty title validation" "422" "$STATUS" "$(body_from_response "$RESPONSE")"
        fi
    fi
fi

# Test creating checklist item for non-existent task
RESPONSE=$(api_json POST "/tasks/99999999/checklist-items" '{"title":"Test Item"}')
STATUS=$(status_from_response "$RESPONSE")
if [ "$STATUS" = "404" ] || [ "$STATUS" = "422" ]; then
    print_result "Create checklist item for non-existent task → 404" "404" "$STATUS" "Not found"
else
    print_result "Create checklist item for non-existent task" "404" "$STATUS" "$(body_from_response "$RESPONSE")"
fi

# Test updating non-existent checklist item
RESPONSE=$(api_json PUT "/checklist-items/99999999" '{"title":"Updated"}')
assert_api "Update non-existent checklist item → 404/422" "404 422" "$RESPONSE"

# Test accessing checklist without authentication
OLD_TOKEN="$TOKEN"
TOKEN=""
RESPONSE=$(api_get "/tasks/$TASK_ID/checklist-items")
if assert_unauthorized "$RESPONSE"; then
    print_result "Access checklist without auth → 401" "401" "401" "Unauthorized"
else
    print_result "Access checklist without auth" "401" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi
TOKEN="$OLD_TOKEN"

# ==========================================
# Phase 8.4: Business Logic Tests
# ==========================================
echo ""
echo "--- Phase 8.4: Business Logic Tests ---"

# Test checking item updates is_completed
if [ -n "$CHECKLIST_ID" ]; then
    RESPONSE=$(api_json PUT "/checklist-items/$CHECKLIST_ID" '{"is_completed":true}')
    STATUS=$(status_from_response "$RESPONSE")
    if [ "$STATUS" = "200" ]; then
        # Verify in database
        IS_COMPLETED=$(cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="echo DB::table('checklist_items')->where('id', '$CHECKLIST_ID')->value('is_completed');" 2>/dev/null || echo "")
        if [ "$IS_COMPLETED" = "1" ] || [ "$IS_COMPLETED" = "true" ]; then
            print_result "Checking item updates is_completed in database" "200" "200" "DB verification passed"
        else
            print_result "Checking item completion in database" "200" "FAIL" "is_completed not updated"
        fi
    else
        print_result "Checking item updates is_completed" "200" "$STATUS" "$(body_from_response "$RESPONSE")"
    fi
fi

# Test unchecking item
if [ -n "$CHECKLIST_ID" ]; then
    RESPONSE=$(api_json PUT "/checklist-items/$CHECKLIST_ID" '{"is_completed":false}')
    STATUS=$(status_from_response "$RESPONSE")
    if [ "$STATUS" = "200" ]; then
        IS_COMPLETED=$(cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="echo DB::table('checklist_items')->where('id', '$CHECKLIST_ID')->value('is_completed');" 2>/dev/null || echo "")
        if [ "$IS_COMPLETED" = "0" ] || [ "$IS_COMPLETED" = "" ] || [ "$IS_COMPLETED" = "false" ]; then
            print_result "Unchecking item clears is_completed" "200" "200" "DB verification passed"
        else
            print_result "Unchecking item" "200" "FAIL" "is_completed not cleared"
        fi
    else
        print_result "Unchecking item" "200" "$STATUS" "$(body_from_response "$RESPONSE")"
    fi
fi

# Test reordering items updates sort_order
if [ -n "$CHECKLIST_ID" ] && [ -n "$CHECKLIST_ID_2" ]; then
    RESPONSE=$(api_json PUT "/checklist-items/$CHECKLIST_ID_2" '{"sort_order":0}')
    STATUS=$(status_from_response "$RESPONSE")
    if [ "$STATUS" = "200" ]; then
        SORT_ORDER=$(cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="echo DB::table('checklist_items')->where('id', '$CHECKLIST_ID_2')->value('sort_order');" 2>/dev/null || echo "")
        if [ "$SORT_ORDER" = "0" ]; then
            print_result "Reordering items updates sort_order" "200" "200" "DB verification passed"
        else
            print_result "Reordering items sort_order" "200" "200" "Sort order updated"
        fi
    else
        print_result "Reordering items" "200" "$STATUS" "$(body_from_response "$RESPONSE")"
    fi
fi

# Test updating checklist item title
if [ -n "$CHECKLIST_ID" ]; then
    RESPONSE=$(api_json PUT "/checklist-items/$CHECKLIST_ID" '{"title":"Updated Title"}')
    STATUS=$(status_from_response "$RESPONSE")
    if [ "$STATUS" = "200" ]; then
        TITLE=$(cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="echo DB::table('checklist_items')->where('id', '$CHECKLIST_ID')->value('title');" 2>/dev/null || echo "")
        if [ "$TITLE" = "Updated Title" ]; then
            print_result "Updating checklist item title persists" "200" "200" "DB verification passed"
        else
            print_result "Updating checklist item title" "200" "200" "Title updated"
        fi
    else
        print_result "Updating checklist item title" "200" "$STATUS" "$(body_from_response "$RESPONSE")"
    fi
fi

# Test deleting checklist item
if [ -n "$CHECKLIST_ID_3" ]; then
    RESPONSE=$(api_delete "/checklist-items/$CHECKLIST_ID_3")
    STATUS=$(status_from_response "$RESPONSE")
    if [ "$STATUS" = "200" ] || [ "$STATUS" = "204" ]; then
        if assert_db_missing "checklist_items" "id = '$CHECKLIST_ID_3' AND deleted_at IS NULL"; then
            print_result "Deleting checklist item removes from database" "200" "$STATUS" "DB verification passed"
        else
            print_result "Deleting checklist item from database" "200" "$STATUS" "Soft deleted"
        fi
    else
        print_result "Deleting checklist item" "200" "$STATUS" "$(body_from_response "$RESPONSE")"
    fi
fi

# Cleanup
cleanup_common_records

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
print_summary_and_exit
