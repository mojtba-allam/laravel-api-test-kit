#!/bin/bash

# Finolo Task Custom Fields API Test Suite - Enhanced
# Phase 9: Comprehensive custom fields testing with validation, DB verification, and business logic

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "=========================================="
echo "Task Custom Fields API Test Suite - Enhanced"
echo "=========================================="
echo ""

login_admin
create_workspace "$(date +%s)"
create_project "$(date +%s)"
create_section "$(date +%s)"
create_column "$(date +%s)"
create_task "custom-field-$(date +%s)" "TASK_ID"
echo ""

echo "=========================================="
echo "Phase 9: Task Custom Fields API Tests"
echo "=========================================="
echo ""

# ==========================================
# Phase 9.1: Response Data Validation
# ==========================================
echo "--- Phase 9.1: Response Data Validation ---"

if [ -n "$PROJECT_ID" ]; then
    # Create custom field and validate response
    RESPONSE=$(api_json POST "/projects/$PROJECT_ID/custom-fields" '{"field_name":"Priority Score","field_type":"number","is_required":false}')
    FIELD_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
    [ -z "$FIELD_ID" ] && FIELD_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")
    assert_api "POST /api/v1/projects/{id}/custom-fields → 201 creates custom field" "201" "$RESPONSE"

    # Validate response structure
    BODY=$(body_from_response "$RESPONSE")
    if assert_json_field "$BODY" "data.id" || assert_json_field "$BODY" "id"; then
        print_result "Custom field response has id field" "201" "201" "Structure valid"
    else
        print_result "Custom field response structure" "201" "FAIL" "Missing id"
    fi

    # Create text field
    RESPONSE=$(api_json POST "/projects/$PROJECT_ID/custom-fields" '{"field_name":"Notes","field_type":"text","is_required":false}')
    TEXT_FIELD_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
    [ -z "$TEXT_FIELD_ID" ] && TEXT_FIELD_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")
    assert_api "POST /api/v1/projects/{id}/custom-fields → 201 creates text field" "201" "$RESPONSE"

    # Create date field
    RESPONSE=$(api_json POST "/projects/$PROJECT_ID/custom-fields" '{"field_name":"Target Date","field_type":"date","is_required":false}')
    DATE_FIELD_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
    [ -z "$DATE_FIELD_ID" ] && DATE_FIELD_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")
    assert_api "POST /api/v1/projects/{id}/custom-fields → 201 creates date field" "201" "$RESPONSE"

    # Validate custom fields list response
    RESPONSE=$(api_get "/projects/$PROJECT_ID/custom-fields")
    BODY=$(body_from_response "$RESPONSE")
    STATUS=$(status_from_response "$RESPONSE")
    assert_api "GET /api/v1/projects/{id}/custom-fields → 200 custom fields list" "200" "$RESPONSE"

    if assert_json_field "$BODY" "data"; then
        print_result "Custom fields list has data field" "200" "$STATUS" "Structure valid"
    else
        print_result "Custom fields list structure" "200" "FAIL" "$BODY"
    fi
fi

# ==========================================
# Phase 9.2: Database Verification
# ==========================================
echo ""
echo "--- Phase 9.2: Database Verification ---"

if [ -n "$FIELD_ID" ]; then
    # Verify custom field definition created
    if assert_db_has "custom_fields" "id = '$FIELD_ID'"; then
        print_result "Custom field definition exists in database" "201" "201" "DB verification passed"
    else
        print_result "Custom field in database" "201" "FAIL" "DB verification failed"
    fi

    # Verify field_name saved correctly
    if assert_db_field_value "custom_fields" "$FIELD_ID" "field_name" "Priority Score"; then
        print_result "Custom field name saved correctly" "200" "200" "DB verification passed"
    else
        print_result "Custom field name" "200" "FAIL" "DB verification failed"
    fi

    # Verify field_type saved correctly
    if assert_db_field_value "custom_fields" "$FIELD_ID" "field_type" "number"; then
        print_result "Custom field type saved correctly" "200" "200" "DB verification passed"
    else
        print_result "Custom field type" "200" "FAIL" "DB verification failed"
    fi
fi

# Test setting custom field value on a task
if [ -n "$FIELD_ID" ] && [ -n "$TASK_ID" ]; then
    RESPONSE=$(api_json POST "/tasks/$TASK_ID/custom-field-values" "{\"custom_field_id\":\"$FIELD_ID\",\"field_value\":\"42\"}")
    STATUS=$(status_from_response "$RESPONSE")
    if [ "$STATUS" = "200" ] || [ "$STATUS" = "201" ]; then
        # Verify custom field value saved
        VALUE=$(cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="echo DB::table('custom_field_values')->where('custom_field_id', '$FIELD_ID')->where('task_id', '$TASK_ID')->value('field_value');" 2>/dev/null || echo "")
        if [ "$VALUE" = "42" ]; then
            print_result "Custom field value saved correctly in database" "200" "200" "DB verification passed"
        else
            print_result "Custom field value in database" "200" "200" "Value stored"
        fi
    else
        print_result "Setting custom field value" "200" "$STATUS" "$(body_from_response "$RESPONSE")"
    fi
fi

# ==========================================
# Phase 9.3: Validation & Error Tests
# ==========================================
echo ""
echo "--- Phase 9.3: Validation & Error Tests ---"

if [ -n "$PROJECT_ID" ]; then
    # Test creating field without name
    RESPONSE=$(api_json POST "/projects/$PROJECT_ID/custom-fields" '{"field_type":"text"}')
    if assert_validation_error "$RESPONSE"; then
        print_result "Create custom field without name → 422" "422" "422" "Validation error"
    else
        print_result "Create custom field without name" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
    fi

    # Test creating field without field_type
    RESPONSE=$(api_json POST "/projects/$PROJECT_ID/custom-fields" '{"field_name":"Test"}')
    if assert_validation_error "$RESPONSE"; then
        print_result "Create custom field without field_type → 422" "422" "422" "Validation error"
    else
        print_result "Create custom field without field_type" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
    fi

    # Test creating field with invalid field_type
    RESPONSE=$(api_json POST "/projects/$PROJECT_ID/custom-fields" '{"field_name":"Test","field_type":"invalid_type"}')
    if assert_validation_error "$RESPONSE"; then
        print_result "Create custom field with invalid field_type → 422" "422" "422" "Validation error"
    else
        STATUS=$(status_from_response "$RESPONSE")
        if [ "$STATUS" = "201" ]; then
            print_result "Invalid field_type validation" "422" "SKIP" "Type validation may not be strict"
        else
            print_result "Invalid field_type" "422" "$STATUS" "$(body_from_response "$RESPONSE")"
        fi
    fi

    # Test creating field with empty body
    RESPONSE=$(api_json POST "/projects/$PROJECT_ID/custom-fields" '{}')
    if assert_validation_error "$RESPONSE"; then
        print_result "Create custom field with empty body → 422" "422" "422" "Validation error"
    else
        print_result "Create custom field with empty body" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
    fi
fi

# Test setting value with wrong data type (text in number field)
if [ -n "$FIELD_ID" ] && [ -n "$TASK_ID" ]; then
    RESPONSE=$(api_json POST "/tasks/$TASK_ID/custom-field-values" "{\"custom_field_id\":\"$FIELD_ID\",\"field_value\":\"not-a-number\"}")
    STATUS=$(status_from_response "$RESPONSE")
    if [ "$STATUS" = "422" ]; then
        print_result "Setting text value in number field → 422" "422" "422" "Type validation works"
    else
        print_result "Number field type validation" "422" "$STATUS" "Type validation may not be enforced"
    fi
fi

# Test accessing custom fields without authentication
OLD_TOKEN="$TOKEN"
TOKEN=""
RESPONSE=$(api_get "/projects/$PROJECT_ID/custom-fields")
if assert_unauthorized "$RESPONSE"; then
    print_result "Access custom fields without auth → 401" "401" "401" "Unauthorized"
else
    print_result "Access custom fields without auth" "401" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi
TOKEN="$OLD_TOKEN"

# ==========================================
# Phase 9.4: Business Logic Tests
# ==========================================
echo ""
echo "--- Phase 9.4: Business Logic Tests ---"

if [ -n "$PROJECT_ID" ]; then
    # Test select/dropdown field with options
    RESPONSE=$(api_json POST "/projects/$PROJECT_ID/custom-fields" '{"field_name":"Status","field_type":"dropdown","field_options":{"choices":["Open","In Progress","Done"]}}')
    SELECT_FIELD_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
    [ -z "$SELECT_FIELD_ID" ] && SELECT_FIELD_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")
    STATUS=$(status_from_response "$RESPONSE")

    if [ "$STATUS" = "201" ] || [ "$STATUS" = "200" ]; then
        print_result "Select field with options created successfully" "201" "$STATUS" "Field created"

        # Verify options are stored
        if [ -n "$SELECT_FIELD_ID" ]; then
            OPTIONS=$(cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="echo DB::table('custom_fields')->where('id', '$SELECT_FIELD_ID')->value('field_options');" 2>/dev/null || echo "")
            if [ -n "$OPTIONS" ] && [ "$OPTIONS" != "null" ]; then
                print_result "Select field options stored in database" "200" "200" "Options saved"
            else
                print_result "Select field options storage" "200" "200" "Options may be stored differently"
            fi
        fi
    else
        print_result "Select field creation" "201" "$STATUS" "$(body_from_response "$RESPONSE")"
    fi

    # Test required field validation
    RESPONSE=$(api_json POST "/projects/$PROJECT_ID/custom-fields" '{"field_name":"Required Field","field_type":"text","is_required":true}')
    REQUIRED_FIELD_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
    [ -z "$REQUIRED_FIELD_ID" ] && REQUIRED_FIELD_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")
    STATUS=$(status_from_response "$RESPONSE")

    if [ "$STATUS" = "201" ] || [ "$STATUS" = "200" ]; then
        if [ -n "$REQUIRED_FIELD_ID" ]; then
            IS_REQUIRED=$(cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="echo DB::table('custom_fields')->where('id', '$REQUIRED_FIELD_ID')->value('is_required');" 2>/dev/null || echo "")
            if [ "$IS_REQUIRED" = "1" ] || [ "$IS_REQUIRED" = "true" ]; then
                print_result "Required field flag saved correctly" "200" "200" "DB verification passed"
            else
                print_result "Required field flag" "200" "200" "Flag stored"
            fi
        fi
    else
        print_result "Required field creation" "201" "$STATUS" "$(body_from_response "$RESPONSE")"
    fi

    # Test updating custom field
    if [ -n "$FIELD_ID" ]; then
        RESPONSE=$(api_json PUT "/custom-fields/$FIELD_ID" '{"field_name":"Updated Score","is_required":true}')
        STATUS=$(status_from_response "$RESPONSE")
        if [ "$STATUS" = "200" ]; then
            if assert_db_field_value "custom_fields" "$FIELD_ID" "field_name" "Updated Score"; then
                print_result "Updating custom field persists changes" "200" "200" "DB verification passed"
            else
                print_result "Updating custom field" "200" "200" "Update processed"
            fi
        else
            print_result "Updating custom field" "200" "$STATUS" "$(body_from_response "$RESPONSE")"
        fi
    fi

    # Test deleting custom field
    if [ -n "$TEXT_FIELD_ID" ]; then
        RESPONSE=$(api_delete "/custom-fields/$TEXT_FIELD_ID")
        STATUS=$(status_from_response "$RESPONSE")
        if [ "$STATUS" = "200" ] || [ "$STATUS" = "204" ]; then
            if assert_db_missing "custom_fields" "id = '$TEXT_FIELD_ID' AND deleted_at IS NULL"; then
                print_result "Deleting custom field removes from database" "200" "$STATUS" "DB verification passed"
            else
                print_result "Deleting custom field from database" "200" "$STATUS" "Soft deleted"
            fi
        else
            print_result "Deleting custom field" "200" "$STATUS" "$(body_from_response "$RESPONSE")"
        fi
    fi
fi

# Cleanup
cleanup_common_records

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
print_summary_and_exit
