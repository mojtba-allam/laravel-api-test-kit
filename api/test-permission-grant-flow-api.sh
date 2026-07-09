#!/bin/bash
# ===========================================================================
# test-permission-grant-flow-api.sh
# Tests the full permission grant/revoke flow:
#   1. User A (owner) creates a project
#   2. User A verifies they have ALL permissions (project admin)
#   3. User A adds User B as a member (with NO permissions)
#   4. User B attempts each action → 403 (no permission)
#   5. User A grants the specific permission to User B
#   6. User B attempts the same action → success (201/200)
#   7. Repeat for all permission-gated actions
#
# Uses REAL data against the running API — no mocks.
# ===========================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "===== Permission Grant/Revoke Flow Test Suite ====="

# ──────────────────────────────────────────────────────────────────────────────
# Setup: Login as Owner (user-01) and Member (user-03)
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "----- Setup: Authenticating users -----"

OWNER_TOKEN=$(login_as "$SEED_OWNER_EMAIL") || { echo "FATAL: cannot login owner" >&2; exit 1; }
login_as "$SEED_OWNER_EMAIL" > /dev/null 2>&1; OWNER_USER_ID="$LAST_LOGIN_USER_ID"

MEMBER_TOKEN=$(login_as "$SEED_MEMBER_EMAIL") || { echo "FATAL: cannot login member" >&2; exit 1; }
login_as "$SEED_MEMBER_EMAIL" > /dev/null 2>&1; MEMBER_USER_ID="$LAST_LOGIN_USER_ID"

echo "  Owner  ID: $OWNER_USER_ID"
echo "  Member ID: $MEMBER_USER_ID"

# ──────────────────────────────────────────────────────────────────────────────
# Step 1: Owner creates workspace + project + section + column + task
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "----- Step 1: Owner creates project infrastructure -----"
act_as "$OWNER_TOKEN"

UNIQUE="permflow-$(date +%s)-$RANDOM"

RESP=$(api_json POST "/workspaces" "{\"name\":\"WS-$UNIQUE\",\"description\":\"Permission flow test\",\"visibility\":\"private\"}")
PF_WORKSPACE_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$PF_WORKSPACE_ID" ] && PF_WORKSPACE_ID=$(json_value "$(body_from_response "$RESP")" "id")
[ -z "$PF_WORKSPACE_ID" ] && { echo "FATAL: failed to create workspace"; exit 1; }
echo "  Workspace: $PF_WORKSPACE_ID"

RESP=$(api_json POST "/projects" "{\"name\":\"Proj-$UNIQUE\",\"description\":\"Permission flow test\",\"workspace_id\":\"$PF_WORKSPACE_ID\"}")
PF_PROJECT_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$PF_PROJECT_ID" ] && PF_PROJECT_ID=$(json_value "$(body_from_response "$RESP")" "id")
[ -z "$PF_PROJECT_ID" ] && { echo "FATAL: failed to create project"; exit 1; }
echo "  Project: $PF_PROJECT_ID"

RESP=$(api_json POST "/sections" "{\"name\":\"Sec-$UNIQUE\",\"project_id\":\"$PF_PROJECT_ID\",\"sort_order\":1}")
PF_SECTION_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$PF_SECTION_ID" ] && PF_SECTION_ID=$(json_value "$(body_from_response "$RESP")" "id")
[ -z "$PF_SECTION_ID" ] && { echo "FATAL: failed to create section"; exit 1; }
echo "  Section: $PF_SECTION_ID"

RESP=$(api_json POST "/columns" "{\"name\":\"Col-$UNIQUE\",\"section_id\":\"$PF_SECTION_ID\",\"sort_order\":1}")
PF_COLUMN_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$PF_COLUMN_ID" ] && PF_COLUMN_ID=$(json_value "$(body_from_response "$RESP")" "id")
[ -z "$PF_COLUMN_ID" ] && { echo "FATAL: failed to create column"; exit 1; }
echo "  Column: $PF_COLUMN_ID"

RESP=$(api_json POST "/tasks" "{\"title\":\"Task-$UNIQUE\",\"column_id\":\"$PF_COLUMN_ID\",\"priority\":\"medium\"}")
PF_TASK_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$PF_TASK_ID" ] && PF_TASK_ID=$(json_value "$(body_from_response "$RESP")" "id")
[ -z "$PF_TASK_ID" ] && { echo "FATAL: failed to create task"; exit 1; }
echo "  Task: $PF_TASK_ID"

# ──────────────────────────────────────────────────────────────────────────────
# Step 2: Verify Owner has ALL permissions (project admin)
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "----- Step 2: Verify owner has all permissions (project admin) -----"
act_as "$OWNER_TOKEN"

RESP=$(api_get "/projects/$PF_PROJECT_ID/my-permissions")
BODY=$(body_from_response "$RESP")
STATUS=$(status_from_response "$RESP")
IS_ADMIN=$(json_value "$BODY" "data.is_project_admin")
assert_api "Owner my-permissions returns 200" "200" "$RESP"

TOTAL=$((TOTAL + 1))
if [ "$IS_ADMIN" = "true" ]; then
    echo -e "${GREEN}✓${NC} Owner is_project_admin = true"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗${NC} Owner is_project_admin expected true, got: $IS_ADMIN"
    FAILED=$((FAILED + 1))
    FAILED_TESTS+=("Owner is_project_admin = true")
fi

# Owner can do all actions (create section, column, task, comment, attachment, tag, timelog)
RESP=$(api_json POST "/comments" "{\"task_id\":\"$PF_TASK_ID\",\"content\":\"owner comment test\"}")
assert_api "Owner can create comment (project admin)" "201" "$RESP"
OWNER_COMMENT_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$OWNER_COMMENT_ID" ] && OWNER_COMMENT_ID=$(json_value "$(body_from_response "$RESP")" "id")

RESP=$(api_json POST "/tags" "{\"name\":\"owner-tag-$UNIQUE\",\"project_id\":\"$PF_PROJECT_ID\",\"color\":\"#FF0000\"}")
assert_api "Owner can create tag (project admin)" "201" "$RESP"
OWNER_TAG_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$OWNER_TAG_ID" ] && OWNER_TAG_ID=$(json_value "$(body_from_response "$RESP")" "id")

TODAY=$(date +%Y-%m-%d)
RESP=$(api_json POST "/time-logs" "{\"task_id\":\"$PF_TASK_ID\",\"minutes\":15,\"hours\":0,\"description\":\"owner timelog\",\"logged_date\":\"$TODAY\"}")
assert_api "Owner can create timelog (project admin)" "201" "$RESP"
OWNER_TIMELOG_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$OWNER_TIMELOG_ID" ] && OWNER_TIMELOG_ID=$(json_value "$(body_from_response "$RESP")" "id")

# ──────────────────────────────────────────────────────────────────────────────
# Step 3: Owner adds Member to project WITH EMPTY permissions
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "----- Step 3: Add member with NO permissions -----"
act_as "$OWNER_TOKEN"

# Add member to the project
RESP=$(api_json POST "/projects/$PF_PROJECT_ID/members-overview" "{\"user_id\":\"$MEMBER_USER_ID\"}")
assert_api "Owner adds member to project" "201 200" "$RESP"
PF_MEMBER_ID=$(json_value "$(body_from_response "$RESP")" "data.member_id")
[ -z "$PF_MEMBER_ID" ] && PF_MEMBER_ID=$(json_value "$(body_from_response "$RESP")" "member_id")
echo "  Member record ID: $PF_MEMBER_ID"

# Revoke ALL default permissions so the member starts with zero
RESP=$(api_json PUT "/projects/$PF_PROJECT_ID/members/$PF_MEMBER_ID/permissions" "{\"permissions\":[]}")
assert_api "Owner clears all member permissions" "200" "$RESP"

# Verify member has zero permissions
RESP=$(api_get "/projects/$PF_PROJECT_ID/members/$PF_MEMBER_ID/permissions")
BODY=$(body_from_response "$RESP")
PERM_COUNT=$(JSON_INPUT="$BODY" php -r '
    $d = json_decode(getenv("JSON_INPUT"), true);
    $perms = $d["data"]["permissions"] ?? $d["permissions"] ?? [];
    echo count($perms);
')
TOTAL=$((TOTAL + 1))
if [ "$PERM_COUNT" = "0" ]; then
    echo -e "${GREEN}✓${NC} Member has 0 permissions after clear"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗${NC} Member should have 0 permissions, has $PERM_COUNT"
    FAILED=$((FAILED + 1))
    FAILED_TESTS+=("Member has 0 permissions after clear")
fi

# ──────────────────────────────────────────────────────────────────────────────
# Helper: test deny→grant→allow for a given permission slug + action
# ──────────────────────────────────────────────────────────────────────────────
# Usage: test_permission_flow "permission_slug" "action_description" "deny_cmd" "deny_expected" "allow_cmd" "allow_expected"
# deny_cmd/allow_cmd are evaluated with eval so they can reference variables

grant_permission() {
    local slug="$1"
    act_as "$OWNER_TOKEN"
    local resp
    resp=$(api_json POST "/projects/$PF_PROJECT_ID/members/$PF_MEMBER_ID/permissions/$slug" "{}")
    local status
    status=$(status_from_response "$resp")
    if [ "$status" != "200" ] && [ "$status" != "201" ]; then
        echo -e "${RED}  ⚠ Failed to grant $slug (HTTP $status)${NC}"
        echo "    $(body_from_response "$resp" | head -c 200)"
    fi
}

revoke_permission() {
    local slug="$1"
    act_as "$OWNER_TOKEN"
    api_delete "/projects/$PF_PROJECT_ID/members/$PF_MEMBER_ID/permissions/$slug" > /dev/null 2>&1
}

# ──────────────────────────────────────────────────────────────────────────────
# Step 4-6: Test each permission-gated action
# Pattern: deny (no perm) → grant → allow (with perm)
# ──────────────────────────────────────────────────────────────────────────────

echo ""
echo "----- Section permissions (create_section / edit_section / delete_section) -----"

# --- create_section ---
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/sections" "{\"name\":\"member-sec-$UNIQUE\",\"project_id\":\"$PF_PROJECT_ID\",\"sort_order\":2}")
assert_api "Section create [member, NO perm → 403]" "403" "$RESP"

grant_permission "create_section"

act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/sections" "{\"name\":\"member-sec-$UNIQUE\",\"project_id\":\"$PF_PROJECT_ID\",\"sort_order\":2}")
assert_api "Section create [member, WITH create_section → 201]" "201" "$RESP"
MEMBER_SECTION_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$MEMBER_SECTION_ID" ] && MEMBER_SECTION_ID=$(json_value "$(body_from_response "$RESP")" "id")

revoke_permission "create_section"

# --- edit_section ---
act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/sections/$MEMBER_SECTION_ID" "{\"name\":\"member-sec-updated-$UNIQUE\"}")
assert_api "Section update [member, NO perm → 403]" "403" "$RESP"

grant_permission "edit_section"

act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/sections/$MEMBER_SECTION_ID" "{\"name\":\"member-sec-updated-$UNIQUE\"}")
assert_api "Section update [member, WITH edit_section → 200]" "200" "$RESP"

revoke_permission "edit_section"

# --- delete_section ---
act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/sections/$MEMBER_SECTION_ID")
assert_api "Section delete [member, NO perm → 403]" "403" "$RESP"

grant_permission "delete_section"

act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/sections/$MEMBER_SECTION_ID")
assert_api "Section delete [member, WITH delete_section → 200]" "200 204" "$RESP"

revoke_permission "delete_section"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "----- Column permissions (create_column / edit_column / delete_column / reorder_column) -----"

# --- create_column ---
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/columns" "{\"name\":\"member-col-$UNIQUE\",\"section_id\":\"$PF_SECTION_ID\",\"sort_order\":2}")
assert_api "Column create [member, NO perm → 403]" "403" "$RESP"

grant_permission "create_column"

act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/columns" "{\"name\":\"member-col-$UNIQUE\",\"section_id\":\"$PF_SECTION_ID\",\"sort_order\":2}")
assert_api "Column create [member, WITH create_column → 201]" "201" "$RESP"
MEMBER_COLUMN_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$MEMBER_COLUMN_ID" ] && MEMBER_COLUMN_ID=$(json_value "$(body_from_response "$RESP")" "id")

revoke_permission "create_column"

# --- edit_column ---
act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/columns/$MEMBER_COLUMN_ID" "{\"name\":\"member-col-updated-$UNIQUE\"}")
assert_api "Column update [member, NO perm → 403]" "403" "$RESP"

grant_permission "edit_column"

act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/columns/$MEMBER_COLUMN_ID" "{\"name\":\"member-col-updated-$UNIQUE\"}")
assert_api "Column update [member, WITH edit_column → 200]" "200" "$RESP"

revoke_permission "edit_column"

# --- delete_column ---
act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/columns/$MEMBER_COLUMN_ID")
assert_api "Column delete [member, NO perm → 403]" "403" "$RESP"

grant_permission "delete_column"

act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/columns/$MEMBER_COLUMN_ID")
assert_api "Column delete [member, WITH delete_column → 200]" "200 204" "$RESP"

revoke_permission "delete_column"

# --- reorder_column ---
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/sections/$PF_SECTION_ID/columns/reorder" "{\"order\":[\"$PF_COLUMN_ID\"]}")
assert_api "Column reorder [member, NO perm → 403]" "403" "$RESP"

grant_permission "reorder_column"

act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/sections/$PF_SECTION_ID/columns/reorder" "{\"order\":[\"$PF_COLUMN_ID\"]}")
assert_api "Column reorder [member, WITH reorder_column → 200]" "200" "$RESP"

revoke_permission "reorder_column"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "----- Task permissions (create_task / edit_task / delete_task / move_task) -----"

# --- create_task ---
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/tasks" "{\"title\":\"member-task-$UNIQUE\",\"column_id\":\"$PF_COLUMN_ID\",\"priority\":\"low\"}")
assert_api "Task create [member, NO perm → 403]" "403" "$RESP"

grant_permission "create_task"

act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/tasks" "{\"title\":\"member-task-$UNIQUE\",\"column_id\":\"$PF_COLUMN_ID\",\"priority\":\"low\"}")
assert_api "Task create [member, WITH create_task → 201]" "201" "$RESP"
MEMBER_TASK_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$MEMBER_TASK_ID" ] && MEMBER_TASK_ID=$(json_value "$(body_from_response "$RESP")" "id")

revoke_permission "create_task"

# --- edit_task ---
act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/tasks/$PF_TASK_ID" "{\"title\":\"member-updated-task-$UNIQUE\"}")
assert_api "Task update [member, NO perm → 403]" "403" "$RESP"

grant_permission "edit_task"

act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/tasks/$PF_TASK_ID" "{\"title\":\"member-updated-task-$UNIQUE\"}")
assert_api "Task update [member, WITH edit_task → 200]" "200" "$RESP"

revoke_permission "edit_task"

# --- delete_task (on a task NOT created by the member) ---
act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/tasks/$PF_TASK_ID")
assert_api "Task delete [member, NO perm, not creator → 403]" "403" "$RESP"

grant_permission "delete_task"

act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/tasks/$PF_TASK_ID")
assert_api "Task delete [member, WITH delete_task → 200]" "200 204" "$RESP"

revoke_permission "delete_task"

# Recreate a task for remaining tests (as owner)
act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/tasks" "{\"title\":\"Task2-$UNIQUE\",\"column_id\":\"$PF_COLUMN_ID\",\"priority\":\"medium\"}")
PF_TASK_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$PF_TASK_ID" ] && PF_TASK_ID=$(json_value "$(body_from_response "$RESP")" "id")

# --- move_task ---
# NOTE: The move endpoint authorizes via 'update' policy which checks edit_task.
# The move_task permission from the catalog is for frontend UI gating, not backend.
# We test that without edit_task, the member cannot move; with it, they can.
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/tasks/$PF_TASK_ID/move" "{\"column_id\":\"$PF_COLUMN_ID\",\"sort_order\":0}")
assert_api "Task move [member, NO edit_task → 403]" "403" "$RESP"

grant_permission "edit_task"

act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/tasks/$PF_TASK_ID/move" "{\"column_id\":\"$PF_COLUMN_ID\",\"sort_order\":0}")
assert_api "Task move [member, WITH edit_task → 200]" "200" "$RESP"

revoke_permission "edit_task"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "----- Comment permissions (create_comment / edit_comment / delete_comment) -----"

# --- create_comment ---
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/comments" "{\"task_id\":\"$PF_TASK_ID\",\"content\":\"member comment denied\"}")
assert_api "Comment create [member, NO perm → 403]" "403" "$RESP"

grant_permission "create_comment"

act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/comments" "{\"task_id\":\"$PF_TASK_ID\",\"content\":\"member comment allowed\"}")
assert_api "Comment create [member, WITH create_comment → 201]" "201" "$RESP"
MEMBER_COMMENT_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$MEMBER_COMMENT_ID" ] && MEMBER_COMMENT_ID=$(json_value "$(body_from_response "$RESP")" "id")

revoke_permission "create_comment"

# --- edit_comment (editing ANOTHER user's comment) ---
# Create a fresh comment by owner for this test
act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/comments" "{\"task_id\":\"$PF_TASK_ID\",\"content\":\"owner comment for edit test\"}")
OWNER_COMMENT_EDIT=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$OWNER_COMMENT_EDIT" ] && OWNER_COMMENT_EDIT=$(json_value "$(body_from_response "$RESP")" "id")

act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/comments/$OWNER_COMMENT_EDIT" "{\"content\":\"member edit attempt\"}")
assert_api "Comment edit other's [member, NO perm → 403]" "403" "$RESP"

grant_permission "edit_comment"

act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/comments/$OWNER_COMMENT_EDIT" "{\"content\":\"member edit allowed\"}")
assert_api "Comment edit other's [member, WITH edit_comment → 200]" "200" "$RESP"

revoke_permission "edit_comment"

# --- delete_comment (deleting ANOTHER user's comment) ---
# Create a fresh comment by owner so we can test deletion
act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/comments" "{\"task_id\":\"$PF_TASK_ID\",\"content\":\"owner comment for delete test\"}")
OWNER_COMMENT_DEL=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$OWNER_COMMENT_DEL" ] && OWNER_COMMENT_DEL=$(json_value "$(body_from_response "$RESP")" "id")

act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/comments/$OWNER_COMMENT_DEL")
assert_api "Comment delete other's [member, NO perm → 403]" "403" "$RESP"

grant_permission "delete_comment"

act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/comments/$OWNER_COMMENT_DEL")
assert_api "Comment delete other's [member, WITH delete_comment → 200]" "200" "$RESP"

revoke_permission "delete_comment"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "----- Attachment permissions (upload_attachment / delete_attachment) -----"

# Create a temp file for upload tests
echo "permission-flow-test-file" > /tmp/pf-test-attach.txt

# --- upload_attachment ---
act_as "$MEMBER_TOKEN"
RESP=$(api_multipart POST "/attachments/upload" -F "file=@/tmp/pf-test-attach.txt" -F "task_id=$PF_TASK_ID")
assert_api "Attachment upload [member, NO perm → 403]" "403" "$RESP"

grant_permission "upload_attachment"

act_as "$MEMBER_TOKEN"
RESP=$(api_multipart POST "/attachments/upload" -F "file=@/tmp/pf-test-attach.txt" -F "task_id=$PF_TASK_ID")
assert_api "Attachment upload [member, WITH upload_attachment → 201]" "201" "$RESP"
MEMBER_ATTACHMENT_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$MEMBER_ATTACHMENT_ID" ] && MEMBER_ATTACHMENT_ID=$(json_value "$(body_from_response "$RESP")" "id")

revoke_permission "upload_attachment"

# --- delete_attachment (deleting ANOTHER user's attachment) ---
# Owner uploads an attachment
act_as "$OWNER_TOKEN"
RESP=$(api_multipart POST "/attachments/upload" -F "file=@/tmp/pf-test-attach.txt" -F "task_id=$PF_TASK_ID")
OWNER_ATTACHMENT_DEL=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$OWNER_ATTACHMENT_DEL" ] && OWNER_ATTACHMENT_DEL=$(json_value "$(body_from_response "$RESP")" "id")

act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/attachments/$OWNER_ATTACHMENT_DEL")
assert_api "Attachment delete other's [member, NO perm → 403]" "403" "$RESP"

grant_permission "delete_attachment"

act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/attachments/$OWNER_ATTACHMENT_DEL")
assert_api "Attachment delete other's [member, WITH delete_attachment → 200]" "200" "$RESP"

revoke_permission "delete_attachment"

rm -f /tmp/pf-test-attach.txt

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "----- Tag permissions (create_tag / edit_tag / delete_tag) -----"

# --- create_tag ---
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/tags" "{\"name\":\"member-tag-$UNIQUE\",\"project_id\":\"$PF_PROJECT_ID\",\"color\":\"#00FF00\"}")
assert_api "Tag create [member, NO perm → 403]" "403" "$RESP"

grant_permission "create_tag"

act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/tags" "{\"name\":\"member-tag-$UNIQUE\",\"project_id\":\"$PF_PROJECT_ID\",\"color\":\"#00FF00\"}")
assert_api "Tag create [member, WITH create_tag → 201]" "201" "$RESP"
MEMBER_TAG_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$MEMBER_TAG_ID" ] && MEMBER_TAG_ID=$(json_value "$(body_from_response "$RESP")" "id")

revoke_permission "create_tag"

# --- edit_tag ---
act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/tags/$MEMBER_TAG_ID" "{\"name\":\"member-tag-updated-$UNIQUE\"}")
assert_api "Tag update [member, NO perm → 403]" "403" "$RESP"

grant_permission "edit_tag"

act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/tags/$MEMBER_TAG_ID" "{\"name\":\"member-tag-updated-$UNIQUE\"}")
assert_api "Tag update [member, WITH edit_tag → 200]" "200" "$RESP"

revoke_permission "edit_tag"

# --- delete_tag ---
act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/tags/$MEMBER_TAG_ID")
assert_api "Tag delete [member, NO perm → 403]" "403" "$RESP"

grant_permission "delete_tag"

act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/tags/$MEMBER_TAG_ID")
assert_api "Tag delete [member, WITH delete_tag → 200]" "200 204" "$RESP"

revoke_permission "delete_tag"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "----- TimeLog permissions (log_time / view_timelogs) -----"

# --- log_time (create) ---
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/time-logs" "{\"task_id\":\"$PF_TASK_ID\",\"minutes\":10,\"hours\":0,\"description\":\"member timelog denied\",\"logged_date\":\"$TODAY\"}")
assert_api "TimeLog create [member, NO perm → 403]" "403" "$RESP"

grant_permission "log_time"

act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/time-logs" "{\"task_id\":\"$PF_TASK_ID\",\"minutes\":10,\"hours\":0,\"description\":\"member timelog allowed\",\"logged_date\":\"$TODAY\"}")
assert_api "TimeLog create [member, WITH log_time → 201]" "201" "$RESP"
MEMBER_TIMELOG_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$MEMBER_TIMELOG_ID" ] && MEMBER_TIMELOG_ID=$(json_value "$(body_from_response "$RESP")" "id")

# Also test update own timelog (requires log_time)
act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/time-logs/$MEMBER_TIMELOG_ID" "{\"minutes\":20}")
assert_api "TimeLog update own [member, WITH log_time → 200]" "200" "$RESP"

# Also test delete own timelog (requires log_time)
act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/time-logs/$MEMBER_TIMELOG_ID")
assert_api "TimeLog delete own [member, WITH log_time → 200]" "200 204" "$RESP"

revoke_permission "log_time"

# --- view_timelogs ---
# NOTE: The TimeLog view policy allows ANY project member to view timelogs
# (isMember check succeeds). The view_timelogs permission is only needed for
# NON-members who are workspace members. Since our member IS a project member,
# they can always view timelogs. We test that the endpoint returns 200.
act_as "$MEMBER_TOKEN"
RESP=$(api_get "/time-logs/$OWNER_TIMELOG_ID")
assert_api "TimeLog view other's [member is project member → 200]" "200" "$RESP"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "----- Project permissions (edit_project / manage_members) -----"

# --- edit_project ---
act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/projects/$PF_PROJECT_ID" "{\"name\":\"Proj-edited-$UNIQUE\"}")
assert_api "Project update [member, NO perm → 403]" "403" "$RESP"

grant_permission "edit_project"

act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/projects/$PF_PROJECT_ID" "{\"name\":\"Proj-edited-$UNIQUE\"}")
assert_api "Project update [member, WITH edit_project → 200]" "200" "$RESP"

revoke_permission "edit_project"

# --- manage_members ---
act_as "$MEMBER_TOKEN"
RESP=$(api_get "/projects/$PF_PROJECT_ID/permission-catalog")
assert_api "Permission catalog [member, NO manage_members → 403]" "403" "$RESP"

grant_permission "manage_members"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/projects/$PF_PROJECT_ID/permission-catalog")
assert_api "Permission catalog [member, WITH manage_members → 200]" "200" "$RESP"

revoke_permission "manage_members"

# ──────────────────────────────────────────────────────────────────────────────
# Teardown
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "----- Teardown -----"
act_as "$OWNER_TOKEN"

[ -n "${MEMBER_COMMENT_ID:-}" ] && api_delete "/comments/$MEMBER_COMMENT_ID" > /dev/null 2>&1 || true
[ -n "${OWNER_COMMENT_ID:-}" ] && api_delete "/comments/$OWNER_COMMENT_ID" > /dev/null 2>&1 || true
[ -n "${MEMBER_ATTACHMENT_ID:-}" ] && api_delete "/attachments/$MEMBER_ATTACHMENT_ID" > /dev/null 2>&1 || true
[ -n "${OWNER_TAG_ID:-}" ] && api_delete "/tags/$OWNER_TAG_ID" > /dev/null 2>&1 || true
[ -n "${OWNER_TIMELOG_ID:-}" ] && api_delete "/time-logs/$OWNER_TIMELOG_ID" > /dev/null 2>&1 || true
[ -n "${MEMBER_TASK_ID:-}" ] && api_delete "/tasks/$MEMBER_TASK_ID" > /dev/null 2>&1 || true
[ -n "${PF_TASK_ID:-}" ] && api_delete "/tasks/$PF_TASK_ID" > /dev/null 2>&1 || true
[ -n "${PF_COLUMN_ID:-}" ] && api_delete "/columns/$PF_COLUMN_ID" > /dev/null 2>&1 || true
[ -n "${PF_SECTION_ID:-}" ] && api_delete "/sections/$PF_SECTION_ID" > /dev/null 2>&1 || true
[ -n "${PF_PROJECT_ID:-}" ] && api_delete "/projects/$PF_PROJECT_ID" > /dev/null 2>&1 || true
[ -n "${PF_WORKSPACE_ID:-}" ] && api_delete "/workspaces/$PF_WORKSPACE_ID" > /dev/null 2>&1 || true

echo "  Cleanup complete."

# ──────────────────────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────────────────────
print_summary_and_exit
