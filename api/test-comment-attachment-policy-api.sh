#!/bin/bash
# Comment & Attachment Delete Policy — Focused 6-Scenario Script
#
# Mirrors the "Expected API behavior (HTTP)" table in
# tests/api/POLICY_AUTHORIZATION_REVIEW.md exactly.
#
# Requires: API server running (e.g. php artisan serve)
# Usage:    bash tests/api/test-comment-attachment-policy-api.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "===== Comment & Attachment Delete Policy ====="
echo ""

# -------------------------------------------------------
# 1. Capture tokens for all relevant actors
# -------------------------------------------------------
ADMIN_TOKEN=$(login_as "admin@finolo.com")   || { echo "ERROR: could not login as admin" >&2; exit 1; }
OWNER_TOKEN=$(login_as "user-01@finolo.com") || { echo "ERROR: could not login as user-01" >&2; exit 1; }
MEMBER_TOKEN=$(login_as "user-03@finolo.com") || { echo "ERROR: could not login as user-03" >&2; exit 1; }
AUTHOR_TOKEN=$(login_as "user-04@finolo.com") || { echo "ERROR: could not login as user-04" >&2; exit 1; }

# Capture user IDs for member-add step
act_as "$OWNER_TOKEN"
OWNER_LOGIN_ID=""
login_as "user-01@finolo.com" > /dev/null 2>&1 || true
OWNER_LOGIN_ID="$LAST_LOGIN_USER_ID"

# Re-login as user-03 to capture user ID
login_as "user-03@finolo.com" > /dev/null 2>&1 || true
MEMBER_USER_ID="$LAST_LOGIN_USER_ID"

# Re-login as user-04 to capture user ID
login_as "user-04@finolo.com" > /dev/null 2>&1 || true
AUTHOR_USER_ID="$LAST_LOGIN_USER_ID"

# -------------------------------------------------------
# 2. Build minimal fixture world (as project owner)
# -------------------------------------------------------
act_as "$OWNER_TOKEN"
create_workspace "ca-policy"
create_project   "ca-policy"
create_section   "ca-policy"
create_column    "ca-policy"
create_task      "ca-policy"

echo "Workspace: $WORKSPACE_ID  Project: $PROJECT_ID  Task: $TASK_ID"

# Create a project team so we can add members
TEAM_RESP=$(api_json POST "/projects/$PROJECT_ID/teams" '{"name":"ca-policy-team","description":"policy test team"}')
TEAM_ID=$(json_value "$(body_from_response "$TEAM_RESP")" "data.id")
[ -z "$TEAM_ID" ] && TEAM_ID=$(json_value "$(body_from_response "$TEAM_RESP")" "id")

if [ -z "$TEAM_ID" ]; then
    echo "ERROR: failed to create project team for project $PROJECT_ID" >&2
    echo "Response: $(body_from_response "$TEAM_RESP")" >&2
    exit 1
fi
echo "Team: $TEAM_ID"

# Add MEMBER (user-03) to project via team (creates project_members row with Contributor role)
if [ -n "$MEMBER_USER_ID" ]; then
    add_member_direct "$PROJECT_ID" "$MEMBER_USER_ID"
    echo "Added member user-03 ($MEMBER_USER_ID) to project"
else
    echo "WARNING: could not capture user-03 ID; member 403 test may fail" >&2
fi

# Add AUTHOR (user-04) to project via team (creates project_members row with Contributor role)
if [ -n "$AUTHOR_USER_ID" ]; then
    add_member_direct "$PROJECT_ID" "$AUTHOR_USER_ID"
    echo "Added author user-04 ($AUTHOR_USER_ID) to project"
else
    echo "WARNING: could not capture user-04 ID; author tests may fail" >&2
fi

echo ""

# -------------------------------------------------------
# 3. Author creates TWO comments and TWO attachments
# -------------------------------------------------------
act_as "$AUTHOR_TOKEN"

# Comment A — will be deleted by the author (row 1)
COMMENT_A_RESP=$(api_json POST "/comments" "{\"task_id\":\"$TASK_ID\",\"content\":\"CA-Policy comment A\"}")
COMMENT_A=$(json_value "$(body_from_response "$COMMENT_A_RESP")" "data.id")
[ -z "$COMMENT_A" ] && COMMENT_A=$(json_value "$(body_from_response "$COMMENT_A_RESP")" "id")

# Comment B — member will attempt delete (row 2), then admin deletes (row 3)
COMMENT_B_RESP=$(api_json POST "/comments" "{\"task_id\":\"$TASK_ID\",\"content\":\"CA-Policy comment B\"}")
COMMENT_B=$(json_value "$(body_from_response "$COMMENT_B_RESP")" "data.id")
[ -z "$COMMENT_B" ] && COMMENT_B=$(json_value "$(body_from_response "$COMMENT_B_RESP")" "id")

if [ -z "$COMMENT_A" ] || [ -z "$COMMENT_B" ]; then
    echo "ERROR: failed to create test comments" >&2
    echo "  Comment A response: $(body_from_response "$COMMENT_A_RESP")" >&2
    echo "  Comment B response: $(body_from_response "$COMMENT_B_RESP")" >&2
    # Teardown before exit
    act_as "$ADMIN_TOKEN"
    [ -n "${TEAM_ID:-}" ] && api_delete "/project-teams/$TEAM_ID" > /dev/null 2>&1 || true
    cleanup_common_records
    exit 1
fi
echo "Comment A: $COMMENT_A  Comment B: $COMMENT_B"

# Create temp file for attachment uploads
ATTACH_TMP="/tmp/ca-pol-test-$$.txt"
echo "ca-policy attachment test content" > "$ATTACH_TMP"

# Attachment A — will be deleted by the uploader (row 4)
ATT_A_RESP=$(api_multipart POST "/attachments/upload" \
    -F "file=@${ATTACH_TMP};type=text/plain" \
    -F "task_id=$TASK_ID")
ATT_A=$(json_value "$(body_from_response "$ATT_A_RESP")" "data.id")
[ -z "$ATT_A" ] && ATT_A=$(json_value "$(body_from_response "$ATT_A_RESP")" "id")

# Attachment B — member will attempt delete (row 5), then admin deletes (row 6)
ATT_B_RESP=$(api_multipart POST "/attachments/upload" \
    -F "file=@${ATTACH_TMP};type=text/plain" \
    -F "task_id=$TASK_ID")
ATT_B=$(json_value "$(body_from_response "$ATT_B_RESP")" "data.id")
[ -z "$ATT_B" ] && ATT_B=$(json_value "$(body_from_response "$ATT_B_RESP")" "id")

if [ -z "$ATT_A" ] || [ -z "$ATT_B" ]; then
    echo "ERROR: failed to upload test attachments" >&2
    echo "  ATT_A response: $(body_from_response "$ATT_A_RESP")" >&2
    echo "  ATT_B response: $(body_from_response "$ATT_B_RESP")" >&2
    # Teardown before exit
    act_as "$ADMIN_TOKEN"
    [ -n "$COMMENT_A" ] && api_delete "/comments/$COMMENT_A" > /dev/null 2>&1 || true
    [ -n "$COMMENT_B" ] && api_delete "/comments/$COMMENT_B" > /dev/null 2>&1 || true
    [ -n "${TEAM_ID:-}" ] && api_delete "/project-teams/$TEAM_ID" > /dev/null 2>&1 || true
    cleanup_common_records
    rm -f "$ATTACH_TMP"
    exit 1
fi
echo "Attachment A: $ATT_A  Attachment B: $ATT_B"
echo ""

# -------------------------------------------------------
# 4. Assertions — 6 rows from POLICY_AUTHORIZATION_REVIEW.md
# -------------------------------------------------------
echo "--- Policy Assertions ---"
echo ""

# Row 1: Author deletes own comment → 200
act_as "$AUTHOR_TOKEN"
assert_api "Author deletes own comment" "200" "$(api_delete "/comments/$COMMENT_A")"

# Row 2: Non-author member deletes comment → 403
act_as "$MEMBER_TOKEN"
assert_api "Non-author member denied deleting comment" "403" "$(api_delete "/comments/$COMMENT_B")"

# Row 3: Admin deletes any comment → 200
act_as "$ADMIN_TOKEN"
assert_api "Admin deletes any comment" "200" "$(api_delete "/comments/$COMMENT_B")"

# Row 4: Uploader deletes own attachment → 200
act_as "$AUTHOR_TOKEN"
assert_api "Uploader deletes own attachment" "200" "$(api_delete "/attachments/$ATT_A")"

# Row 5: Non-uploader member deletes attachment → 403
act_as "$MEMBER_TOKEN"
assert_api "Non-uploader member denied deleting attachment" "403" "$(api_delete "/attachments/$ATT_B")"

# Row 6: Admin deletes any attachment → 200
act_as "$ADMIN_TOKEN"
assert_api "Admin deletes any attachment" "200" "$(api_delete "/attachments/$ATT_B")"

echo ""

# -------------------------------------------------------
# 5. Teardown — clean up all created fixtures
# -------------------------------------------------------
echo "--- Teardown ---"
act_as "$ADMIN_TOKEN"

# Comments A and B are already deleted by assertions above; guard just in case
[ -n "${COMMENT_A:-}" ] && api_delete "/comments/$COMMENT_A" > /dev/null 2>&1 || true
[ -n "${COMMENT_B:-}" ] && api_delete "/comments/$COMMENT_B" > /dev/null 2>&1 || true

# Attachments A and B are already deleted by assertions above; guard just in case
[ -n "${ATT_A:-}" ] && api_delete "/attachments/$ATT_A" > /dev/null 2>&1 || true
[ -n "${ATT_B:-}" ] && api_delete "/attachments/$ATT_B" > /dev/null 2>&1 || true

# Delete project team (project_members rows cascade or are cleaned with project)
[ -n "${TEAM_ID:-}" ] && api_delete "/project-teams/$TEAM_ID" > /dev/null 2>&1 || true

# Delete task → column → section → project → workspace
cleanup_common_records

rm -f "$ATTACH_TMP"
echo "Teardown complete."

print_summary_and_exit
