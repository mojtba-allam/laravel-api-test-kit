#!/bin/bash
# Run the permission grant flow test against the remote production server
# using freshly registered test users.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

export BASE_URL="https://finolo.ir/api/v1"

echo "===== Remote Permission Test — finolo.ir ====="
echo ""

# Login as owner
echo "Logging in as testowner-permflow@example.com..."
_LOGIN_RESP=$(curl -sk -X POST "$BASE_URL/auth/login" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{"email":"testowner-permflow@example.com","password":"Password123!"}')
OWNER_TOKEN=$(json_value "$_LOGIN_RESP" "data.token")
[ -z "$OWNER_TOKEN" ] && OWNER_TOKEN=$(json_value "$_LOGIN_RESP" "token")
OWNER_USER_ID=$(json_value "$_LOGIN_RESP" "data.user.id")
[ -z "$OWNER_USER_ID" ] && OWNER_USER_ID=$(json_value "$_LOGIN_RESP" "data.id")
if [ -z "$OWNER_TOKEN" ]; then
    echo "FATAL: Could not login as owner. Response: $_LOGIN_RESP"
    exit 1
fi
echo "  Owner ID: $OWNER_USER_ID"

# Login as member
echo "Logging in as testmember-permflow@example.com..."
_LOGIN_RESP=$(curl -sk -X POST "$BASE_URL/auth/login" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{"email":"testmember-permflow@example.com","password":"Password123!"}')
MEMBER_TOKEN=$(json_value "$_LOGIN_RESP" "data.token")
[ -z "$MEMBER_TOKEN" ] && MEMBER_TOKEN=$(json_value "$_LOGIN_RESP" "token")
MEMBER_USER_ID=$(json_value "$_LOGIN_RESP" "data.user.id")
[ -z "$MEMBER_USER_ID" ] && MEMBER_USER_ID=$(json_value "$_LOGIN_RESP" "data.id")
if [ -z "$MEMBER_TOKEN" ]; then
    echo "FATAL: Could not login as member. Response: $_LOGIN_RESP"
    exit 1
fi
echo "  Member ID: $MEMBER_USER_ID"

# Now run the actual test logic (inlined from test-permission-grant-flow-api.sh
# but using our tokens directly)

echo ""
echo "----- Step 1: Owner creates project infrastructure -----"
act_as "$OWNER_TOKEN"

UNIQUE="permflow-$(date +%s)-$RANDOM"

RESP=$(api_json POST "/workspaces" "{\"name\":\"WS-$UNIQUE\",\"description\":\"Permission flow test\",\"visibility\":\"private\"}")
PF_WORKSPACE_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$PF_WORKSPACE_ID" ] && PF_WORKSPACE_ID=$(json_value "$(body_from_response "$RESP")" "id")
[ -z "$PF_WORKSPACE_ID" ] && { echo "FATAL: failed to create workspace. $(body_from_response "$RESP")"; exit 1; }
echo "  Workspace: $PF_WORKSPACE_ID"

RESP=$(api_json POST "/projects" "{\"name\":\"Proj-$UNIQUE\",\"description\":\"Permission flow test\",\"workspace_id\":\"$PF_WORKSPACE_ID\"}")
PF_PROJECT_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$PF_PROJECT_ID" ] && PF_PROJECT_ID=$(json_value "$(body_from_response "$RESP")" "id")
[ -z "$PF_PROJECT_ID" ] && { echo "FATAL: failed to create project. $(body_from_response "$RESP")"; exit 1; }
echo "  Project: $PF_PROJECT_ID"

RESP=$(api_json POST "/sections" "{\"name\":\"Sec-$UNIQUE\",\"project_id\":\"$PF_PROJECT_ID\",\"sort_order\":1}")
PF_SECTION_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$PF_SECTION_ID" ] && PF_SECTION_ID=$(json_value "$(body_from_response "$RESP")" "id")
[ -z "$PF_SECTION_ID" ] && { echo "FATAL: failed to create section. $(body_from_response "$RESP")"; exit 1; }
echo "  Section: $PF_SECTION_ID"

RESP=$(api_json POST "/columns" "{\"name\":\"Col-$UNIQUE\",\"section_id\":\"$PF_SECTION_ID\",\"sort_order\":1}")
PF_COLUMN_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$PF_COLUMN_ID" ] && PF_COLUMN_ID=$(json_value "$(body_from_response "$RESP")" "id")
[ -z "$PF_COLUMN_ID" ] && { echo "FATAL: failed to create column. $(body_from_response "$RESP")"; exit 1; }
echo "  Column: $PF_COLUMN_ID"

RESP=$(api_json POST "/tasks" "{\"title\":\"Task-$UNIQUE\",\"column_id\":\"$PF_COLUMN_ID\",\"priority\":\"medium\"}")
PF_TASK_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$PF_TASK_ID" ] && PF_TASK_ID=$(json_value "$(body_from_response "$RESP")" "id")
[ -z "$PF_TASK_ID" ] && { echo "FATAL: failed to create task. $(body_from_response "$RESP")"; exit 1; }
echo "  Task: $PF_TASK_ID"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "----- Step 2: Verify owner has all permissions (project admin) -----"
act_as "$OWNER_TOKEN"

RESP=$(api_get "/projects/$PF_PROJECT_ID/my-permissions")
BODY=$(body_from_response "$RESP")
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

# Owner can create comment
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
echo ""
echo "----- Step 3: Add member with NO permissions -----"
act_as "$OWNER_TOKEN"

RESP=$(api_json POST "/projects/$PF_PROJECT_ID/members-overview" "{\"user_id\":\"$MEMBER_USER_ID\"}")
assert_api "Owner adds member to project" "201 200" "$RESP"
PF_MEMBER_ID=$(json_value "$(body_from_response "$RESP")" "data.member_id")
[ -z "$PF_MEMBER_ID" ] && PF_MEMBER_ID=$(json_value "$(body_from_response "$RESP")" "member_id")
echo "  Member record ID: $PF_MEMBER_ID"

# Clear ALL permissions
RESP=$(api_json PUT "/projects/$PF_PROJECT_ID/members/$PF_MEMBER_ID/permissions" "{\"permissions\":[]}")
assert_api "Owner clears all member permissions" "200" "$RESP"

# ──────────────────────────────────────────────────────────────────────────────
# Helpers
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
echo ""
echo "----- Section (create_section / edit_section / delete_section) -----"

act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/sections" "{\"name\":\"member-sec-$UNIQUE\",\"project_id\":\"$PF_PROJECT_ID\",\"sort_order\":2}")
assert_api "Section create [NO perm → 403]" "403" "$RESP"

grant_permission "create_section"
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/sections" "{\"name\":\"member-sec-$UNIQUE\",\"project_id\":\"$PF_PROJECT_ID\",\"sort_order\":2}")
assert_api "Section create [WITH create_section → 201]" "201" "$RESP"
MEMBER_SECTION_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$MEMBER_SECTION_ID" ] && MEMBER_SECTION_ID=$(json_value "$(body_from_response "$RESP")" "id")
revoke_permission "create_section"

act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/sections/$MEMBER_SECTION_ID" "{\"name\":\"member-sec-upd-$UNIQUE\"}")
assert_api "Section update [NO perm → 403]" "403" "$RESP"

grant_permission "edit_section"
act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/sections/$MEMBER_SECTION_ID" "{\"name\":\"member-sec-upd-$UNIQUE\"}")
assert_api "Section update [WITH edit_section → 200]" "200" "$RESP"
revoke_permission "edit_section"

act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/sections/$MEMBER_SECTION_ID")
assert_api "Section delete [NO perm → 403]" "403" "$RESP"

grant_permission "delete_section"
act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/sections/$MEMBER_SECTION_ID")
assert_api "Section delete [WITH delete_section → 200]" "200 204" "$RESP"
revoke_permission "delete_section"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "----- Column (create_column / edit_column / delete_column) -----"

act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/columns" "{\"name\":\"member-col-$UNIQUE\",\"section_id\":\"$PF_SECTION_ID\",\"sort_order\":2}")
assert_api "Column create [NO perm → 403]" "403" "$RESP"

grant_permission "create_column"
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/columns" "{\"name\":\"member-col-$UNIQUE\",\"section_id\":\"$PF_SECTION_ID\",\"sort_order\":2}")
assert_api "Column create [WITH create_column → 201]" "201" "$RESP"
MEMBER_COLUMN_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$MEMBER_COLUMN_ID" ] && MEMBER_COLUMN_ID=$(json_value "$(body_from_response "$RESP")" "id")
revoke_permission "create_column"

act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/columns/$MEMBER_COLUMN_ID" "{\"name\":\"member-col-upd-$UNIQUE\"}")
assert_api "Column update [NO perm → 403]" "403" "$RESP"

grant_permission "edit_column"
act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/columns/$MEMBER_COLUMN_ID" "{\"name\":\"member-col-upd-$UNIQUE\"}")
assert_api "Column update [WITH edit_column → 200]" "200" "$RESP"
revoke_permission "edit_column"

act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/columns/$MEMBER_COLUMN_ID")
assert_api "Column delete [NO perm → 403]" "403" "$RESP"

grant_permission "delete_column"
act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/columns/$MEMBER_COLUMN_ID")
assert_api "Column delete [WITH delete_column → 200]" "200 204" "$RESP"
revoke_permission "delete_column"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "----- Task (create_task / edit_task / delete_task) -----"

act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/tasks" "{\"title\":\"member-task-$UNIQUE\",\"column_id\":\"$PF_COLUMN_ID\",\"priority\":\"low\"}")
assert_api "Task create [NO perm → 403]" "403" "$RESP"

grant_permission "create_task"
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/tasks" "{\"title\":\"member-task-$UNIQUE\",\"column_id\":\"$PF_COLUMN_ID\",\"priority\":\"low\"}")
assert_api "Task create [WITH create_task → 201]" "201" "$RESP"
MEMBER_TASK_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$MEMBER_TASK_ID" ] && MEMBER_TASK_ID=$(json_value "$(body_from_response "$RESP")" "id")
revoke_permission "create_task"

act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/tasks/$PF_TASK_ID" "{\"title\":\"member-upd-$UNIQUE\"}")
assert_api "Task update [NO perm → 403]" "403" "$RESP"

grant_permission "edit_task"
act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/tasks/$PF_TASK_ID" "{\"title\":\"member-upd-$UNIQUE\"}")
assert_api "Task update [WITH edit_task → 200]" "200" "$RESP"
revoke_permission "edit_task"

act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/tasks/$PF_TASK_ID")
assert_api "Task delete [NO perm → 403]" "403" "$RESP"

grant_permission "delete_task"
act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/tasks/$PF_TASK_ID")
assert_api "Task delete [WITH delete_task → 200]" "200 204" "$RESP"
revoke_permission "delete_task"

# Recreate task for remaining tests
act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/tasks" "{\"title\":\"Task2-$UNIQUE\",\"column_id\":\"$PF_COLUMN_ID\",\"priority\":\"medium\"}")
PF_TASK_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$PF_TASK_ID" ] && PF_TASK_ID=$(json_value "$(body_from_response "$RESP")" "id")

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "----- Comment (create_comment / edit_comment / delete_comment) -----"

act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/comments" "{\"task_id\":\"$PF_TASK_ID\",\"content\":\"member comment denied\"}")
assert_api "Comment create [NO perm → 403]" "403" "$RESP"

grant_permission "create_comment"
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/comments" "{\"task_id\":\"$PF_TASK_ID\",\"content\":\"member comment allowed\"}")
assert_api "Comment create [WITH create_comment → 201]" "201" "$RESP"
MEMBER_COMMENT_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$MEMBER_COMMENT_ID" ] && MEMBER_COMMENT_ID=$(json_value "$(body_from_response "$RESP")" "id")
revoke_permission "create_comment"

# Edit another's comment
act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/comments" "{\"task_id\":\"$PF_TASK_ID\",\"content\":\"owner comment for edit test\"}")
OWNER_COMMENT_EDIT=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$OWNER_COMMENT_EDIT" ] && OWNER_COMMENT_EDIT=$(json_value "$(body_from_response "$RESP")" "id")

act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/comments/$OWNER_COMMENT_EDIT" "{\"content\":\"member edit attempt\"}")
assert_api "Comment edit other's [NO perm → 403]" "403" "$RESP"

grant_permission "edit_comment"
act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/comments/$OWNER_COMMENT_EDIT" "{\"content\":\"member edit allowed\"}")
assert_api "Comment edit other's [WITH edit_comment → 200]" "200" "$RESP"
revoke_permission "edit_comment"

# Delete another's comment
act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/comments" "{\"task_id\":\"$PF_TASK_ID\",\"content\":\"owner comment for delete test\"}")
OWNER_COMMENT_DEL=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$OWNER_COMMENT_DEL" ] && OWNER_COMMENT_DEL=$(json_value "$(body_from_response "$RESP")" "id")

act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/comments/$OWNER_COMMENT_DEL")
assert_api "Comment delete other's [NO perm → 403]" "403" "$RESP"

grant_permission "delete_comment"
act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/comments/$OWNER_COMMENT_DEL")
assert_api "Comment delete other's [WITH delete_comment → 200]" "200" "$RESP"
revoke_permission "delete_comment"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "----- Attachment (upload_attachment / delete_attachment) -----"
echo "permission-flow-test" > /tmp/pf-test-attach.txt

act_as "$MEMBER_TOKEN"
RESP=$(api_multipart POST "/attachments/upload" -F "file=@/tmp/pf-test-attach.txt" -F "task_id=$PF_TASK_ID")
assert_api "Attachment upload [NO perm → 403]" "403" "$RESP"

grant_permission "upload_attachment"
act_as "$MEMBER_TOKEN"
RESP=$(api_multipart POST "/attachments/upload" -F "file=@/tmp/pf-test-attach.txt" -F "task_id=$PF_TASK_ID")
assert_api "Attachment upload [WITH upload_attachment → 201]" "201" "$RESP"
MEMBER_ATT_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$MEMBER_ATT_ID" ] && MEMBER_ATT_ID=$(json_value "$(body_from_response "$RESP")" "id")
revoke_permission "upload_attachment"

# Delete another's attachment
act_as "$OWNER_TOKEN"
RESP=$(api_multipart POST "/attachments/upload" -F "file=@/tmp/pf-test-attach.txt" -F "task_id=$PF_TASK_ID")
OWNER_ATT_DEL=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$OWNER_ATT_DEL" ] && OWNER_ATT_DEL=$(json_value "$(body_from_response "$RESP")" "id")

act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/attachments/$OWNER_ATT_DEL")
assert_api "Attachment delete other's [NO perm → 403]" "403" "$RESP"

grant_permission "delete_attachment"
act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/attachments/$OWNER_ATT_DEL")
assert_api "Attachment delete other's [WITH delete_attachment → 200]" "200" "$RESP"
revoke_permission "delete_attachment"
rm -f /tmp/pf-test-attach.txt

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "----- Tag (create_tag / edit_tag / delete_tag) -----"

act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/tags" "{\"name\":\"member-tag-$UNIQUE\",\"project_id\":\"$PF_PROJECT_ID\",\"color\":\"#00FF00\"}")
assert_api "Tag create [NO perm → 403]" "403" "$RESP"

grant_permission "create_tag"
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/tags" "{\"name\":\"member-tag-$UNIQUE\",\"project_id\":\"$PF_PROJECT_ID\",\"color\":\"#00FF00\"}")
assert_api "Tag create [WITH create_tag → 201]" "201" "$RESP"
MEMBER_TAG_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$MEMBER_TAG_ID" ] && MEMBER_TAG_ID=$(json_value "$(body_from_response "$RESP")" "id")
revoke_permission "create_tag"

act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/tags/$MEMBER_TAG_ID" "{\"name\":\"member-tag-upd-$UNIQUE\"}")
assert_api "Tag update [NO perm → 403]" "403" "$RESP"

grant_permission "edit_tag"
act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/tags/$MEMBER_TAG_ID" "{\"name\":\"member-tag-upd-$UNIQUE\"}")
assert_api "Tag update [WITH edit_tag → 200]" "200" "$RESP"
revoke_permission "edit_tag"

act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/tags/$MEMBER_TAG_ID")
assert_api "Tag delete [NO perm → 403]" "403" "$RESP"

grant_permission "delete_tag"
act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/tags/$MEMBER_TAG_ID")
assert_api "Tag delete [WITH delete_tag → 200]" "200 204" "$RESP"
revoke_permission "delete_tag"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "----- TimeLog (log_time) -----"

act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/time-logs" "{\"task_id\":\"$PF_TASK_ID\",\"minutes\":10,\"hours\":0,\"description\":\"denied\",\"logged_date\":\"$TODAY\"}")
assert_api "TimeLog create [NO perm → 403]" "403" "$RESP"

grant_permission "log_time"
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/time-logs" "{\"task_id\":\"$PF_TASK_ID\",\"minutes\":10,\"hours\":0,\"description\":\"allowed\",\"logged_date\":\"$TODAY\"}")
assert_api "TimeLog create [WITH log_time → 201]" "201" "$RESP"
MEMBER_TL_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$MEMBER_TL_ID" ] && MEMBER_TL_ID=$(json_value "$(body_from_response "$RESP")" "id")
revoke_permission "log_time"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "----- Project (edit_project / manage_members) -----"

act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/projects/$PF_PROJECT_ID" "{\"name\":\"Proj-edit-$UNIQUE\"}")
assert_api "Project update [NO perm → 403]" "403" "$RESP"

grant_permission "edit_project"
act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/projects/$PF_PROJECT_ID" "{\"name\":\"Proj-edit-$UNIQUE\"}")
assert_api "Project update [WITH edit_project → 200]" "200" "$RESP"
revoke_permission "edit_project"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/projects/$PF_PROJECT_ID/permission-catalog")
assert_api "Permission catalog [NO manage_members → 403]" "403" "$RESP"

grant_permission "manage_members"
act_as "$MEMBER_TOKEN"
RESP=$(api_get "/projects/$PF_PROJECT_ID/permission-catalog")
assert_api "Permission catalog [WITH manage_members → 200]" "200" "$RESP"
revoke_permission "manage_members"

# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "----- Teardown -----"
act_as "$OWNER_TOKEN"
[ -n "${MEMBER_COMMENT_ID:-}" ] && api_delete "/comments/$MEMBER_COMMENT_ID" > /dev/null 2>&1 || true
[ -n "${OWNER_COMMENT_ID:-}" ] && api_delete "/comments/$OWNER_COMMENT_ID" > /dev/null 2>&1 || true
[ -n "${OWNER_COMMENT_EDIT:-}" ] && api_delete "/comments/$OWNER_COMMENT_EDIT" > /dev/null 2>&1 || true
[ -n "${MEMBER_ATT_ID:-}" ] && api_delete "/attachments/$MEMBER_ATT_ID" > /dev/null 2>&1 || true
[ -n "${OWNER_TAG_ID:-}" ] && api_delete "/tags/$OWNER_TAG_ID" > /dev/null 2>&1 || true
[ -n "${OWNER_TIMELOG_ID:-}" ] && api_delete "/time-logs/$OWNER_TIMELOG_ID" > /dev/null 2>&1 || true
[ -n "${MEMBER_TL_ID:-}" ] && api_delete "/time-logs/$MEMBER_TL_ID" > /dev/null 2>&1 || true
[ -n "${MEMBER_TASK_ID:-}" ] && api_delete "/tasks/$MEMBER_TASK_ID" > /dev/null 2>&1 || true
[ -n "${PF_TASK_ID:-}" ] && api_delete "/tasks/$PF_TASK_ID" > /dev/null 2>&1 || true
[ -n "${PF_COLUMN_ID:-}" ] && api_delete "/columns/$PF_COLUMN_ID" > /dev/null 2>&1 || true
[ -n "${PF_SECTION_ID:-}" ] && api_delete "/sections/$PF_SECTION_ID" > /dev/null 2>&1 || true
[ -n "${PF_PROJECT_ID:-}" ] && api_delete "/projects/$PF_PROJECT_ID" > /dev/null 2>&1 || true
[ -n "${PF_WORKSPACE_ID:-}" ] && api_delete "/workspaces/$PF_WORKSPACE_ID" > /dev/null 2>&1 || true
echo "  Cleanup complete."

print_summary_and_exit
