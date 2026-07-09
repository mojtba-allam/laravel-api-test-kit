#!/bin/bash

# JSON Import/Export API Test Suite
# Covers all three levels (project / section / column) for happy paths,
# round-trip export→import, and bad scenarios.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "=========================================="
echo "JSON Import/Export API Test Suite"
echo "=========================================="
echo ""

login_admin
create_workspace "$(date +%s)"
echo ""

# Track projects created via import so we can clean them up afterwards.
IMPORTED_PROJECT_ID=""
ROUNDTRIP_PROJECT_ID=""

# Extract the `data` object of a response body as a JSON string (no jq needed).
extract_data_object() {
    BODY_INPUT="$1" php -r '$d = json_decode(getenv("BODY_INPUT"), true); echo json_encode($d["data"] ?? new stdClass());'
}

# ==========================================
# Phase 1: Project-level import (happy path)
# ==========================================
echo "--- Phase 1: Import full project ---"

PROJECT_JSON=$(cat <<JSON
{
  "name": "Curl Import Project",
  "description": "Imported via curl smoke test",
  "status": "active",
  "board_type": "kanban",
  "workspace_id": "$WORKSPACE_ID",
  "sections": [
    {
      "name": "Sprint 1",
      "section_type": "active",
      "columns": [
        {
          "name": "To Do",
          "column_type": "default",
          "tasks": [
            {"title": "Design schema", "priority": "high", "status": "open"},
            {"title": "Write tests", "priority": "medium"}
          ]
        },
        {"name": "Done", "column_type": "done", "tasks": []}
      ]
    }
  ]
}
JSON
)

RESPONSE=$(api_json POST "/projects/import" "$PROJECT_JSON")
assert_api "POST /projects/import → 201 imports full project" "201" "$RESPONSE"
IMPORTED_PROJECT_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
echo "   imported project id: $IMPORTED_PROJECT_ID"

# Verify the nested tree was persisted.
if [ -n "$IMPORTED_PROJECT_ID" ]; then
    if assert_db_has "sections" "project_id = '$IMPORTED_PROJECT_ID'"; then
        print_result "Imported project has sections in DB" "201" "201" "DB verification passed"
    else
        print_result "Imported project sections in DB" "201" "FAIL" "DB verification failed"
    fi

    if assert_db_has "tasks" "title = 'Design schema'"; then
        print_result "Imported nested task persisted in DB" "201" "201" "DB verification passed"
    else
        print_result "Imported nested task in DB" "201" "FAIL" "DB verification failed"
    fi
fi

# ==========================================
# Phase 2: Project export + round-trip import
# ==========================================
echo ""
echo "--- Phase 2: Export project and round-trip ---"

RESPONSE=$(api_get "/projects/$IMPORTED_PROJECT_ID/export")
assert_api "GET /projects/{id}/export → 200 exports project" "200" "$RESPONSE"
EXPORTED_BODY=$(body_from_response "$RESPONSE")

if assert_json_field "$EXPORTED_BODY" "data.sections.first.columns.first.tasks.first.title"; then
    print_result "Export contains nested task title" "200" "200" "Structure valid"
else
    print_result "Export nested structure" "200" "FAIL" "Missing nested task"
fi

EXPORTED_DATA=$(extract_data_object "$EXPORTED_BODY")
RESPONSE=$(api_json POST "/projects/import" "$EXPORTED_DATA")
assert_api "POST /projects/import → 201 re-imports exported JSON (round-trip)" "201" "$RESPONSE"
ROUNDTRIP_PROJECT_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")

# ==========================================
# Phase 3: Section-level import + export
# ==========================================
echo ""
echo "--- Phase 3: Import & export section ---"

SECTION_JSON=$(cat <<JSON
{
  "project_id": "$IMPORTED_PROJECT_ID",
  "name": "Imported Backlog",
  "columns": [
    {"name": "Ideas", "tasks": [{"title": "Investigate caching"}]}
  ]
}
JSON
)

RESPONSE=$(api_json POST "/sections/import" "$SECTION_JSON")
assert_api "POST /sections/import → 201 imports section into project" "201" "$RESPONSE"
IMPORTED_SECTION_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")

if [ -n "$IMPORTED_SECTION_ID" ]; then
    RESPONSE=$(api_get "/sections/$IMPORTED_SECTION_ID/export")
    assert_api "GET /sections/{id}/export → 200 exports section" "200" "$RESPONSE"
fi

# ==========================================
# Phase 4: Column-level import + export
# ==========================================
echo ""
echo "--- Phase 4: Import & export column ---"

COLUMN_JSON=$(cat <<JSON
{
  "section_id": "$IMPORTED_SECTION_ID",
  "name": "In Review",
  "column_type": "wip",
  "tasks": [
    {"title": "Review PR #1", "priority": "medium"},
    {"title": "Review PR #2"}
  ]
}
JSON
)

RESPONSE=$(api_json POST "/columns/import" "$COLUMN_JSON")
assert_api "POST /columns/import → 201 imports column into section" "201" "$RESPONSE"
IMPORTED_COLUMN_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")

if [ -n "$IMPORTED_COLUMN_ID" ]; then
    RESPONSE=$(api_get "/columns/$IMPORTED_COLUMN_ID/export")
    assert_api "GET /columns/{id}/export → 200 exports column" "200" "$RESPONSE"
fi

# ==========================================
# Phase 5: Bad scenarios
# ==========================================
echo ""
echo "--- Phase 5: Bad scenarios ---"

# 5a: project import without a name
RESPONSE=$(api_json POST "/projects/import" '{"description":"no name"}')
if assert_validation_error "$RESPONSE"; then
    print_result "Import project without name → 422" "422" "422" "Validation error"
else
    print_result "Import project without name" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# 5b: invalid task status nested deep in the tree
BAD_STATUS='{"name":"Bad","sections":[{"name":"S","columns":[{"name":"C","tasks":[{"title":"T","status":"not_a_status"}]}]}]}'
RESPONSE=$(api_json POST "/projects/import" "$BAD_STATUS")
if assert_validation_error "$RESPONSE"; then
    print_result "Import project with invalid task status → 422" "422" "422" "Validation error"
else
    print_result "Import project invalid task status" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# 5c: nested task missing a title
BAD_TITLE='{"name":"Bad","sections":[{"name":"S","columns":[{"name":"C","tasks":[{"priority":"high"}]}]}]}'
RESPONSE=$(api_json POST "/projects/import" "$BAD_TITLE")
if assert_validation_error "$RESPONSE"; then
    print_result "Import project with task missing title → 422" "422" "422" "Validation error"
else
    print_result "Import project task missing title" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# 5d: section import referencing a non-existent project
RESPONSE=$(api_json POST "/sections/import" '{"project_id":"00000000-0000-0000-0000-000000000000","name":"Orphan"}')
if assert_validation_error "$RESPONSE"; then
    print_result "Import section with bad project_id → 422" "422" "422" "Validation error"
else
    print_result "Import section bad project_id" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# 5e: column import referencing a non-existent section
RESPONSE=$(api_json POST "/columns/import" '{"section_id":"00000000-0000-0000-0000-000000000000","name":"Orphan"}')
if assert_validation_error "$RESPONSE"; then
    print_result "Import column with bad section_id → 422" "422" "422" "Validation error"
else
    print_result "Import column bad section_id" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# 5f: unauthenticated import
OLD_TOKEN="$TOKEN"
TOKEN=""
RESPONSE=$(api_json POST "/projects/import" "$PROJECT_JSON")
if assert_unauthorized "$RESPONSE"; then
    print_result "Import without auth → 401" "401" "401" "Unauthorized"
else
    print_result "Import without auth" "401" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi
TOKEN="$OLD_TOKEN"

# 5g: export a non-existent project
RESPONSE=$(api_get "/projects/00000000-0000-0000-0000-000000000000/export")
if assert_not_found "$RESPONSE"; then
    print_result "Export missing project → 404" "404" "404" "Not found"
else
    print_result "Export missing project" "404" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# ==========================================
# Cleanup
# ==========================================
echo ""
echo "--- Cleanup ---"
[ -n "$IMPORTED_PROJECT_ID" ] && api_delete "/projects/$IMPORTED_PROJECT_ID" > /dev/null 2>&1 || true
[ -n "$ROUNDTRIP_PROJECT_ID" ] && api_delete "/projects/$ROUNDTRIP_PROJECT_ID" > /dev/null 2>&1 || true
cleanup_common_records

print_summary_and_exit
