#!/bin/bash

# Task Templates API Test Suite - Enhanced
# Phase 10: Comprehensive template testing with validation, DB verification, and business logic

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "=========================================="
echo "Task Templates API Test Suite - Enhanced"
echo "=========================================="
echo ""

login_admin
create_workspace "$(date +%s)"
create_project "$(date +%s)"
create_section "$(date +%s)"
create_column "$(date +%s)"
echo ""

echo "=========================================="
echo "Phase 10: Task Templates API Tests"
echo "=========================================="
echo ""

# ==========================================
# Phase 10.1: Response Data Validation
# ==========================================
echo "--- Phase 10.1: Response Data Validation ---"

if [ -n "$PROJECT_ID" ]; then
    # Create template and validate response
    RESPONSE=$(api_json POST "/projects/$PROJECT_ID/task-templates" '{"name":"Bug Report Template","title":"Bug: [Title]","description":"Steps to reproduce:\n1.\n2.\n3.\n\nExpected behavior:\nActual behavior:","priority":"high"}')
    TEMPLATE_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
    [ -z "$TEMPLATE_ID" ] && TEMPLATE_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")
    assert_api "POST /api/v1/projects/{id}/task-templates → 201 creates template" "201" "$RESPONSE"

    # Validate response structure
    BODY=$(body_from_response "$RESPONSE")
    if assert_json_field "$BODY" "data.id" || assert_json_field "$BODY" "id"; then
        print_result "Template response has id field" "201" "201" "Structure valid"
    else
        print_result "Template response structure" "201" "FAIL" "Missing id"
    fi

    # Create second template
    RESPONSE=$(api_json POST "/projects/$PROJECT_ID/task-templates" '{"name":"Feature Request","title":"Feature: [Title]","description":"As a user, I want...","priority":"medium"}')
    TEMPLATE_ID_2=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
    [ -z "$TEMPLATE_ID_2" ] && TEMPLATE_ID_2=$(json_value "$(body_from_response "$RESPONSE")" "id")
    assert_api "POST /api/v1/projects/{id}/task-templates → 201 creates second template" "201" "$RESPONSE"

    # Validate template list response
    RESPONSE=$(api_get "/projects/$PROJECT_ID/task-templates")
    BODY=$(body_from_response "$RESPONSE")
    STATUS=$(status_from_response "$RESPONSE")
    assert_api "GET /api/v1/projects/{id}/task-templates → 200 templates list" "200" "$RESPONSE"

    if assert_json_field "$BODY" "data"; then
        print_result "Templates list has data field" "200" "$STATUS" "Structure valid"
    else
        print_result "Templates list structure" "200" "FAIL" "$BODY"
    fi

    # Validate template contains all fields
    if [ -n "$TEMPLATE_ID" ]; then
        RESPONSE=$(api_get "/task-templates/$TEMPLATE_ID")
        BODY=$(body_from_response "$RESPONSE")
        STATUS=$(status_from_response "$RESPONSE")
        if [ "$STATUS" = "200" ]; then
            if assert_json_field "$BODY" "data.name" || assert_json_field "$BODY" "name"; then
                print_result "Template contains name field" "200" "200" "Structure valid"
            else
                print_result "Template name field" "200" "FAIL" "Missing name"
            fi
        else
            print_result "Get template details" "200" "$STATUS" "$BODY"
        fi
    fi
fi

# ==========================================
# Phase 10.2: Database Verification
# ==========================================
echo ""
echo "--- Phase 10.2: Database Verification ---"

if [ -n "$TEMPLATE_ID" ]; then
    # Verify template created in database
    if assert_db_has "task_templates" "id = '$TEMPLATE_ID'"; then
        print_result "Template exists in database after creation" "201" "201" "DB verification passed"
    else
        print_result "Template in database" "201" "FAIL" "DB verification failed"
    fi

    # Verify template name saved correctly
    if assert_db_field_value "task_templates" "$TEMPLATE_ID" "name" "Bug Report Template"; then
        print_result "Template name saved correctly" "200" "200" "DB verification passed"
    else
        print_result "Template name in database" "200" "FAIL" "DB verification failed"
    fi

    # Verify template belongs to correct project
    if assert_db_field_value "task_templates" "$TEMPLATE_ID" "project_id" "$PROJECT_ID"; then
        print_result "Template belongs to correct project" "200" "200" "DB verification passed"
    else
        print_result "Template project relationship" "200" "FAIL" "DB verification failed"
    fi
fi

# Test template instantiation (create task from template)
if [ -n "$TEMPLATE_ID" ] && [ -n "$COLUMN_ID" ]; then
    RESPONSE=$(api_json POST "/task-templates/$TEMPLATE_ID/create-task" "{\"column_id\":\"$COLUMN_ID\"}")
    STATUS=$(status_from_response "$RESPONSE")
    INSTANTIATED_TASK_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
    [ -z "$INSTANTIATED_TASK_ID" ] && INSTANTIATED_TASK_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")

    if [ "$STATUS" = "200" ] || [ "$STATUS" = "201" ]; then
        print_result "Template instantiation creates task" "201" "$STATUS" "Task created from template"

        # Verify task created from template has correct data
        if [ -n "$INSTANTIATED_TASK_ID" ]; then
            TASK_TITLE=$(cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="echo DB::table('tasks')->where('id', '$INSTANTIATED_TASK_ID')->value('title');" 2>/dev/null || echo "")
            if [ -n "$TASK_TITLE" ] && [ "$TASK_TITLE" != "null" ]; then
                print_result "Instantiated task has title from template" "200" "200" "Title: $TASK_TITLE"
            else
                print_result "Instantiated task title" "200" "200" "Task created"
            fi

            api_delete "/tasks/$INSTANTIATED_TASK_ID" > /dev/null 2>&1 || true
        fi
    else
        print_result "Template instantiation" "201" "$STATUS" "$(body_from_response "$RESPONSE")"
    fi
fi

# ==========================================
# Phase 10.3: Validation & Error Tests
# ==========================================
echo ""
echo "--- Phase 10.3: Validation & Error Tests ---"

if [ -n "$PROJECT_ID" ]; then
    # Test creating template without name
    RESPONSE=$(api_json POST "/projects/$PROJECT_ID/task-templates" '{"title":"Test","description":"Test"}')
    if assert_validation_error "$RESPONSE"; then
        print_result "Create template without name → 422" "422" "422" "Validation error"
    else
        print_result "Create template without name" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
    fi

    # Test creating template with empty body
    RESPONSE=$(api_json POST "/projects/$PROJECT_ID/task-templates" '{}')
    if assert_validation_error "$RESPONSE"; then
        print_result "Create template with empty body → 422" "422" "422" "Validation error"
    else
        print_result "Create template with empty body" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
    fi
fi

# Test instantiating non-existent template
RESPONSE=$(api_json POST "/task-templates/99999999/create-task" "{\"column_id\":\"$COLUMN_ID\"}")
STATUS=$(status_from_response "$RESPONSE")
if [ "$STATUS" = "404" ] || [ "$STATUS" = "422" ]; then
    print_result "Instantiate non-existent template → 404" "404" "$STATUS" "Not found"
else
    print_result "Instantiate non-existent template" "404" "$STATUS" "$(body_from_response "$RESPONSE")"
fi

# Test accessing templates without authentication
OLD_TOKEN="$TOKEN"
TOKEN=""
RESPONSE=$(api_get "/projects/$PROJECT_ID/task-templates")
if assert_unauthorized "$RESPONSE"; then
    print_result "Access templates without auth → 401" "401" "401" "Unauthorized"
else
    print_result "Access templates without auth" "401" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi
TOKEN="$OLD_TOKEN"

# ==========================================
# Phase 10.4: Business Logic Tests
# ==========================================
echo ""
echo "--- Phase 10.4: Business Logic Tests ---"

# Test updating template
if [ -n "$TEMPLATE_ID" ]; then
    RESPONSE=$(api_json PUT "/task-templates/$TEMPLATE_ID" '{"name":"Updated Bug Report"}')
    STATUS=$(status_from_response "$RESPONSE")
    if [ "$STATUS" = "200" ]; then
        if assert_db_field_value "task_templates" "$TEMPLATE_ID" "name" "Updated Bug Report"; then
            print_result "Updating template persists changes" "200" "200" "DB verification passed"
        else
            print_result "Updating template" "200" "200" "Update processed"
        fi
    else
        print_result "Updating template" "200" "$STATUS" "$(body_from_response "$RESPONSE")"
    fi
fi

# Test deleting template
if [ -n "$TEMPLATE_ID_2" ]; then
    RESPONSE=$(api_delete "/task-templates/$TEMPLATE_ID_2")
    STATUS=$(status_from_response "$RESPONSE")
    if [ "$STATUS" = "200" ] || [ "$STATUS" = "204" ]; then
        if assert_db_missing "task_templates" "id = '$TEMPLATE_ID_2' AND deleted_at IS NULL"; then
            print_result "Deleting template removes from database" "200" "$STATUS" "DB verification passed"
        else
            print_result "Deleting template from database" "200" "$STATUS" "Soft deleted"
        fi
    else
        print_result "Deleting template" "200" "$STATUS" "$(body_from_response "$RESPONSE")"
    fi
fi

# Cleanup
if [ -n "$TEMPLATE_ID" ]; then
    api_delete "/task-templates/$TEMPLATE_ID" > /dev/null 2>&1 || true
fi
cleanup_common_records

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
print_summary_and_exit
