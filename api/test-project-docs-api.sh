#!/bin/bash

# Project Docs API Test Suite

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "=========================================="
echo "Project Docs API Test Suite"
echo "=========================================="
echo ""

mint_token_for "project-docs-api@test.example.com"
TOKEN="$MINTED_TOKEN"
USER_ID="$MINTED_USER_ID"
echo "✓ Auth token obtained (test user: project-docs-api@test.example.com)"
echo ""

create_workspace "$(date +%s)"
create_project "$(date +%s)"
echo ""

echo "--- List (empty) ---"
RESPONSE=$(api_get "/projects/$PROJECT_ID/docs")
assert_api "GET /api/v1/projects/{id}/docs → 200 empty list" "200" "$RESPONSE"

echo ""
echo "--- Upload text doc ---"
TEST_FILE="/tmp/project-doc-rules-$$.md"
echo "# Coding Rules" > "$TEST_FILE"
RESPONSE=$(api_multipart POST "/projects/$PROJECT_ID/docs" -F "file=@$TEST_FILE" -F "title=Coding Rules" -F "category=rules")
DOC_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
assert_api "POST /api/v1/projects/{id}/docs → 201 upload" "201" "$RESPONSE"

echo ""
echo "--- Upload second doc ---"
TEST_FILE_2="/tmp/project-doc-notes-$$.txt"
echo "System design notes" > "$TEST_FILE_2"
RESPONSE=$(api_multipart POST "/projects/$PROJECT_ID/docs" -F "file=@$TEST_FILE_2" -F "category=general")
DOC_ID_2=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
assert_api "POST /api/v1/projects/{id}/docs → 201 second upload" "201" "$RESPONSE"
rm -f "$TEST_FILE" "$TEST_FILE_2"

echo ""
echo "--- List populated ---"
RESPONSE=$(api_get "/projects/$PROJECT_ID/docs")
assert_api "GET /api/v1/projects/{id}/docs → 200 populated" "200" "$RESPONSE"

echo ""
echo "--- Filter by category ---"
RESPONSE=$(api_get "/projects/$PROJECT_ID/docs?category=rules")
BODY=$(body_from_response "$RESPONSE")
assert_api "GET /api/v1/projects/{id}/docs?category=rules → 200" "200" "$RESPONSE"

echo ""
echo "--- Get metadata ---"
if [ -n "$DOC_ID" ]; then
    RESPONSE=$(api_get "/project-docs/$DOC_ID")
    assert_api "GET /api/v1/project-docs/{id} → 200" "200" "$RESPONSE"

    RESPONSE=$(api_get "/project-docs/$DOC_ID/download")
    STATUS=$(status_from_response "$RESPONSE")
    if [ "$STATUS" = "200" ]; then
        print_result "GET /api/v1/project-docs/{id}/download → 200" "200" "$STATUS" "Download ok"
    else
        print_result "GET /api/v1/project-docs/{id}/download" "200" "$STATUS" "$(body_from_response "$RESPONSE")"
    fi

    RESPONSE=$(api_json PUT "/project-docs/$DOC_ID" '{"title":"Updated Rules","description":"Team coding standards"}')
    assert_api "PUT /api/v1/project-docs/{id} → 200 update" "200" "$RESPONSE"
fi

echo ""
echo "--- 403 upload without permission (non-member) ---"
mint_token_for "project-docs-stranger-$(date +%s)@test.example.com"
STRANGER_TOKEN="$MINTED_TOKEN"
TOKEN="$STRANGER_TOKEN"
DENY_FILE="/tmp/project-doc-deny-$$.txt"
echo "denied" > "$DENY_FILE"
RESPONSE=$(api_multipart POST "/projects/$PROJECT_ID/docs" -F "file=@$DENY_FILE" -F "category=general")
assert_api "POST /api/v1/projects/{id}/docs as non-member → 403" "403" "$RESPONSE"
rm -f "$DENY_FILE"
mint_token_for "project-docs-api@test.example.com"
TOKEN="$MINTED_TOKEN"

echo ""
echo "--- Delete doc ---"
if [ -n "$DOC_ID" ]; then
    RESPONSE=$(api_delete "/project-docs/$DOC_ID")
    assert_api "DELETE /api/v1/project-docs/{id} → 200" "200" "$RESPONSE"

    if assert_db_has "project_attachments" "id = '$DOC_ID' AND deleted_at IS NOT NULL"; then
        print_result "Doc soft-deleted in database" "200" "200" "DB ok"
    else
        print_result "Doc soft-deleted in database" "200" "FAIL" "Missing soft delete"
    fi
fi

echo ""
echo "=========================================="
print_summary_and_exit
