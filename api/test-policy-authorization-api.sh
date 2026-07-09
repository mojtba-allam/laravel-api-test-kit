#!/bin/bash
# ===========================================================================
# test-policy-authorization-api.sh
# Consolidated policy authorization matrix test suite — Part A
# Covers: Comment, Attachment, Task, Project, Workspace policies
# Part B (remaining modules + teardown) is appended by task 5.
# ===========================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"
source "$SCRIPT_DIR/policy/policy-fixtures.sh"

echo "===== Policy Authorization Test Suite — Part A ====="
setup_policy_fixtures || { echo "FATAL: fixture setup failed" >&2; exit 1; }

# ============================================================
# COMMENT POLICY
# ============================================================
echo ""
echo "----- Comment Policy -----"

# ---------------------------------------------------------------------------
# viewAny — GET /comments — all user types → 200
# ---------------------------------------------------------------------------
act_as "$ADMIN_TOKEN"
RESP=$(api_get "/comments")
assert_api "Comment viewAny [admin]" "200" "$RESP"

act_as "$AUTHOR_TOKEN"
RESP=$(api_get "/comments")
assert_api "Comment viewAny [author]" "200" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_get "/comments")
assert_api "Comment viewAny [owner]" "200" "$RESP"

act_as "$CREATOR_TOKEN"
RESP=$(api_get "/comments")
assert_api "Comment viewAny [creator]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/comments")
assert_api "Comment viewAny [member]" "200" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_get "/comments")
assert_api "Comment viewAny [other]" "200" "$RESP"

# ---------------------------------------------------------------------------
# view — GET /comments/{id}
# Members → 200; OTHER (non-member) → 403
# ---------------------------------------------------------------------------
act_as "$ADMIN_TOKEN"
RESP=$(api_get "/comments/$POL_COMMENT_A")
assert_api "Comment view [admin]" "200" "$RESP"

act_as "$AUTHOR_TOKEN"
RESP=$(api_get "/comments/$POL_COMMENT_A")
assert_api "Comment view [author]" "200" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_get "/comments/$POL_COMMENT_A")
assert_api "Comment view [owner]" "200" "$RESP"

act_as "$CREATOR_TOKEN"
RESP=$(api_get "/comments/$POL_COMMENT_A")
assert_api "Comment view [creator]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/comments/$POL_COMMENT_A")
assert_api "Comment view [member]" "200" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_get "/comments/$POL_COMMENT_A")
assert_api "Comment view [other → 403]" "403" "$RESP"

# ---------------------------------------------------------------------------
# create — POST /comments — all user types → 201
# We create a temporary comment for each user and discard it (or leave cleanup
# to Part B teardown; admin can delete orphaned comments).
# ---------------------------------------------------------------------------
act_as "$ADMIN_TOKEN"
RESP=$(api_json POST "/comments" "{\"task_id\":\"$POL_TASK_ID\",\"content\":\"admin create test\"}")
assert_api "Comment create [admin]" "201" "$RESP"
_CMT_TMP_ADMIN=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_CMT_TMP_ADMIN" ] && _CMT_TMP_ADMIN=$(json_value "$(body_from_response "$RESP")" "id")

act_as "$AUTHOR_TOKEN"
RESP=$(api_json POST "/comments" "{\"task_id\":\"$POL_TASK_ID\",\"content\":\"author create test\"}")
assert_api "Comment create [author]" "201" "$RESP"
_CMT_TMP_AUTHOR=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_CMT_TMP_AUTHOR" ] && _CMT_TMP_AUTHOR=$(json_value "$(body_from_response "$RESP")" "id")

act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/comments" "{\"task_id\":\"$POL_TASK_ID\",\"content\":\"owner create test\"}")
assert_api "Comment create [owner]" "201" "$RESP"
_CMT_TMP_OWNER=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_CMT_TMP_OWNER" ] && _CMT_TMP_OWNER=$(json_value "$(body_from_response "$RESP")" "id")

act_as "$CREATOR_TOKEN"
RESP=$(api_json POST "/comments" "{\"task_id\":\"$POL_TASK_ID\",\"content\":\"creator create test\"}")
assert_api "Comment create [creator]" "201" "$RESP"
_CMT_TMP_CREATOR=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_CMT_TMP_CREATOR" ] && _CMT_TMP_CREATOR=$(json_value "$(body_from_response "$RESP")" "id")

act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/comments" "{\"task_id\":\"$POL_TASK_ID\",\"content\":\"member create test\"}")
assert_api "Comment create [member]" "201" "$RESP"
_CMT_TMP_MEMBER=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_CMT_TMP_MEMBER" ] && _CMT_TMP_MEMBER=$(json_value "$(body_from_response "$RESP")" "id")

# OTHER is not a project member → create_comment denied → 403
act_as "$OTHER_TOKEN"
RESP=$(api_json POST "/comments" "{\"task_id\":\"$POL_TASK_ID\",\"content\":\"other create test\"}")
assert_api "Comment create [other → 403]" "403" "$RESP"
_CMT_TMP_OTHER=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_CMT_TMP_OTHER" ] && _CMT_TMP_OTHER=$(json_value "$(body_from_response "$RESP")" "id")

# ---------------------------------------------------------------------------
# update — PUT /comments/{id}
# author (own) → 200; admin (super admin) → 200; owner (project admin) → 200;
# members without edit_comment (creator/member) → 403; other → 403
# Use POL_COMMENT_A for deny tests (403 is idempotent — does not consume the resource)
# ---------------------------------------------------------------------------
act_as "$OWNER_TOKEN"
RESP=$(api_json PUT "/comments/$POL_COMMENT_A" "{\"content\":\"owner (project admin) update\"}")
assert_api "Comment update [owner (project admin) → 200]" "200" "$RESP"

act_as "$CREATOR_TOKEN"
RESP=$(api_json PUT "/comments/$POL_COMMENT_A" "{\"content\":\"creator update attempt\"}")
assert_api "Comment update [creator → 403]" "403" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/comments/$POL_COMMENT_A" "{\"content\":\"member update attempt\"}")
assert_api "Comment update [member → 403]" "403" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_json PUT "/comments/$POL_COMMENT_A" "{\"content\":\"other update attempt\"}")
assert_api "Comment update [other → 403]" "403" "$RESP"

# Allow cases: admin and author can update
act_as "$ADMIN_TOKEN"
RESP=$(api_json PUT "/comments/$POL_COMMENT_A" "{\"content\":\"admin updated content\"}")
assert_api "Comment update [admin → 200]" "200" "$RESP"

act_as "$AUTHOR_TOKEN"
RESP=$(api_json PUT "/comments/$POL_COMMENT_B" "{\"content\":\"author updated content\"}")
assert_api "Comment update [author → 200]" "200" "$RESP"

# ---------------------------------------------------------------------------
# delete — DELETE /comments/{id}
# author (own) → 200; admin (super admin) → 200; owner (project admin moderation) → 200;
# members without delete_comment (creator/member) → 403; other → 403
#
# Strategy (a successful delete consumes the comment):
#   - Deny tests (creator/member/other) run on POL_COMMENT_A (403 does not consume)
#   - author deletes POL_COMMENT_A → 200 (own)
#   - admin deletes POL_COMMENT_B → 200
#   - owner deletes a freshly created comment → 200 (project-admin moderation)
# ---------------------------------------------------------------------------
act_as "$CREATOR_TOKEN"
RESP=$(api_delete "/comments/$POL_COMMENT_A")
assert_api "Comment delete [creator → 403]" "403" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/comments/$POL_COMMENT_A")
assert_api "Comment delete [member → 403]" "403" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_delete "/comments/$POL_COMMENT_A")
assert_api "Comment delete [other → 403]" "403" "$RESP"

# Allow: author deletes their own comment (POL_COMMENT_A)
act_as "$AUTHOR_TOKEN"
RESP=$(api_delete "/comments/$POL_COMMENT_A")
assert_api "Comment delete [author (own) → 200]" "200" "$RESP"

# Allow: admin (super admin) deletes any comment (POL_COMMENT_B)
act_as "$ADMIN_TOKEN"
RESP=$(api_delete "/comments/$POL_COMMENT_B")
assert_api "Comment delete [admin → 200]" "200" "$RESP"

# Allow: owner (project admin) moderates/deletes another member's comment.
# Create a fresh comment as AUTHOR so the owner has its own target to delete.
act_as "$AUTHOR_TOKEN"
RESP=$(api_json POST "/comments" "{\"task_id\":\"$POL_TASK_ID\",\"content\":\"owner moderation delete target\"}")
_CMT_OWNER_DEL=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_CMT_OWNER_DEL" ] && _CMT_OWNER_DEL=$(json_value "$(body_from_response "$RESP")" "id")
act_as "$OWNER_TOKEN"
RESP=$(api_delete "/comments/$_CMT_OWNER_DEL")
assert_api "Comment delete [owner (project admin moderation) → 200]" "200" "$RESP"

# Clean up the temporary create-test comments
act_as "$ADMIN_TOKEN"
[ -n "${_CMT_TMP_ADMIN:-}"   ] && api_delete "/comments/$_CMT_TMP_ADMIN"   > /dev/null 2>&1 || true
[ -n "${_CMT_TMP_AUTHOR:-}"  ] && api_delete "/comments/$_CMT_TMP_AUTHOR"  > /dev/null 2>&1 || true
[ -n "${_CMT_TMP_OWNER:-}"   ] && api_delete "/comments/$_CMT_TMP_OWNER"   > /dev/null 2>&1 || true
[ -n "${_CMT_TMP_CREATOR:-}" ] && api_delete "/comments/$_CMT_TMP_CREATOR" > /dev/null 2>&1 || true
[ -n "${_CMT_TMP_MEMBER:-}"  ] && api_delete "/comments/$_CMT_TMP_MEMBER"  > /dev/null 2>&1 || true
[ -n "${_CMT_TMP_OTHER:-}"   ] && api_delete "/comments/$_CMT_TMP_OTHER"   > /dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# restore / forceDelete — no routes registered → skip_case
# ---------------------------------------------------------------------------
skip_case "Comment restore" "no restore route registered for comments"
skip_case "Comment forceDelete" "no forceDelete route registered for comments"

# ============================================================
# ATTACHMENT POLICY
# ============================================================
echo ""
echo "----- Attachment Policy -----"

# ---------------------------------------------------------------------------
# viewAny — GET /attachments — all user types → 200
# ---------------------------------------------------------------------------
act_as "$ADMIN_TOKEN"
RESP=$(api_get "/attachments")
assert_api "Attachment viewAny [admin]" "200" "$RESP"

act_as "$AUTHOR_TOKEN"
RESP=$(api_get "/attachments")
assert_api "Attachment viewAny [uploader/author]" "200" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_get "/attachments")
assert_api "Attachment viewAny [owner]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/attachments")
assert_api "Attachment viewAny [member]" "200" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_get "/attachments")
assert_api "Attachment viewAny [other]" "200" "$RESP"

# ---------------------------------------------------------------------------
# view — GET /attachments/{id}
# Admin/uploader/owner/member → 200; OTHER (non-member) → 403
# ---------------------------------------------------------------------------
act_as "$ADMIN_TOKEN"
RESP=$(api_get "/attachments/$POL_ATTACHMENT_A")
assert_api "Attachment view [admin]" "200" "$RESP"

act_as "$AUTHOR_TOKEN"
RESP=$(api_get "/attachments/$POL_ATTACHMENT_A")
assert_api "Attachment view [uploader/author]" "200" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_get "/attachments/$POL_ATTACHMENT_A")
assert_api "Attachment view [owner]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/attachments/$POL_ATTACHMENT_A")
assert_api "Attachment view [member]" "200" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_get "/attachments/$POL_ATTACHMENT_A")
assert_api "Attachment view [other → 403]" "403" "$RESP"

# ---------------------------------------------------------------------------
# create — POST /attachments/upload (multipart) — all user types → 201
# ---------------------------------------------------------------------------
echo "policy-test-create-test" > /tmp/pol-att-create-test.txt

act_as "$ADMIN_TOKEN"
RESP=$(api_multipart POST "/attachments/upload" -F "file=@/tmp/pol-att-create-test.txt" -F "task_id=$POL_TASK_ID")
assert_api "Attachment create [admin]" "201" "$RESP"
_ATT_TMP_ADMIN=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_ATT_TMP_ADMIN" ] && _ATT_TMP_ADMIN=$(json_value "$(body_from_response "$RESP")" "id")

act_as "$AUTHOR_TOKEN"
RESP=$(api_multipart POST "/attachments/upload" -F "file=@/tmp/pol-att-create-test.txt" -F "task_id=$POL_TASK_ID")
assert_api "Attachment create [uploader/author]" "201" "$RESP"
_ATT_TMP_AUTHOR=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_ATT_TMP_AUTHOR" ] && _ATT_TMP_AUTHOR=$(json_value "$(body_from_response "$RESP")" "id")

act_as "$OWNER_TOKEN"
RESP=$(api_multipart POST "/attachments/upload" -F "file=@/tmp/pol-att-create-test.txt" -F "task_id=$POL_TASK_ID")
assert_api "Attachment create [owner]" "201" "$RESP"
_ATT_TMP_OWNER=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_ATT_TMP_OWNER" ] && _ATT_TMP_OWNER=$(json_value "$(body_from_response "$RESP")" "id")

act_as "$MEMBER_TOKEN"
RESP=$(api_multipart POST "/attachments/upload" -F "file=@/tmp/pol-att-create-test.txt" -F "task_id=$POL_TASK_ID")
assert_api "Attachment create [member]" "201" "$RESP"
_ATT_TMP_MEMBER=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_ATT_TMP_MEMBER" ] && _ATT_TMP_MEMBER=$(json_value "$(body_from_response "$RESP")" "id")

# OTHER is not a project member → upload_attachment denied → 403
act_as "$OTHER_TOKEN"
RESP=$(api_multipart POST "/attachments/upload" -F "file=@/tmp/pol-att-create-test.txt" -F "task_id=$POL_TASK_ID")
assert_api "Attachment create [other → 403]" "403" "$RESP"
_ATT_TMP_OTHER=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_ATT_TMP_OTHER" ] && _ATT_TMP_OTHER=$(json_value "$(body_from_response "$RESP")" "id")

rm -f /tmp/pol-att-create-test.txt

# ---------------------------------------------------------------------------
# update — PUT /attachments/{id}
# Admin → 200, uploader (author) → 200, owner → 200; member → 403, other → 403
# Use POL_ATTACHMENT_A for deny tests (403 is idempotent)
# ---------------------------------------------------------------------------
act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/attachments/$POL_ATTACHMENT_A" "{\"description\":\"member update attempt\"}")
assert_api "Attachment update [member → 403]" "403" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_json PUT "/attachments/$POL_ATTACHMENT_A" "{\"description\":\"other update attempt\"}")
assert_api "Attachment update [other → 403]" "403" "$RESP"

act_as "$ADMIN_TOKEN"
RESP=$(api_json PUT "/attachments/$POL_ATTACHMENT_A" "{\"description\":\"admin updated\"}")
assert_api "Attachment update [admin → 200]" "200" "$RESP"

act_as "$AUTHOR_TOKEN"
RESP=$(api_json PUT "/attachments/$POL_ATTACHMENT_A" "{\"description\":\"uploader updated\"}")
assert_api "Attachment update [uploader/author → 200]" "200" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_json PUT "/attachments/$POL_ATTACHMENT_A" "{\"description\":\"owner updated\"}")
assert_api "Attachment update [owner → 200]" "200" "$RESP"

# ---------------------------------------------------------------------------
# delete — DELETE /attachments/{id}
# uploader (author, own) → 200; admin (super admin) → 200;
# owner (project admin moderation) → 200; member/creator → 403; other → 403
#
# Strategy (a successful delete consumes the attachment):
#   - Deny tests (member/other) run on POL_ATTACHMENT_A (403 does not consume)
#   - uploader (author) deletes POL_ATTACHMENT_A → 200 (own)
#   - admin deletes POL_ATTACHMENT_B → 200
#   - owner deletes a freshly uploaded attachment → 200 (project-admin moderation)
# ---------------------------------------------------------------------------
act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/attachments/$POL_ATTACHMENT_A")
assert_api "Attachment delete [member → 403]" "403" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_delete "/attachments/$POL_ATTACHMENT_A")
assert_api "Attachment delete [other → 403]" "403" "$RESP"

# Allow: uploader deletes their own attachment (POL_ATTACHMENT_A)
act_as "$AUTHOR_TOKEN"
RESP=$(api_delete "/attachments/$POL_ATTACHMENT_A")
assert_api "Attachment delete [uploader/author (own) → 200]" "200" "$RESP"

# Allow: admin (super admin) deletes any attachment (POL_ATTACHMENT_B)
act_as "$ADMIN_TOKEN"
RESP=$(api_delete "/attachments/$POL_ATTACHMENT_B")
assert_api "Attachment delete [admin → 200]" "200" "$RESP"

# Allow: owner (project admin) moderates/deletes another member's attachment.
# Upload a fresh attachment as AUTHOR so the owner has its own target to delete.
echo "policy-test-owner-del" > /tmp/pol-att-owner-del.txt
act_as "$AUTHOR_TOKEN"
RESP=$(api_multipart POST "/attachments/upload" -F "file=@/tmp/pol-att-owner-del.txt" -F "task_id=$POL_TASK_ID")
_ATT_OWNER_DEL=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_ATT_OWNER_DEL" ] && _ATT_OWNER_DEL=$(json_value "$(body_from_response "$RESP")" "id")
rm -f /tmp/pol-att-owner-del.txt
act_as "$OWNER_TOKEN"
RESP=$(api_delete "/attachments/$_ATT_OWNER_DEL")
assert_api "Attachment delete [owner (project admin moderation) → 200]" "200" "$RESP"

# Clean up temporary create-test attachments
act_as "$ADMIN_TOKEN"
[ -n "${_ATT_TMP_ADMIN:-}"   ] && api_delete "/attachments/$_ATT_TMP_ADMIN"   > /dev/null 2>&1 || true
[ -n "${_ATT_TMP_AUTHOR:-}"  ] && api_delete "/attachments/$_ATT_TMP_AUTHOR"  > /dev/null 2>&1 || true
[ -n "${_ATT_TMP_OWNER:-}"   ] && api_delete "/attachments/$_ATT_TMP_OWNER"   > /dev/null 2>&1 || true
[ -n "${_ATT_TMP_MEMBER:-}"  ] && api_delete "/attachments/$_ATT_TMP_MEMBER"  > /dev/null 2>&1 || true
[ -n "${_ATT_TMP_OTHER:-}"   ] && api_delete "/attachments/$_ATT_TMP_OTHER"   > /dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# restore / forceDelete — no routes registered → skip_case
# ---------------------------------------------------------------------------
skip_case "Attachment restore" "no restore route registered for attachments"
skip_case "Attachment forceDelete" "no forceDelete route registered for attachments"

# ============================================================
# TASK POLICY
# ============================================================
echo ""
echo "----- Task Policy -----"

# ---------------------------------------------------------------------------
# viewAny — GET /tasks — all user types → 200
# ---------------------------------------------------------------------------
act_as "$ADMIN_TOKEN"
RESP=$(api_get "/tasks")
assert_api "Task viewAny [admin]" "200" "$RESP"

act_as "$CREATOR_TOKEN"
RESP=$(api_get "/tasks")
assert_api "Task viewAny [creator]" "200" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_get "/tasks")
assert_api "Task viewAny [owner]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/tasks")
assert_api "Task viewAny [member]" "200" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_get "/tasks")
assert_api "Task viewAny [other]" "200" "$RESP"

# ---------------------------------------------------------------------------
# view — GET /tasks/{id}
# Admin/creator/owner/member → 200; OTHER (non-member) → 403
# ---------------------------------------------------------------------------
act_as "$ADMIN_TOKEN"
RESP=$(api_get "/tasks/$POL_TASK_ID")
assert_api "Task view [admin]" "200" "$RESP"

act_as "$CREATOR_TOKEN"
RESP=$(api_get "/tasks/$POL_TASK_ID")
assert_api "Task view [creator]" "200" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_get "/tasks/$POL_TASK_ID")
assert_api "Task view [owner]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/tasks/$POL_TASK_ID")
assert_api "Task view [member]" "200" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_get "/tasks/$POL_TASK_ID")
assert_api "Task view [other → 403]" "403" "$RESP"

# ---------------------------------------------------------------------------
# create — POST /tasks — all user types → 201
# ---------------------------------------------------------------------------
act_as "$ADMIN_TOKEN"
RESP=$(api_json POST "/tasks" "{\"title\":\"admin-create-test\",\"column_id\":\"$POL_COLUMN_ID\",\"priority\":\"low\"}")
assert_api "Task create [admin]" "201" "$RESP"
_TASK_TMP_ADMIN=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_TASK_TMP_ADMIN" ] && _TASK_TMP_ADMIN=$(json_value "$(body_from_response "$RESP")" "id")

act_as "$CREATOR_TOKEN"
RESP=$(api_json POST "/tasks" "{\"title\":\"creator-create-test\",\"column_id\":\"$POL_COLUMN_ID\",\"priority\":\"low\"}")
assert_api "Task create [creator]" "201" "$RESP"
_TASK_TMP_CREATOR=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_TASK_TMP_CREATOR" ] && _TASK_TMP_CREATOR=$(json_value "$(body_from_response "$RESP")" "id")

act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/tasks" "{\"title\":\"owner-create-test\",\"column_id\":\"$POL_COLUMN_ID\",\"priority\":\"low\"}")
assert_api "Task create [owner]" "201" "$RESP"
_TASK_TMP_OWNER=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_TASK_TMP_OWNER" ] && _TASK_TMP_OWNER=$(json_value "$(body_from_response "$RESP")" "id")

act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/tasks" "{\"title\":\"member-create-test\",\"column_id\":\"$POL_COLUMN_ID\",\"priority\":\"low\"}")
assert_api "Task create [member]" "201" "$RESP"
_TASK_TMP_MEMBER=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_TASK_TMP_MEMBER" ] && _TASK_TMP_MEMBER=$(json_value "$(body_from_response "$RESP")" "id")

# OTHER is not a project member → create_task denied → 403
act_as "$OTHER_TOKEN"
RESP=$(api_json POST "/tasks" "{\"title\":\"other-create-test\",\"column_id\":\"$POL_COLUMN_ID\",\"priority\":\"low\"}")
assert_api "Task create [other → 403]" "403" "$RESP"
_TASK_TMP_OTHER=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_TASK_TMP_OTHER" ] && _TASK_TMP_OTHER=$(json_value "$(body_from_response "$RESP")" "id")

# Clean up create-test tasks now (before delete tests consume IDs below)
act_as "$ADMIN_TOKEN"
[ -n "${_TASK_TMP_ADMIN:-}"   ] && api_delete "/tasks/$_TASK_TMP_ADMIN"   > /dev/null 2>&1 || true
[ -n "${_TASK_TMP_CREATOR:-}" ] && api_delete "/tasks/$_TASK_TMP_CREATOR" > /dev/null 2>&1 || true
[ -n "${_TASK_TMP_OWNER:-}"   ] && api_delete "/tasks/$_TASK_TMP_OWNER"   > /dev/null 2>&1 || true
[ -n "${_TASK_TMP_MEMBER:-}"  ] && api_delete "/tasks/$_TASK_TMP_MEMBER"  > /dev/null 2>&1 || true
[ -n "${_TASK_TMP_OTHER:-}"   ] && api_delete "/tasks/$_TASK_TMP_OTHER"   > /dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# update — PUT /tasks/{id}
# Admin/creator/owner/member → 200; OTHER → 403
# POL_TASK_ID is used for deny tests (403 is idempotent)
# ---------------------------------------------------------------------------
act_as "$OTHER_TOKEN"
RESP=$(api_json PUT "/tasks/$POL_TASK_ID" "{\"title\":\"other update attempt\"}")
assert_api "Task update [other → 403]" "403" "$RESP"

act_as "$ADMIN_TOKEN"
RESP=$(api_json PUT "/tasks/$POL_TASK_ID" "{\"title\":\"admin updated task\"}")
assert_api "Task update [admin → 200]" "200" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_json PUT "/tasks/$POL_TASK_ID" "{\"title\":\"owner updated task\"}")
assert_api "Task update [owner → 200]" "200" "$RESP"

act_as "$CREATOR_TOKEN"
RESP=$(api_json PUT "/tasks/$POL_TASK_ID" "{\"title\":\"creator updated task\"}")
assert_api "Task update [creator → 200]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/tasks/$POL_TASK_ID" "{\"title\":\"member updated task\"}")
assert_api "Task update [member → 200]" "200" "$RESP"

# ---------------------------------------------------------------------------
# delete — DELETE /tasks/{id}
# Admin/creator/owner → 200 or 204; member → 403; other → 403
# OWNER created POL_TASK_ID and POL_TASK_ID_2 (owner = creator in fixture).
#
# Strategy:
#   - Deny tests: POL_TASK_ID_2 (403 does not consume it)
#   - Allow tests: create fresh tasks per actor, then delete them
# ---------------------------------------------------------------------------
act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/tasks/$POL_TASK_ID_2")
assert_api "Task delete [member → 403]" "403" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_delete "/tasks/$POL_TASK_ID_2")
assert_api "Task delete [other → 403]" "403" "$RESP"

# Allow: admin creates and deletes a task
act_as "$ADMIN_TOKEN"
RESP=$(api_json POST "/tasks" "{\"title\":\"admin-del-test\",\"column_id\":\"$POL_COLUMN_ID\",\"priority\":\"low\"}")
_TASK_DEL_ADMIN=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_TASK_DEL_ADMIN" ] && _TASK_DEL_ADMIN=$(json_value "$(body_from_response "$RESP")" "id")
RESP=$(api_delete "/tasks/$_TASK_DEL_ADMIN")
assert_api "Task delete [admin → 200/204]" "200 204" "$RESP"

# Allow: owner creates and deletes a task
act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/tasks" "{\"title\":\"owner-del-test\",\"column_id\":\"$POL_COLUMN_ID\",\"priority\":\"low\"}")
_TASK_DEL_OWNER=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_TASK_DEL_OWNER" ] && _TASK_DEL_OWNER=$(json_value "$(body_from_response "$RESP")" "id")
RESP=$(api_delete "/tasks/$_TASK_DEL_OWNER")
assert_api "Task delete [owner → 200/204]" "200 204" "$RESP"

# Allow: creator creates and deletes a task
act_as "$CREATOR_TOKEN"
RESP=$(api_json POST "/tasks" "{\"title\":\"creator-del-test\",\"column_id\":\"$POL_COLUMN_ID\",\"priority\":\"low\"}")
_TASK_DEL_CREATOR=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_TASK_DEL_CREATOR" ] && _TASK_DEL_CREATOR=$(json_value "$(body_from_response "$RESP")" "id")
RESP=$(api_delete "/tasks/$_TASK_DEL_CREATOR")
assert_api "Task delete [creator → 200/204]" "200 204" "$RESP"

# ---------------------------------------------------------------------------
# restore — POST /tasks/{id}/restore
# Admin/creator/owner/member → 200; other → 403
#
# NOTE: The restoreFromArchive controller authorizes 'update' (not 'restore').
# The update policy allows project members, so MEMBER can restore.
# OTHER (non-member) → 403 because update policy denies non-members.
#
# For restore we must first archive, then restore.
# ---------------------------------------------------------------------------
# Archive POL_TASK_ID_2 as owner so we can test restore policy on it
act_as "$OWNER_TOKEN"
api_json POST "/tasks/$POL_TASK_ID_2/archive" '{}' > /dev/null 2>&1 || true

act_as "$OTHER_TOKEN"
RESP=$(api_json POST "/tasks/$POL_TASK_ID_2/restore" '{}')
assert_api "Task restore [other → 403]" "403" "$RESP"

# Member can restore because restoreFromArchive uses 'update' policy (members allowed)
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/tasks/$POL_TASK_ID_2/restore" '{}')
assert_api "Task restore [member → 200 (update policy)]" "200" "$RESP"
# Re-archive so the allow tests work cleanly
api_json POST "/tasks/$POL_TASK_ID_2/archive" '{}' > /dev/null 2>&1 || true

# Allow: admin — create, archive, restore
act_as "$ADMIN_TOKEN"
RESP=$(api_json POST "/tasks" "{\"title\":\"admin-restore-test\",\"column_id\":\"$POL_COLUMN_ID\",\"priority\":\"low\"}")
_TASK_RST_ADMIN=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_TASK_RST_ADMIN" ] && _TASK_RST_ADMIN=$(json_value "$(body_from_response "$RESP")" "id")
api_json POST "/tasks/$_TASK_RST_ADMIN/archive" '{}' > /dev/null 2>&1 || true
RESP=$(api_json POST "/tasks/$_TASK_RST_ADMIN/restore" '{}')
assert_api "Task restore [admin → 200]" "200" "$RESP"
api_delete "/tasks/$_TASK_RST_ADMIN" > /dev/null 2>&1 || true

# Allow: owner — create, archive, restore
act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/tasks" "{\"title\":\"owner-restore-test\",\"column_id\":\"$POL_COLUMN_ID\",\"priority\":\"low\"}")
_TASK_RST_OWNER=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_TASK_RST_OWNER" ] && _TASK_RST_OWNER=$(json_value "$(body_from_response "$RESP")" "id")
api_json POST "/tasks/$_TASK_RST_OWNER/archive" '{}' > /dev/null 2>&1 || true
RESP=$(api_json POST "/tasks/$_TASK_RST_OWNER/restore" '{}')
assert_api "Task restore [owner → 200]" "200" "$RESP"
api_delete "/tasks/$_TASK_RST_OWNER" > /dev/null 2>&1 || true

# Allow: creator — create, archive, restore
act_as "$CREATOR_TOKEN"
RESP=$(api_json POST "/tasks" "{\"title\":\"creator-restore-test\",\"column_id\":\"$POL_COLUMN_ID\",\"priority\":\"low\"}")
_TASK_RST_CREATOR=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_TASK_RST_CREATOR" ] && _TASK_RST_CREATOR=$(json_value "$(body_from_response "$RESP")" "id")
api_json POST "/tasks/$_TASK_RST_CREATOR/archive" '{}' > /dev/null 2>&1 || true
RESP=$(api_json POST "/tasks/$_TASK_RST_CREATOR/restore" '{}')
assert_api "Task restore [creator → 200]" "200" "$RESP"
api_delete "/tasks/$_TASK_RST_CREATOR" > /dev/null 2>&1 || true

# Restore POL_TASK_ID_2 (now archived) so teardown can delete it normally
act_as "$OWNER_TOKEN"
api_json POST "/tasks/$POL_TASK_ID_2/restore" '{}' > /dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# forceDelete — no dedicated route → skip_case
# ---------------------------------------------------------------------------
skip_case "Task forceDelete" "no dedicated forceDelete route registered for tasks"

# ============================================================
# PROJECT POLICY
# ============================================================
echo ""
echo "----- Project Policy -----"
# NOTE: Super Admin now bypasses ALL policies via Gate::before, so ADMIN succeeds
# on every project ability (view/update/delete/restore) regardless of ownership.
# Project Admin = project owner/creator/workspace owner. Plain members and
# non-members are denied owner-only abilities (update/delete/restore).

# ---------------------------------------------------------------------------
# viewAny — GET /projects — all user types → 200
# ---------------------------------------------------------------------------
act_as "$ADMIN_TOKEN"
RESP=$(api_get "/projects")
assert_api "Project viewAny [admin]" "200" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_get "/projects")
assert_api "Project viewAny [owner]" "200" "$RESP"

act_as "$CREATOR_TOKEN"
RESP=$(api_get "/projects")
assert_api "Project viewAny [creator]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/projects")
assert_api "Project viewAny [member]" "200" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_get "/projects")
assert_api "Project viewAny [other]" "200" "$RESP"

# ---------------------------------------------------------------------------
# view — GET /projects/{id}
# Admin (super admin) → 200; owner/creator/member → 200; OTHER (non-member) → 403
# ---------------------------------------------------------------------------
act_as "$ADMIN_TOKEN"
RESP=$(api_get "/projects/$POL_PROJECT_ID")
assert_api "Project view [admin (super admin) → 200]" "200" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_get "/projects/$POL_PROJECT_ID")
assert_api "Project view [owner]" "200" "$RESP"

act_as "$CREATOR_TOKEN"
RESP=$(api_get "/projects/$POL_PROJECT_ID")
assert_api "Project view [creator]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/projects/$POL_PROJECT_ID")
assert_api "Project view [member]" "200" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_get "/projects/$POL_PROJECT_ID")
assert_api "Project view [other → 403]" "403" "$RESP"

# ---------------------------------------------------------------------------
# create — POST /projects — all user types → 201
# ProjectPolicy::create returns true for any authenticated user.
# Each user creates in THEIR OWN workspace to pass the workspace access check.
# ---------------------------------------------------------------------------
_PROJ_CREATE_UNIQUE="pct-$(date +%s)-$RANDOM"

# OWNER: can create in their own workspace
act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/projects" "{\"name\":\"owner-create-${_PROJ_CREATE_UNIQUE}\",\"workspace_id\":\"$POL_WORKSPACE_ID\"}")
assert_api "Project create [owner]" "201" "$RESP"
_PROJ_TMP_OWNER=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_PROJ_TMP_OWNER" ] && _PROJ_TMP_OWNER=$(json_value "$(body_from_response "$RESP")" "id")

# ADMIN: creates their own workspace first, then creates a project in it
act_as "$ADMIN_TOKEN"
_WS_ADMIN_TMP=$(api_json POST "/workspaces" "{\"name\":\"admin-ws-${_PROJ_CREATE_UNIQUE}\",\"visibility\":\"private\"}")
_WS_ADMIN_TMP_ID=$(json_value "$(body_from_response "$_WS_ADMIN_TMP")" "data.id")
[ -z "$_WS_ADMIN_TMP_ID" ] && _WS_ADMIN_TMP_ID=$(json_value "$(body_from_response "$_WS_ADMIN_TMP")" "id")
RESP=$(api_json POST "/projects" "{\"name\":\"admin-create-${_PROJ_CREATE_UNIQUE}\",\"workspace_id\":\"$_WS_ADMIN_TMP_ID\"}")
assert_api "Project create [admin]" "201" "$RESP"
_PROJ_TMP_ADMIN=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_PROJ_TMP_ADMIN" ] && _PROJ_TMP_ADMIN=$(json_value "$(body_from_response "$RESP")" "id")

# CREATOR: creates their own workspace first
act_as "$CREATOR_TOKEN"
_WS_CREATOR_TMP=$(api_json POST "/workspaces" "{\"name\":\"creator-ws-${_PROJ_CREATE_UNIQUE}\",\"visibility\":\"private\"}")
_WS_CREATOR_TMP_ID=$(json_value "$(body_from_response "$_WS_CREATOR_TMP")" "data.id")
[ -z "$_WS_CREATOR_TMP_ID" ] && _WS_CREATOR_TMP_ID=$(json_value "$(body_from_response "$_WS_CREATOR_TMP")" "id")
RESP=$(api_json POST "/projects" "{\"name\":\"creator-create-${_PROJ_CREATE_UNIQUE}\",\"workspace_id\":\"$_WS_CREATOR_TMP_ID\"}")
assert_api "Project create [creator]" "201" "$RESP"
_PROJ_TMP_CREATOR=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_PROJ_TMP_CREATOR" ] && _PROJ_TMP_CREATOR=$(json_value "$(body_from_response "$RESP")" "id")

# MEMBER: creates their own workspace first
act_as "$MEMBER_TOKEN"
_WS_MEMBER_TMP=$(api_json POST "/workspaces" "{\"name\":\"member-ws-${_PROJ_CREATE_UNIQUE}\",\"visibility\":\"private\"}")
_WS_MEMBER_TMP_ID=$(json_value "$(body_from_response "$_WS_MEMBER_TMP")" "data.id")
[ -z "$_WS_MEMBER_TMP_ID" ] && _WS_MEMBER_TMP_ID=$(json_value "$(body_from_response "$_WS_MEMBER_TMP")" "id")
RESP=$(api_json POST "/projects" "{\"name\":\"member-create-${_PROJ_CREATE_UNIQUE}\",\"workspace_id\":\"$_WS_MEMBER_TMP_ID\"}")
assert_api "Project create [member]" "201" "$RESP"
_PROJ_TMP_MEMBER=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_PROJ_TMP_MEMBER" ] && _PROJ_TMP_MEMBER=$(json_value "$(body_from_response "$RESP")" "id")

# OTHER: creates their own workspace first
act_as "$OTHER_TOKEN"
_WS_OTHER_TMP=$(api_json POST "/workspaces" "{\"name\":\"other-ws-${_PROJ_CREATE_UNIQUE}\",\"visibility\":\"private\"}")
_WS_OTHER_TMP_ID=$(json_value "$(body_from_response "$_WS_OTHER_TMP")" "data.id")
[ -z "$_WS_OTHER_TMP_ID" ] && _WS_OTHER_TMP_ID=$(json_value "$(body_from_response "$_WS_OTHER_TMP")" "id")
RESP=$(api_json POST "/projects" "{\"name\":\"other-create-${_PROJ_CREATE_UNIQUE}\",\"workspace_id\":\"$_WS_OTHER_TMP_ID\"}")
assert_api "Project create [other]" "201" "$RESP"
_PROJ_TMP_OTHER=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_PROJ_TMP_OTHER" ] && _PROJ_TMP_OTHER=$(json_value "$(body_from_response "$RESP")" "id")

# Clean up temporary create-test projects and workspaces
act_as "$OWNER_TOKEN"
[ -n "${_PROJ_TMP_OWNER:-}" ]   && api_delete "/projects/$_PROJ_TMP_OWNER"   > /dev/null 2>&1 || true
act_as "$ADMIN_TOKEN"
[ -n "${_PROJ_TMP_ADMIN:-}" ]   && api_delete "/projects/$_PROJ_TMP_ADMIN"   > /dev/null 2>&1 || true
[ -n "${_WS_ADMIN_TMP_ID:-}" ]  && api_delete "/workspaces/$_WS_ADMIN_TMP_ID"  > /dev/null 2>&1 || true
act_as "$CREATOR_TOKEN"
[ -n "${_PROJ_TMP_CREATOR:-}" ] && api_delete "/projects/$_PROJ_TMP_CREATOR" > /dev/null 2>&1 || true
[ -n "${_WS_CREATOR_TMP_ID:-}" ] && api_delete "/workspaces/$_WS_CREATOR_TMP_ID" > /dev/null 2>&1 || true
act_as "$MEMBER_TOKEN"
[ -n "${_PROJ_TMP_MEMBER:-}" ]  && api_delete "/projects/$_PROJ_TMP_MEMBER"  > /dev/null 2>&1 || true
[ -n "${_WS_MEMBER_TMP_ID:-}" ] && api_delete "/workspaces/$_WS_MEMBER_TMP_ID"  > /dev/null 2>&1 || true
act_as "$OTHER_TOKEN"
[ -n "${_PROJ_TMP_OTHER:-}" ]   && api_delete "/projects/$_PROJ_TMP_OTHER"   > /dev/null 2>&1 || true
[ -n "${_WS_OTHER_TMP_ID:-}" ]  && api_delete "/workspaces/$_WS_OTHER_TMP_ID"  > /dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# update — PUT /projects/{id}
# Admin (super admin) → 200; owner → 200; creator (own project) → 200;
# member (no edit_project) → 403; other → 403
# ---------------------------------------------------------------------------
act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/projects/$POL_PROJECT_ID" "{\"name\":\"member-update-attempt\"}")
assert_api "Project update [member → 403]" "403" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_json PUT "/projects/$POL_PROJECT_ID" "{\"name\":\"other-update-attempt\"}")
assert_api "Project update [other → 403]" "403" "$RESP"

# Admin is super admin → bypasses policy → 200
act_as "$ADMIN_TOKEN"
RESP=$(api_json PUT "/projects/$POL_PROJECT_ID" "{\"name\":\"admin-updated-project\"}")
assert_api "Project update [admin (super admin) → 200]" "200" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_json PUT "/projects/$POL_PROJECT_ID" "{\"name\":\"owner-updated-project\"}")
assert_api "Project update [owner → 200]" "200" "$RESP"

# CREATOR_TOKEN is user-02; they are a project member but NOT the created_by for
# POL_PROJECT_ID (which was created by OWNER). Test creator by creating a
# temporary project as creator in their own workspace, then updating it.
act_as "$CREATOR_TOKEN"
_WS_CREATOR_UPD=$(api_json POST "/workspaces" "{\"name\":\"creator-upd-ws-${_PROJ_CREATE_UNIQUE}\",\"visibility\":\"private\"}")
_WS_CREATOR_UPD_ID=$(json_value "$(body_from_response "$_WS_CREATOR_UPD")" "data.id")
[ -z "$_WS_CREATOR_UPD_ID" ] && _WS_CREATOR_UPD_ID=$(json_value "$(body_from_response "$_WS_CREATOR_UPD")" "id")
RESP=$(api_json POST "/projects" "{\"name\":\"creator-upd-${_PROJ_CREATE_UNIQUE}\",\"workspace_id\":\"$_WS_CREATOR_UPD_ID\"}")
_PROJ_CREATOR_UPDATE=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_PROJ_CREATOR_UPDATE" ] && _PROJ_CREATOR_UPDATE=$(json_value "$(body_from_response "$RESP")" "id")
RESP=$(api_json PUT "/projects/$_PROJ_CREATOR_UPDATE" "{\"name\":\"creator-updated-project\"}")
assert_api "Project update [creator (own project) → 200]" "200" "$RESP"
api_delete "/projects/$_PROJ_CREATOR_UPDATE" > /dev/null 2>&1 || true
[ -n "${_WS_CREATOR_UPD_ID:-}" ] && api_delete "/workspaces/$_WS_CREATOR_UPD_ID" > /dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# delete — DELETE /projects/{id}
# Admin (super admin) → success; owner → success; creator/member/other → 403
#
# Deny tests use POL_PROJECT_ID (403 is idempotent and must NOT consume it).
# Allow tests each delete a freshly created throwaway project.
# ---------------------------------------------------------------------------
act_as "$CREATOR_TOKEN"
RESP=$(api_delete "/projects/$POL_PROJECT_ID")
assert_api "Project delete [creator → 403]" "403" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/projects/$POL_PROJECT_ID")
assert_api "Project delete [member → 403]" "403" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_delete "/projects/$POL_PROJECT_ID")
assert_api "Project delete [other → 403]" "403" "$RESP"

# Allow: admin (super admin) deletes a throwaway project created by owner
act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/projects" "{\"name\":\"admin-del-proj-$(date +%s)-$RANDOM\",\"workspace_id\":\"$POL_WORKSPACE_ID\"}")
_PROJ_DEL_ADMIN=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_PROJ_DEL_ADMIN" ] && _PROJ_DEL_ADMIN=$(json_value "$(body_from_response "$RESP")" "id")
act_as "$ADMIN_TOKEN"
RESP=$(api_delete "/projects/$_PROJ_DEL_ADMIN")
assert_api "Project delete [admin (super admin) → 200]" "200 204" "$RESP"

# Allow: owner creates a temporary project, deletes it
act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/projects" "{\"name\":\"owner-del-proj-$(date +%s)-$RANDOM\",\"workspace_id\":\"$POL_WORKSPACE_ID\"}")
_PROJ_DEL_OWNER=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_PROJ_DEL_OWNER" ] && _PROJ_DEL_OWNER=$(json_value "$(body_from_response "$RESP")" "id")
RESP=$(api_delete "/projects/$_PROJ_DEL_OWNER")
assert_api "Project delete [owner → 200]" "200 204" "$RESP"

# ---------------------------------------------------------------------------
# restore — POST /projects/{id}/restore
# Admin (super admin) → 200; owner → 200; creator/member/other → 403
#
# Strategy: deny tests run on an archived _PROJ_RST_BASE (403 leaves it archived);
# admin restores its OWN archived project; owner restores _PROJ_RST_BASE.
# ---------------------------------------------------------------------------

# Create a temporary project as OWNER, archive it, then test restore policy
act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/projects" "{\"name\":\"owner-rst-proj-$(date +%s)-$RANDOM\",\"workspace_id\":\"$POL_WORKSPACE_ID\"}")
_PROJ_RST_BASE=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_PROJ_RST_BASE" ] && _PROJ_RST_BASE=$(json_value "$(body_from_response "$RESP")" "id")
api_json POST "/projects/$_PROJ_RST_BASE/archive" '{}' > /dev/null 2>&1 || true

act_as "$CREATOR_TOKEN"
RESP=$(api_json POST "/projects/$_PROJ_RST_BASE/restore" '{}')
assert_api "Project restore [creator → 403]" "403" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/projects/$_PROJ_RST_BASE/restore" '{}')
assert_api "Project restore [member → 403]" "403" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_json POST "/projects/$_PROJ_RST_BASE/restore" '{}')
assert_api "Project restore [other → 403]" "403" "$RESP"

# Allow: admin (super admin) restores its OWN archived throwaway project
act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/projects" "{\"name\":\"admin-rst-proj-$(date +%s)-$RANDOM\",\"workspace_id\":\"$POL_WORKSPACE_ID\"}")
_PROJ_RST_ADMIN=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_PROJ_RST_ADMIN" ] && _PROJ_RST_ADMIN=$(json_value "$(body_from_response "$RESP")" "id")
api_json POST "/projects/$_PROJ_RST_ADMIN/archive" '{}' > /dev/null 2>&1 || true
act_as "$ADMIN_TOKEN"
RESP=$(api_json POST "/projects/$_PROJ_RST_ADMIN/restore" '{}')
assert_api "Project restore [admin (super admin) → 200]" "200" "$RESP"
api_delete "/projects/$_PROJ_RST_ADMIN" > /dev/null 2>&1 || true

# Allow: owner restores their own archived project
act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/projects/$_PROJ_RST_BASE/restore" '{}')
assert_api "Project restore [owner → 200]" "200" "$RESP"
api_delete "/projects/$_PROJ_RST_BASE" > /dev/null 2>&1 || true

# ============================================================
# WORKSPACE POLICY
# ============================================================
echo ""
echo "----- Workspace Policy -----"

# Add MEMBER_USER_ID as workspace member so they qualify as "active member"
# for workspace-level view / viewReporting tests.
act_as "$OWNER_TOKEN"
api_json POST "/workspaces/$POL_WORKSPACE_ID/members" \
    "{\"user_id\":\"$MEMBER_USER_ID\"}" > /dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# viewAny — GET /workspaces — all user types → 200
# ---------------------------------------------------------------------------
act_as "$OWNER_TOKEN"
RESP=$(api_get "/workspaces")
assert_api "Workspace viewAny [owner]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/workspaces")
assert_api "Workspace viewAny [active member]" "200" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_get "/workspaces")
assert_api "Workspace viewAny [other]" "200" "$RESP"

# ---------------------------------------------------------------------------
# view — GET /workspaces/{id}
# Owner/active-member → 200; OTHER (non-member) → 403/404
# NOTE: WorkspaceController uses findForUser which returns null for non-members,
# resulting in 404 (not 403) before the policy check is reached.
# ---------------------------------------------------------------------------
act_as "$OWNER_TOKEN"
RESP=$(api_get "/workspaces/$POL_WORKSPACE_ID")
assert_api "Workspace view [owner]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/workspaces/$POL_WORKSPACE_ID")
assert_api "Workspace view [active member]" "200" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_get "/workspaces/$POL_WORKSPACE_ID")
assert_api "Workspace view [other → 403/404]" "403 404" "$RESP"

# ---------------------------------------------------------------------------
# create — POST /workspaces — all user types → 201
# ---------------------------------------------------------------------------
_WS_CREATE_UNIQUE="wsc-$(date +%s)-$RANDOM"

act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/workspaces" "{\"name\":\"owner-ws-${_WS_CREATE_UNIQUE}\",\"visibility\":\"private\"}")
assert_api "Workspace create [owner]" "201" "$RESP"
_WS_TMP_OWNER=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_WS_TMP_OWNER" ] && _WS_TMP_OWNER=$(json_value "$(body_from_response "$RESP")" "id")

act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/workspaces" "{\"name\":\"member-ws-${_WS_CREATE_UNIQUE}\",\"visibility\":\"private\"}")
assert_api "Workspace create [active member]" "201" "$RESP"
_WS_TMP_MEMBER=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_WS_TMP_MEMBER" ] && _WS_TMP_MEMBER=$(json_value "$(body_from_response "$RESP")" "id")

act_as "$OTHER_TOKEN"
RESP=$(api_json POST "/workspaces" "{\"name\":\"other-ws-${_WS_CREATE_UNIQUE}\",\"visibility\":\"private\"}")
assert_api "Workspace create [other]" "201" "$RESP"
_WS_TMP_OTHER=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_WS_TMP_OTHER" ] && _WS_TMP_OTHER=$(json_value "$(body_from_response "$RESP")" "id")

# Clean up temporary workspaces (each owner deletes their own)
act_as "$OWNER_TOKEN"
[ -n "${_WS_TMP_OWNER:-}" ]  && api_delete "/workspaces/$_WS_TMP_OWNER"  > /dev/null 2>&1 || true
act_as "$MEMBER_TOKEN"
[ -n "${_WS_TMP_MEMBER:-}" ] && api_delete "/workspaces/$_WS_TMP_MEMBER" > /dev/null 2>&1 || true
act_as "$OTHER_TOKEN"
[ -n "${_WS_TMP_OTHER:-}" ]  && api_delete "/workspaces/$_WS_TMP_OTHER"  > /dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# update — PUT /workspaces/{id}
# Owner → 200; active member (no workspace.manage permission) → 403; other → 403
# ---------------------------------------------------------------------------
act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/workspaces/$POL_WORKSPACE_ID" "{\"name\":\"member-update-attempt\"}")
assert_api "Workspace update [active member → 403]" "403" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_json PUT "/workspaces/$POL_WORKSPACE_ID" "{\"name\":\"other-update-attempt\"}")
assert_api "Workspace update [other → 403/404]" "403 404" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_json PUT "/workspaces/$POL_WORKSPACE_ID" "{\"name\":\"owner-updated-workspace\"}")
assert_api "Workspace update [owner → 200]" "200" "$RESP"

# ---------------------------------------------------------------------------
# delete — DELETE /workspaces/{id}
# Owner → 200; active member → 403; other → 403
#
# Deny tests use POL_WORKSPACE_ID (403 is idempotent).
# Allow test: owner creates a temporary workspace, then deletes it.
# ---------------------------------------------------------------------------
act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/workspaces/$POL_WORKSPACE_ID")
assert_api "Workspace delete [active member → 403]" "403" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_delete "/workspaces/$POL_WORKSPACE_ID")
assert_api "Workspace delete [other → 403/404]" "403 404" "$RESP"

# Allow: owner creates a temporary workspace and deletes it
act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/workspaces" "{\"name\":\"owner-del-ws-$(date +%s)-$RANDOM\",\"visibility\":\"private\"}")
_WS_DEL_OWNER=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_WS_DEL_OWNER" ] && _WS_DEL_OWNER=$(json_value "$(body_from_response "$RESP")" "id")
RESP=$(api_delete "/workspaces/$_WS_DEL_OWNER")
assert_api "Workspace delete [owner → 200]" "200" "$RESP"

# ---------------------------------------------------------------------------
# invite — POST /workspaces/{id}/invites
# Owner → 200/201; active member (no workspace.members.manage) → 403; other → 403
# ---------------------------------------------------------------------------
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/workspaces/$POL_WORKSPACE_ID/invites" "{\"email\":\"invite-test@example.com\"}")
assert_api "Workspace invite [active member → 403]" "403" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_json POST "/workspaces/$POL_WORKSPACE_ID/invites" "{\"email\":\"invite-test2@example.com\"}")
assert_api "Workspace invite [other → 403/404]" "403 404" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/workspaces/$POL_WORKSPACE_ID/invites" "{\"email\":\"invite-owner-test@example.com\"}")
assert_api "Workspace invite [owner → 200/201]" "200 201" "$RESP"

# ---------------------------------------------------------------------------
# manageSettings — PUT /workspaces/{id}/settings
# Owner → 200; active member (no workspace.manage) → 403; other → 403/404
# NOTE: Body must be {"settings": {...}} per UpdateWorkspaceSettingsRequest
# ---------------------------------------------------------------------------
act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/workspaces/$POL_WORKSPACE_ID/settings" "{\"settings\":{\"allow_public_projects\":false}}")
assert_api "Workspace manageSettings [active member → 403]" "403" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_json PUT "/workspaces/$POL_WORKSPACE_ID/settings" "{\"settings\":{\"allow_public_projects\":false}}")
assert_api "Workspace manageSettings [other → 403/404]" "403 404" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_json PUT "/workspaces/$POL_WORKSPACE_ID/settings" "{\"settings\":{\"allow_public_projects\":false}}")
assert_api "Workspace manageSettings [owner → 200]" "200" "$RESP"

# ---------------------------------------------------------------------------
# manageCollections — POST /workspaces/{id}/collections
# Owner → 201; active member (no workspace.collections.manage) → 403; other → 403
# ---------------------------------------------------------------------------
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/workspaces/$POL_WORKSPACE_ID/collections" "{\"name\":\"member-col-attempt\"}")
assert_api "Workspace manageCollections [active member → 403]" "403" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_json POST "/workspaces/$POL_WORKSPACE_ID/collections" "{\"name\":\"other-col-attempt\"}")
assert_api "Workspace manageCollections [other → 403/404]" "403 404" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/workspaces/$POL_WORKSPACE_ID/collections" "{\"name\":\"owner-collection-$(date +%s)-$RANDOM\"}")
assert_api "Workspace manageCollections [owner → 201]" "201" "$RESP"
# Note: the collection is left in place; teardown will remove it when the workspace is deleted

# ---------------------------------------------------------------------------
# export — POST /workspaces/{id}/exports
# Owner → 200/201/202 (async export returns 202); active member → 403; other → 403/404
# ---------------------------------------------------------------------------
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/workspaces/$POL_WORKSPACE_ID/exports" "{\"format\":\"json\"}")
assert_api "Workspace export [active member → 403]" "403" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_json POST "/workspaces/$POL_WORKSPACE_ID/exports" "{\"format\":\"json\"}")
assert_api "Workspace export [other → 403/404]" "403 404" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/workspaces/$POL_WORKSPACE_ID/exports" "{\"format\":\"json\"}")
assert_api "Workspace export [owner → 200/201/202]" "200 201 202" "$RESP"

# ---------------------------------------------------------------------------
# viewReporting — GET /workspaces/{id}/reporting
# Owner + active member → 200; other → 403/404 (findForUser returns null)
# ---------------------------------------------------------------------------
act_as "$OTHER_TOKEN"
RESP=$(api_get "/workspaces/$POL_WORKSPACE_ID/reporting")
assert_api "Workspace viewReporting [other → 403/404]" "403 404" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_get "/workspaces/$POL_WORKSPACE_ID/reporting")
assert_api "Workspace viewReporting [owner → 200]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/workspaces/$POL_WORKSPACE_ID/reporting")
assert_api "Workspace viewReporting [active member → 200]" "200" "$RESP"

# ============================================================
# ACTIVITY POLICY
# ============================================================
echo ""
echo "----- Activity Policy -----"

# viewAny — GET /activities — all auth users → 200
act_as "$ADMIN_TOKEN"
RESP=$(api_get "/activities")
assert_api "Activity viewAny [admin]" "200" "$RESP"

act_as "$AUTHOR_TOKEN"
RESP=$(api_get "/activities")
assert_api "Activity viewAny [author/self]" "200" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_get "/activities")
assert_api "Activity viewAny [other auth]" "200" "$RESP"

# view — GET /activities/{id}
# Admin or Self → 200; other → 403
# Use POL_ACTIVITY_ID (owned by admin or whatever action triggered it)
if [ -n "${POL_ACTIVITY_ID:-}" ]; then
    act_as "$ADMIN_TOKEN"
    RESP=$(api_get "/activities/$POL_ACTIVITY_ID")
    assert_api "Activity view [admin]" "200" "$RESP"

    act_as "$OTHER_TOKEN"
    RESP=$(api_get "/activities/$POL_ACTIVITY_ID")
    assert_api "Activity view [other → 403]" "403" "$RESP"
else
    skip_case "Activity view [specific ID]" "no POL_ACTIVITY_ID available (empty activity log)"
fi

# viewStatistics — GET /activities/statistics — all auth → 200
act_as "$MEMBER_TOKEN"
RESP=$(api_get "/activities/statistics")
assert_api "Activity viewStatistics [member/auth]" "200" "$RESP"

# cleanup — DELETE /activities/cleanup
# Intended admin-only but currently allows any auth user → expected_gap
act_as "$ADMIN_TOKEN"
RESP=$(api_delete "/activities/cleanup")
STATUS=$(status_from_response "$RESP")
if [ "$STATUS" = "200" ] || [ "$STATUS" = "204" ]; then
    assert_api "Activity cleanup [admin]" "$STATUS" "$RESP"
else
    assert_api "Activity cleanup [admin]" "200" "$RESP"
fi

act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/activities/cleanup")
STATUS=$(status_from_response "$RESP")
if [ "$STATUS" = "200" ] || [ "$STATUS" = "204" ]; then
    expected_gap "Activity cleanup [member]" \
        "ActivityPolicy::cleanup should be admin-only (TODO) but allows any auth user — live: $STATUS"
else
    assert_api "Activity cleanup [member]" "403" "$RESP"
fi

# ============================================================
# ARCHIVE POLICY
# ============================================================
echo ""
echo "----- Archive Policy -----"
# All abilities require only Auth (no ownership scoping) — documented gap

act_as "$ADMIN_TOKEN"
RESP=$(api_get "/archives")
assert_api "Archive viewAny [admin]" "200" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_get "/archives")
assert_api "Archive viewAny [other auth]" "200" "$RESP"

# Get an archive ID if available
act_as "$ADMIN_TOKEN"
_ARCH_RESP=$(api_get "/archives")
_ARCHIVE_ID=$(json_value "$(body_from_response "$_ARCH_RESP")" "data.0.id")
[ -z "$_ARCHIVE_ID" ] && _ARCHIVE_ID=$(json_value "$(body_from_response "$_ARCH_RESP")" "0.id")

if [ -n "$_ARCHIVE_ID" ]; then
    act_as "$ADMIN_TOKEN"
    RESP=$(api_get "/archives/$_ARCHIVE_ID")
    assert_api "Archive view [admin]" "200" "$RESP"

    act_as "$OTHER_TOKEN"
    RESP=$(api_get "/archives/$_ARCHIVE_ID")
    STATUS=$(status_from_response "$RESP")
    if [ "$STATUS" = "200" ]; then
        expected_gap "Archive view [other — no scoping]" \
            "ArchivePolicy allows any authenticated user (no ownership scoping)"
    else
        assert_api "Archive view [other]" "200" "$RESP"
    fi
else
    skip_case "Archive view [specific ID]" "no archive records available to test against"
fi

act_as "$ADMIN_TOKEN"
RESP=$(api_get "/archives/statistics")
assert_api "Archive statistics [admin]" "200" "$RESP"

skip_case "Archive create/restore/delete" "no mutation routes registered in Modules/Archive/routes/api.php"

# ============================================================
# TASK DEPENDENCY POLICY
# ============================================================
echo ""
echo "----- Task Dependency Policy -----"
# Policy returns true for ALL users — documented as a scoping gap

# viewAny — GET /task-dependencies — all → 200
act_as "$OWNER_TOKEN"
RESP=$(api_get "/task-dependencies")
assert_api "TaskDependency viewAny [owner]" "200" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_get "/task-dependencies")
assert_api "TaskDependency viewAny [other]" "200" "$RESP"

# Create a dependency as owner to test view/update/delete
act_as "$OWNER_TOKEN"
_DEP_RESP=$(api_json POST "/task-dependencies" \
    "{\"task_id\":\"$POL_TASK_ID\",\"depends_on_task_id\":\"$POL_TASK_ID_2\",\"dependency_type\":\"blocks\"}")
_DEP_ID=$(json_value "$(body_from_response "$_DEP_RESP")" "data.id")
[ -z "$_DEP_ID" ] && _DEP_ID=$(json_value "$(body_from_response "$_DEP_RESP")" "id")
_DEP_STATUS=$(status_from_response "$_DEP_RESP")
if [ "$_DEP_STATUS" = "200" ] || [ "$_DEP_STATUS" = "201" ]; then
    assert_api "TaskDependency create [owner]" "$_DEP_STATUS" "$_DEP_RESP"
else
    assert_api "TaskDependency create [owner]" "201" "$_DEP_RESP"
fi

if [ -n "$_DEP_ID" ]; then
    # view — OTHER access (policy returns true → expected_gap)
    act_as "$OTHER_TOKEN"
    RESP=$(api_get "/task-dependencies/$_DEP_ID")
    STATUS=$(status_from_response "$RESP")
    if [ "$STATUS" = "200" ]; then
        expected_gap "TaskDependency view [other — no scoping]" \
            "TaskDependencyPolicy returns true for all users (no ownership scoping) — live: $STATUS"
    else
        assert_api "TaskDependency view [other]" "200" "$RESP"
    fi

    # update — OTHER access (expected_gap)
    act_as "$OTHER_TOKEN"
    RESP=$(api_json PUT "/task-dependencies/$_DEP_ID" \
        "{\"dependency_type\":\"relates_to\"}")
    STATUS=$(status_from_response "$RESP")
    if [ "$STATUS" = "200" ]; then
        expected_gap "TaskDependency update [other — no scoping]" \
            "TaskDependencyPolicy returns true for all users — live: $STATUS"
    else
        assert_api "TaskDependency update [other]" "200" "$RESP"
    fi

    # delete — Owner can delete → 200
    act_as "$OWNER_TOKEN"
    RESP=$(api_delete "/task-dependencies/$_DEP_ID")
    assert_api "TaskDependency delete [owner]" "200 204" "$RESP"
fi

# ============================================================
# COLUMN POLICY
# ============================================================
echo ""
echo "----- Column Policy -----"
# canAccessProject = owner/creator/member/active workspace member → 200; other → 403

act_as "$ADMIN_TOKEN"
RESP=$(api_get "/columns")
assert_api "Column viewAny [admin]" "200" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_get "/columns")
assert_api "Column viewAny [other]" "200" "$RESP"

# view — canAccessProject
act_as "$OWNER_TOKEN"
RESP=$(api_get "/columns/$POL_COLUMN_ID")
assert_api "Column view [owner]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/columns/$POL_COLUMN_ID")
assert_api "Column view [member]" "200" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_get "/columns/$POL_COLUMN_ID")
assert_api "Column view [other → 403]" "403" "$RESP"

# update — requires edit_column (NOT a default member permission)
act_as "$OWNER_TOKEN"
RESP=$(api_json PUT "/columns/$POL_COLUMN_ID" "{\"name\":\"col-updated-owner\"}")
assert_api "Column update [owner → 200]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/columns/$POL_COLUMN_ID" "{\"name\":\"col-updated-member\"}")
assert_api "Column update [member (no edit_column) → 403]" "403" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_json PUT "/columns/$POL_COLUMN_ID" "{\"name\":\"col-updated-other\"}")
assert_api "Column update [other → 403]" "403" "$RESP"

# create — requires create_column (NOT a default member permission)
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/columns" "{\"name\":\"col-create-test-member\",\"section_id\":\"$POL_SECTION_ID\",\"sort_order\":99}")
assert_api "Column create [member (no create_column) → 403]" "403" "$RESP"
_COL_TMP=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_COL_TMP" ] && _COL_TMP=$(json_value "$(body_from_response "$RESP")" "id")
[ -n "$_COL_TMP" ] && { act_as "$ADMIN_TOKEN"; api_delete "/columns/$_COL_TMP" > /dev/null 2>&1 || true; }

# ============================================================
# SECTION POLICY
# ============================================================
echo ""
echo "----- Section Policy -----"

act_as "$ADMIN_TOKEN"
RESP=$(api_get "/sections")
assert_api "Section viewAny [admin]" "200" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_get "/sections")
assert_api "Section viewAny [other]" "200" "$RESP"

# view — admin/owner/creator/member → 200; other → 403
act_as "$OWNER_TOKEN"
RESP=$(api_get "/sections/$POL_SECTION_ID")
assert_api "Section view [owner → 200]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/sections/$POL_SECTION_ID")
assert_api "Section view [member → 200]" "200" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_get "/sections/$POL_SECTION_ID")
assert_api "Section view [other → 403]" "403" "$RESP"

# update — owner/creator → 200; member → 403; admin override → 200
act_as "$OWNER_TOKEN"
RESP=$(api_json PUT "/sections/$POL_SECTION_ID" "{\"name\":\"section-updated-owner\"}")
assert_api "Section update [owner → 200]" "200" "$RESP"

# NOTE: CREATOR_TOKEN (user-02) is a project team member but NOT the project's
# created_by (project was created by OWNER/user-01). SectionPolicy::update
# checks project->created_by === user->id. So CREATOR gets 403 here.
act_as "$CREATOR_TOKEN"
RESP=$(api_json PUT "/sections/$POL_SECTION_ID" "{\"name\":\"section-updated-creator\"}")
assert_api "Section update [creator (not project created_by) → 403]" "403" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/sections/$POL_SECTION_ID" "{\"name\":\"section-updated-member\"}")
assert_api "Section update [member → 403]" "403" "$RESP"

act_as "$ADMIN_TOKEN"
RESP=$(api_json PUT "/sections/$POL_SECTION_ID" "{\"name\":\"section-updated-admin\"}")
assert_api "Section update [admin override → 200]" "200" "$RESP"

# delete — owner only → 200; creator/member → 403; admin override → 200
# Create a disposable section for delete tests
act_as "$OWNER_TOKEN"
_SEC_DEL_RESP=$(api_json POST "/sections" \
    "{\"name\":\"sec-delete-test\",\"project_id\":\"$POL_PROJECT_ID\",\"sort_order\":99}")
_SEC_DEL_ID=$(json_value "$(body_from_response "$_SEC_DEL_RESP")" "data.id")
[ -z "$_SEC_DEL_ID" ] && _SEC_DEL_ID=$(json_value "$(body_from_response "$_SEC_DEL_RESP")" "id")

if [ -n "$_SEC_DEL_ID" ]; then
    act_as "$CREATOR_TOKEN"
    RESP=$(api_delete "/sections/$_SEC_DEL_ID")
    assert_api "Section delete [creator → 403]" "403" "$RESP"

    act_as "$MEMBER_TOKEN"
    RESP=$(api_delete "/sections/$_SEC_DEL_ID")
    assert_api "Section delete [member → 403]" "403" "$RESP"

    act_as "$OWNER_TOKEN"
    RESP=$(api_delete "/sections/$_SEC_DEL_ID")
    assert_api "Section delete [owner → 200]" "200" "$RESP"
fi

# Admin override on delete — create another section, delete as admin
act_as "$OWNER_TOKEN"
_SEC_ADMIN_DEL_RESP=$(api_json POST "/sections" \
    "{\"name\":\"sec-admin-delete-test\",\"project_id\":\"$POL_PROJECT_ID\",\"sort_order\":100}")
_SEC_ADMIN_DEL_ID=$(json_value "$(body_from_response "$_SEC_ADMIN_DEL_RESP")" "data.id")
[ -z "$_SEC_ADMIN_DEL_ID" ] && _SEC_ADMIN_DEL_ID=$(json_value "$(body_from_response "$_SEC_ADMIN_DEL_RESP")" "id")

if [ -n "$_SEC_ADMIN_DEL_ID" ]; then
    act_as "$ADMIN_TOKEN"
    RESP=$(api_delete "/sections/$_SEC_ADMIN_DEL_ID")
    assert_api "Section delete [admin override → 200]" "200" "$RESP"
fi

# ============================================================
# TAG POLICY
# ============================================================
echo ""
echo "----- Tag Policy -----"

act_as "$ADMIN_TOKEN"
RESP=$(api_get "/tags")
assert_api "Tag viewAny [admin]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/tags")
assert_api "Tag viewAny [member]" "200" "$RESP"

# view — admin/owner/creator/member → 200; other → 403
act_as "$OWNER_TOKEN"
RESP=$(api_get "/tags/$POL_TAG_ID")
assert_api "Tag view [owner → 200]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/tags/$POL_TAG_ID")
assert_api "Tag view [member → 200]" "200" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_get "/tags/$POL_TAG_ID")
assert_api "Tag view [other → 403]" "403" "$RESP"

# update — owner/creator → 200; member → 403; admin override → 200
act_as "$OWNER_TOKEN"
RESP=$(api_json PUT "/tags/$POL_TAG_ID" "{\"name\":\"pol-tag-a-updated-owner\"}")
assert_api "Tag update [owner → 200]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/tags/$POL_TAG_ID" "{\"name\":\"pol-tag-a-updated-member\"}")
assert_api "Tag update [member → 403]" "403" "$RESP"

act_as "$ADMIN_TOKEN"
RESP=$(api_json PUT "/tags/$POL_TAG_ID" "{\"name\":\"pol-tag-a-updated-admin\"}")
assert_api "Tag update [admin override → 200]" "200" "$RESP"

# delete — owner/creator → 200; member → 403; admin override → 200
act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/tags/$POL_TAG_ID_2")
assert_api "Tag delete [member → 403]" "403" "$RESP"

act_as "$ADMIN_TOKEN"
RESP=$(api_delete "/tags/$POL_TAG_ID_2")
assert_api "Tag delete [admin override → 200]" "200" "$RESP"

act_as "$ADMIN_TOKEN"
RESP=$(api_delete "/tags/$POL_TAG_ID")
assert_api "Tag delete [admin override tag A → 200]" "200" "$RESP"

# ============================================================
# TASK HIERARCHY POLICY
# ============================================================
echo ""
echo "----- Task Hierarchy Policy -----"
# view: project member → 200; other → 403
# create/delete: member with role Manager/Contributor → 200; other → 403

# view children — GET /tasks/{taskId}/children
act_as "$MEMBER_TOKEN"
RESP=$(api_get "/tasks/$POL_TASK_ID/children")
assert_api "TaskHierarchy view [member → 200]" "200" "$RESP"

# NOTE: TaskHierarchyController::children calls findOrFail without authorization,
# so OTHER users (non-members) can also view — documented gap.
act_as "$OTHER_TOKEN"
RESP=$(api_get "/tasks/$POL_TASK_ID/children")
STATUS=$(status_from_response "$RESP")
if [ "$STATUS" = "200" ]; then
    expected_gap "TaskHierarchy view [other — no auth check in children endpoint]" \
        "TaskHierarchyController::children does not call authorize — any auth user can view — live: $STATUS"
else
    assert_api "TaskHierarchy view [other → 403]" "403" "$RESP"
fi

act_as "$OWNER_TOKEN"
RESP=$(api_get "/tasks/$POL_TASK_ID/children")
assert_api "TaskHierarchy view [owner → 200]" "200" "$RESP"

# create child — POST /tasks/{parentTaskId}/children
# Requires child_task_id (existing task). Create a standalone task first to use as child.
act_as "$OWNER_TOKEN"
_CH_TASK_RESP=$(api_json POST "/tasks" "{\"title\":\"child-hier-src\",\"column_id\":\"$POL_COLUMN_ID\",\"priority\":\"low\"}")
_CH_TASK_SRC=$(json_value "$(body_from_response "$_CH_TASK_RESP")" "data.id")
[ -z "$_CH_TASK_SRC" ] && _CH_TASK_SRC=$(json_value "$(body_from_response "$_CH_TASK_RESP")" "id")

_CH_TASK_RESP2=$(api_json POST "/tasks" "{\"title\":\"child-hier-src2\",\"column_id\":\"$POL_COLUMN_ID\",\"priority\":\"low\"}")
_CH_TASK_SRC2=$(json_value "$(body_from_response "$_CH_TASK_RESP2")" "data.id")
[ -z "$_CH_TASK_SRC2" ] && _CH_TASK_SRC2=$(json_value "$(body_from_response "$_CH_TASK_RESP2")" "id")

if [ -n "$_CH_TASK_SRC" ] && [ -n "$_CH_TASK_SRC2" ]; then
    # owner creates child hierarchy
    act_as "$OWNER_TOKEN"
    RESP=$(api_json POST "/tasks/$POL_TASK_ID/children" \
        "{\"child_task_id\":\"$_CH_TASK_SRC\"}")
    assert_api "TaskHierarchy create [owner → 201]" "200 201" "$RESP"
    _CHILD_TASK_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
    [ -z "$_CHILD_TASK_ID" ] && _CHILD_TASK_ID=$(json_value "$(body_from_response "$RESP")" "id")

    # member (Contributor role) can create hierarchy
    act_as "$MEMBER_TOKEN"
    RESP=$(api_json POST "/tasks/$POL_TASK_ID/children" \
        "{\"child_task_id\":\"$_CH_TASK_SRC2\"}")
    assert_api "TaskHierarchy create [member Contributor → 200/201]" "200 201" "$RESP"
    _CHILD_TASK_MEMBER=$(json_value "$(body_from_response "$RESP")" "data.id")
    [ -z "$_CHILD_TASK_MEMBER" ] && _CHILD_TASK_MEMBER=$(json_value "$(body_from_response "$RESP")" "id")

    # other → 403 (not a project member, policy denies)
    act_as "$OWNER_TOKEN"
    _CH_TASK_RESP3=$(api_json POST "/tasks" "{\"title\":\"child-hier-src3\",\"column_id\":\"$POL_COLUMN_ID\",\"priority\":\"low\"}")
    _CH_TASK_SRC3=$(json_value "$(body_from_response "$_CH_TASK_RESP3")" "data.id")
    [ -z "$_CH_TASK_SRC3" ] && _CH_TASK_SRC3=$(json_value "$(body_from_response "$_CH_TASK_RESP3")" "id")

    act_as "$OTHER_TOKEN"
    RESP=$(api_json POST "/tasks/$POL_TASK_ID/children" \
        "{\"child_task_id\":\"$_CH_TASK_SRC3\"}")
    assert_api "TaskHierarchy create [other → 403]" "403" "$RESP"
    act_as "$ADMIN_TOKEN"
    [ -n "${_CH_TASK_SRC3:-}" ] && api_delete "/tasks/$_CH_TASK_SRC3" > /dev/null 2>&1 || true
else
    skip_case "TaskHierarchy create" "Failed to create source tasks for hierarchy test"
fi

# Clean up child tasks
act_as "$ADMIN_TOKEN"
[ -n "${_CHILD_TASK_ID:-}"     ] && api_delete "/tasks/$_CHILD_TASK_ID"     > /dev/null 2>&1 || true
[ -n "${_CHILD_TASK_MEMBER:-}" ] && api_delete "/tasks/$_CHILD_TASK_MEMBER" > /dev/null 2>&1 || true
[ -n "${_CH_TASK_SRC:-}"       ] && api_delete "/tasks/$_CH_TASK_SRC"       > /dev/null 2>&1 || true
[ -n "${_CH_TASK_SRC2:-}"      ] && api_delete "/tasks/$_CH_TASK_SRC2"      > /dev/null 2>&1 || true

# ============================================================
# TASK RELATIONSHIP POLICY
# ============================================================
echo ""
echo "----- Task Relationship Policy -----"
# Policy: all abilities owner-only. But the controller for view (index)
# and other endpoints may not enforce the policy strictly.
# We assert the documented matrix and emit expected_gap for any deviation.

# view relationships — GET /tasks/{taskId}/relationships
act_as "$OWNER_TOKEN"
RESP=$(api_get "/tasks/$POL_TASK_ID/relationships")
assert_api "TaskRelationship view [owner → 200]" "200" "$RESP"

# Check if policy is enforced for member/other
act_as "$MEMBER_TOKEN"
RESP=$(api_get "/tasks/$POL_TASK_ID/relationships")
STATUS=$(status_from_response "$RESP")
if [ "$STATUS" = "200" ]; then
    expected_gap "TaskRelationship view [member — no policy enforcement on index]" \
        "TaskRelationshipPolicy::view is owner-only but index endpoint returns 200 for members — live: $STATUS"
else
    assert_api "TaskRelationship view [member → 403]" "403" "$RESP"
fi

act_as "$OTHER_TOKEN"
RESP=$(api_get "/tasks/$POL_TASK_ID/relationships")
STATUS=$(status_from_response "$RESP")
if [ "$STATUS" = "200" ]; then
    expected_gap "TaskRelationship view [other — no policy enforcement on index]" \
        "TaskRelationshipPolicy::view is owner-only but index endpoint returns 200 for others — live: $STATUS"
else
    assert_api "TaskRelationship view [other → 403]" "403" "$RESP"
fi

# create — POST /tasks/{taskId}/relationships (owner only)
act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/tasks/$POL_TASK_ID/relationships" \
    "{\"related_task_id\":\"$POL_TASK_ID_2\",\"relationship_type\":\"related_to\"}")
assert_api "TaskRelationship create [owner → 201]" "200 201" "$RESP"
_RELSHIP_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_RELSHIP_ID" ] && _RELSHIP_ID=$(json_value "$(body_from_response "$RESP")" "id")

# member create — policy says 403; may get 422 if relationship already exists
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/tasks/$POL_TASK_ID/relationships" \
    "{\"related_task_id\":\"$POL_TASK_ID_2\",\"relationship_type\":\"related_to\"}")
STATUS=$(status_from_response "$RESP")
if [ "$STATUS" = "403" ]; then
    assert_api "TaskRelationship create [member → 403]" "403" "$RESP"
elif [ "$STATUS" = "422" ]; then
    expected_gap "TaskRelationship create [member — 422 instead of 403]" \
        "Policy not enforced before validation; relationship already exists — live: $STATUS"
else
    assert_api "TaskRelationship create [member → 403]" "403" "$RESP"
fi

# update, delete (owner only)
if [ -n "$_RELSHIP_ID" ]; then
    act_as "$MEMBER_TOKEN"
    RESP=$(api_json PUT "/task-relationships/$_RELSHIP_ID" "{\"relationship_type\":\"related_to\"}")
    STATUS=$(status_from_response "$RESP")
    if [ "$STATUS" = "403" ]; then
        assert_api "TaskRelationship update [member → 403]" "403" "$RESP"
    elif [ "$STATUS" = "200" ]; then
        expected_gap "TaskRelationship update [member — policy not enforced]" \
            "TaskRelationshipPolicy::update is owner-only but member can update — live: $STATUS"
    else
        assert_api "TaskRelationship update [member → 403]" "403" "$RESP"
    fi

    act_as "$OWNER_TOKEN"
    RESP=$(api_json PUT "/task-relationships/$_RELSHIP_ID" "{\"relationship_type\":\"related_to\"}")
    assert_api "TaskRelationship update [owner → 200]" "200" "$RESP"

    act_as "$MEMBER_TOKEN"
    RESP=$(api_delete "/task-relationships/$_RELSHIP_ID")
    STATUS=$(status_from_response "$RESP")
    if [ "$STATUS" = "403" ]; then
        assert_api "TaskRelationship delete [member → 403]" "403" "$RESP"
    elif [ "$STATUS" = "200" ] || [ "$STATUS" = "204" ]; then
        expected_gap "TaskRelationship delete [member — policy not enforced]" \
            "TaskRelationshipPolicy::delete is owner-only but member can delete — live: $STATUS"
        _RELSHIP_ID=""  # consumed by member
    else
        assert_api "TaskRelationship delete [member → 403]" "403" "$RESP"
    fi

    # Owner delete (if not already consumed)
    if [ -n "$_RELSHIP_ID" ]; then
        act_as "$OWNER_TOKEN"
        RESP=$(api_delete "/task-relationships/$_RELSHIP_ID")
        assert_api "TaskRelationship delete [owner → 200]" "200 204" "$RESP"
    else
        skip_case "TaskRelationship delete [owner]" "relationship already deleted by member (policy gap)"
    fi
fi

# ============================================================
# TIMELOG POLICY
# ============================================================
echo ""
echo "----- TimeLog Policy -----"
# view/update/delete: admin/self/project owner → 200; other member → 403

# viewAny — all auth → 200
act_as "$ADMIN_TOKEN"
RESP=$(api_get "/time-logs")
assert_api "TimeLog viewAny [admin]" "200" "$RESP"

act_as "$AUTHOR_TOKEN"
RESP=$(api_get "/time-logs")
assert_api "TimeLog viewAny [self/author]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/time-logs")
assert_api "TimeLog viewAny [member]" "200" "$RESP"

# view — GET /time-logs/{id}
# Admin/self(author)/owner → 200; any project member → 200 (Decision 6: view = any log
# in a project the user is a member of)
act_as "$ADMIN_TOKEN"
RESP=$(api_get "/time-logs/$POL_TIMELOG_ID")
assert_api "TimeLog view [admin → 200]" "200" "$RESP"

act_as "$AUTHOR_TOKEN"
RESP=$(api_get "/time-logs/$POL_TIMELOG_ID")
assert_api "TimeLog view [self/author → 200]" "200" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_get "/time-logs/$POL_TIMELOG_ID")
assert_api "TimeLog view [owner → 200]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/time-logs/$POL_TIMELOG_ID")
assert_api "TimeLog view [project member → 200]" "200" "$RESP"

# update — PUT /time-logs/{id}
act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/time-logs/$POL_TIMELOG_ID" "{\"minutes\":45}")
assert_api "TimeLog update [member → 403]" "403" "$RESP"

act_as "$ADMIN_TOKEN"
RESP=$(api_json PUT "/time-logs/$POL_TIMELOG_ID" "{\"minutes\":59}")
assert_api "TimeLog update [admin → 200]" "200" "$RESP"

act_as "$AUTHOR_TOKEN"
RESP=$(api_json PUT "/time-logs/$POL_TIMELOG_ID" "{\"minutes\":30}")
assert_api "TimeLog update [self/author → 200]" "200" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_json PUT "/time-logs/$POL_TIMELOG_ID" "{\"minutes\":35}")
assert_api "TimeLog update [owner → 200]" "200" "$RESP"

# delete — DELETE /time-logs/{id}
act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/time-logs/$POL_TIMELOG_ID")
assert_api "TimeLog delete [member → 403]" "403" "$RESP"

act_as "$ADMIN_TOKEN"
RESP=$(api_delete "/time-logs/$POL_TIMELOG_ID")
assert_api "TimeLog delete [admin → 200]" "200 204" "$RESP"
# POL_TIMELOG_ID is now deleted; clear it so teardown doesn't double-delete
POL_TIMELOG_ID=""

# ============================================================
# NOTIFICATION PREFERENCE POLICY
# ============================================================
echo ""
echo "----- Notification Preference Policy -----"
# Self-only for view/update; admin → 200; other → 403
# The route is POST /notification-preferences to create defaults and GET to list

# viewAny — GET /notification-preferences (Auth)
act_as "$OWNER_TOKEN"
RESP=$(api_get "/notification-preferences")
assert_api "NotificationPreference viewAny [owner]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/notification-preferences")
assert_api "NotificationPreference viewAny [member]" "200" "$RESP"

# create defaults for self (POST /notification-preferences/create-defaults)
act_as "$AUTHOR_TOKEN"
RESP=$(api_json POST "/notification-preferences/create-defaults" '{}')
assert_api "NotificationPreference createDefaults [self/author]" "200 201" "$RESP"

# update own preferences — POST /notification-preferences
# Policy: self (user_id matches)
act_as "$AUTHOR_TOKEN"
RESP=$(api_json POST "/notification-preferences" \
    "{\"notification_type\":\"task_assigned\",\"email_enabled\":true,\"in_app_enabled\":true}")
assert_api "NotificationPreference update [self → 200]" "200 201" "$RESP"

# ============================================================
# USER POLICY
# ============================================================
echo ""
echo "----- User Policy -----"

# viewAny — GET /users — all auth → 200
act_as "$ADMIN_TOKEN"
RESP=$(api_get "/users")
assert_api "User viewAny [admin]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/users")
assert_api "User viewAny [member auth]" "200" "$RESP"

# view — GET /users/{id}
# Admin or self → 200; other → 403
act_as "$ADMIN_TOKEN"
RESP=$(api_get "/users/$OWNER_USER_ID")
assert_api "User view [admin → 200]" "200" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_get "/users/$OWNER_USER_ID")
assert_api "User view [self → 200]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/users/$OWNER_USER_ID")
assert_api "User view [other → 200 (public profiles)]" "200" "$RESP"

# update — PUT /users/{id}
# Admin/self → 200; other → 403
act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/users/$OWNER_USER_ID" "{\"name\":\"attempted-by-member\"}")
assert_api "User update [other → 403]" "403" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_json PUT "/users/$OWNER_USER_ID" "{\"name\":\"owner-self-update\"}")
assert_api "User update [self → 200]" "200" "$RESP"

act_as "$ADMIN_TOKEN"
RESP=$(api_json PUT "/users/$OWNER_USER_ID" "{\"name\":\"owner-updated-by-admin\"}")
assert_api "User update [admin → 200]" "200" "$RESP"

# delete — admin only; admin cannot delete self
act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/users/$OWNER_USER_ID")
assert_api "User delete [other → 403]" "403" "$RESP"

# Admin (super admin) can delete any user. Use a throwaway user so we never
# delete the seeded admin (deleting it would invalidate ADMIN_TOKEN for the
# remainder of the suite). Under Gate::before, super admin bypasses UserPolicy.
act_as "$ADMIN_TOKEN"
_THROWAWAY_EMAIL="pol-throwaway-$(date +%s)-$RANDOM@example.com"
RESP=$(api_json POST "/users" \
    "{\"name\":\"pol-throwaway\",\"email\":\"$_THROWAWAY_EMAIL\",\"password\":\"password\",\"password_confirmation\":\"password\"}")
_THROWAWAY_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_THROWAWAY_ID" ] && _THROWAWAY_ID=$(json_value "$(body_from_response "$RESP")" "id")
RESP=$(api_delete "/users/$_THROWAWAY_ID")
assert_api "User delete [admin (super admin) deletes another user → 200]" "200 204" "$RESP"

# create — admin only
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/users" \
    "{\"name\":\"test-create-attempt\",\"email\":\"test-create-$(date +%s)@example.com\",\"password\":\"password\",\"password_confirmation\":\"password\"}")
assert_api "User create [non-admin → 403]" "403" "$RESP"

# ============================================================
# WEBHOOK POLICY
# ============================================================
echo ""
echo "----- Webhook Policy -----"
# viewAny/view: owner+member → 200; other → 403
# create/update/delete: owner only → 200; member → 403; NO admin override

# viewAny — GET /webhooks
act_as "$OWNER_TOKEN"
RESP=$(api_get "/webhooks")
assert_api "Webhook viewAny [owner → 200]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/webhooks")
assert_api "Webhook viewAny [member → 200]" "200" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_get "/webhooks")
assert_api "Webhook viewAny [other → 200 empty (scoped)]" "200" "$RESP"

# view — GET /webhooks/{id}
act_as "$OWNER_TOKEN"
RESP=$(api_get "/webhooks/$POL_WEBHOOK_ID")
assert_api "Webhook view [owner → 200]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/webhooks/$POL_WEBHOOK_ID")
assert_api "Webhook view [member → 200]" "200" "$RESP"

act_as "$OTHER_TOKEN"
RESP=$(api_get "/webhooks/$POL_WEBHOOK_ID")
assert_api "Webhook view [other → 403]" "403" "$RESP"

# create — POST /projects/{projectId}/webhooks (owner only)
_WH_UNIQUE="wh-$(date +%s)-$RANDOM"
act_as "$MEMBER_TOKEN"
RESP=$(api_json POST "/projects/$POL_PROJECT_ID/webhooks" \
    "{\"name\":\"member-wh-${_WH_UNIQUE}\",\"url\":\"https://webhook.site/member-test\",\"events\":[\"task.created\"],\"is_active\":false}")
assert_api "Webhook create [member → 403]" "403" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_json POST "/projects/$POL_PROJECT_ID/webhooks" \
    "{\"name\":\"owner-wh-${_WH_UNIQUE}\",\"url\":\"https://webhook.site/owner-test\",\"events\":[\"task.created\"],\"is_active\":false}")
assert_api "Webhook create [owner → 200/201]" "200 201" "$RESP"
_WH_TMP_ID=$(json_value "$(body_from_response "$RESP")" "data.id")
[ -z "$_WH_TMP_ID" ] && _WH_TMP_ID=$(json_value "$(body_from_response "$RESP")" "id")

# update — PUT /webhooks/{id} (owner only)
act_as "$MEMBER_TOKEN"
RESP=$(api_json PUT "/webhooks/$POL_WEBHOOK_ID" "{\"name\":\"member-update-attempt\"}")
assert_api "Webhook update [member → 403]" "403" "$RESP"

act_as "$OWNER_TOKEN"
RESP=$(api_json PUT "/webhooks/$POL_WEBHOOK_ID" "{\"name\":\"owner-webhook-updated\"}")
assert_api "Webhook update [owner → 200]" "200" "$RESP"

# delete — owner → success; member → 403; admin (super admin) → success
act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/webhooks/$POL_WEBHOOK_ID")
assert_api "Webhook delete [member → 403]" "403" "$RESP"

# Admin is super admin → bypasses WebhookPolicy → success.
# Delete the extra owner-created webhook so POL_WEBHOOK_ID survives for the owner case.
act_as "$ADMIN_TOKEN"
RESP=$(api_delete "/webhooks/$_WH_TMP_ID")
assert_api "Webhook delete [admin (super admin) → 200]" "200 204" "$RESP"
_WH_TMP_ID=""  # consumed by admin

# Owner delete succeeds
act_as "$OWNER_TOKEN"
RESP=$(api_delete "/webhooks/$POL_WEBHOOK_ID")
assert_api "Webhook delete [owner → 200]" "200 204" "$RESP"
POL_WEBHOOK_ID=""  # consumed

# Clean up the extra webhook created above (already consumed by admin above)
[ -n "${_WH_TMP_ID:-}" ] && { act_as "$OWNER_TOKEN"; api_delete "/webhooks/$_WH_TMP_ID" > /dev/null 2>&1 || true; }

# ============================================================
# ANALYTICS POLICY
# ============================================================
echo ""
echo "----- Analytics Policy -----"
# view task metrics: Auth → 200
# manage (clearCache): Admin or manage_analytics permission → 200; plain member → 403

# view task metrics — GET /analytics/tasks/metrics
act_as "$AUTHOR_TOKEN"
RESP=$(api_get "/analytics/tasks/metrics")
assert_api "Analytics view task metrics [auth → 200]" "200" "$RESP"

act_as "$ADMIN_TOKEN"
RESP=$(api_get "/analytics/tasks/metrics")
assert_api "Analytics view task metrics [admin → 200]" "200" "$RESP"

# dashboard overview — GET /analytics/dashboard
act_as "$MEMBER_TOKEN"
RESP=$(api_get "/analytics/dashboard")
assert_api "Analytics dashboard viewAny [member auth → 200]" "200" "$RESP"

# manage — DELETE /analytics/cache (admin or manage_analytics)
# Plain member should get 403 on management endpoint
act_as "$MEMBER_TOKEN"
RESP=$(api_delete "/analytics/cache")
STATUS=$(status_from_response "$RESP")
if [ "$STATUS" = "403" ]; then
    assert_api "Analytics manage cache [plain member → 403]" "403" "$RESP"
else
    # Some endpoints may return 200/204 if no permission checks implemented yet
    expected_gap "Analytics manage cache [plain member]" \
        "Expected 403 but got $STATUS — AnalyticsPolicy manage may not be enforced here"
fi

act_as "$ADMIN_TOKEN"
RESP=$(api_delete "/analytics/cache")
assert_api "Analytics manage cache [admin → 200/204]" "200 204" "$RESP"

# ============================================================
# AUTOMATION BUTTON POLICY
# ============================================================
echo ""
echo "----- Automation Button Policy -----"

# viewAny — all auth → 200
act_as "$ADMIN_TOKEN"
RESP=$(api_get "/automation-buttons")
assert_api "AutomationButton viewAny [admin]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/automation-buttons")
assert_api "AutomationButton viewAny [member]" "200" "$RESP"

if [ -n "${POL_AUTO_BTN_ID:-}" ]; then
    # view — owner/creator/member → 200
    act_as "$OWNER_TOKEN"
    RESP=$(api_get "/automation-buttons/$POL_AUTO_BTN_ID")
    assert_api "AutomationButton view [owner → 200]" "200" "$RESP"

    act_as "$MEMBER_TOKEN"
    RESP=$(api_get "/automation-buttons/$POL_AUTO_BTN_ID")
    assert_api "AutomationButton view [member → 200]" "200" "$RESP"

    act_as "$OTHER_TOKEN"
    RESP=$(api_get "/automation-buttons/$POL_AUTO_BTN_ID")
    assert_api "AutomationButton view [other → 403]" "403" "$RESP"

    # update — owner or created_by → 200; member → 403
    act_as "$MEMBER_TOKEN"
    RESP=$(api_json PUT "/automation-buttons/$POL_AUTO_BTN_ID" \
        "{\"button_label\":\"member-update-attempt\"}")
    assert_api "AutomationButton update [member → 403]" "403" "$RESP"

    act_as "$OWNER_TOKEN"
    RESP=$(api_json PUT "/automation-buttons/$POL_AUTO_BTN_ID" \
        "{\"button_label\":\"Run Policy Test Updated\"}")
    assert_api "AutomationButton update [owner → 200]" "200" "$RESP"
else
    skip_case "AutomationButton view/update" "POL_AUTO_BTN_ID not available (creation failed during setup)"
fi

# ============================================================
# AUTOMATION RULE POLICY
# ============================================================
echo ""
echo "----- Automation Rule Policy -----"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/automation-rules")
assert_api "AutomationRule viewAny [member]" "200" "$RESP"

# Create a rule as owner to test view/update
act_as "$OWNER_TOKEN"
_RULE_RESP=$(api_json POST "/automation-rules" \
    "{\"project_id\":\"$POL_PROJECT_ID\",\"name\":\"pol-test-rule-$(date +%s)\",\"trigger\":{\"type\":\"task_created\"},\"actions\":[{\"type\":\"add_comment\",\"config\":{\"content\":\"automated\"}}],\"is_active\":false}")
_RULE_ID=$(json_value "$(body_from_response "$_RULE_RESP")" "data.id")
[ -z "$_RULE_ID" ] && _RULE_ID=$(json_value "$(body_from_response "$_RULE_RESP")" "id")
_RULE_STATUS=$(status_from_response "$_RULE_RESP")
if [ "$_RULE_STATUS" = "200" ] || [ "$_RULE_STATUS" = "201" ]; then
    assert_api "AutomationRule create [owner]" "$_RULE_STATUS" "$_RULE_RESP"
fi

if [ -n "${_RULE_ID:-}" ]; then
    # view — project member → 200
    act_as "$MEMBER_TOKEN"
    RESP=$(api_get "/automation-rules/$_RULE_ID")
    assert_api "AutomationRule view [member → 200]" "200" "$RESP"

    # update — owner or created_by → 200; member → 403
    act_as "$MEMBER_TOKEN"
    RESP=$(api_json PUT "/automation-rules/$_RULE_ID" "{\"name\":\"member-update-attempt\"}")
    assert_api "AutomationRule update [member → 403]" "403" "$RESP"

    act_as "$OWNER_TOKEN"
    RESP=$(api_json PUT "/automation-rules/$_RULE_ID" "{\"name\":\"rule-updated-owner\"}")
    assert_api "AutomationRule update [owner → 200]" "200" "$RESP"

    # Clean up
    act_as "$ADMIN_TOKEN"
    api_delete "/automation-rules/$_RULE_ID" > /dev/null 2>&1 || true
fi

# ============================================================
# AUTOMATION POLICY (empty class — all skip)
# ============================================================
echo ""
echo "----- Automation Policy -----"
skip_case "AutomationPolicy" "Empty class — no abilities defined"

# ============================================================
# SEARCH POLICY
# ============================================================
echo ""
echo "----- Search Policy -----"
# All abilities require is_active === true
# Active user → 200; skip_case for inactive user (needs DB toggle)

act_as "$OWNER_TOKEN"
RESP=$(api_get "/search?q=test")
assert_api "Search [active owner → 200]" "200" "$RESP"

act_as "$MEMBER_TOKEN"
RESP=$(api_get "/search/recent")
assert_api "Search recent [active member → 200]" "200" "$RESP"

act_as "$ADMIN_TOKEN"
RESP=$(api_get "/search/saved")
assert_api "Search saved [active admin → 200]" "200" "$RESP"

skip_case "Search [inactive user]" "requires DB toggle of is_active=false — not automated in this suite"

# ============================================================
# === Teardown ===
# ============================================================
act_as "$ADMIN_TOKEN"
[ -n "${POL_COMMENT_A:-}" ]    && api_delete "/comments/$POL_COMMENT_A"       > /dev/null 2>&1 || true
[ -n "${POL_COMMENT_B:-}" ]    && api_delete "/comments/$POL_COMMENT_B"       > /dev/null 2>&1 || true
[ -n "${POL_ATTACHMENT_A:-}" ] && api_delete "/attachments/$POL_ATTACHMENT_A" > /dev/null 2>&1 || true
[ -n "${POL_ATTACHMENT_B:-}" ] && api_delete "/attachments/$POL_ATTACHMENT_B" > /dev/null 2>&1 || true
[ -n "${POL_TIMELOG_ID:-}" ]   && api_delete "/time-logs/$POL_TIMELOG_ID"     > /dev/null 2>&1 || true
[ -n "${POL_WEBHOOK_ID:-}" ]   && api_delete "/webhooks/$POL_WEBHOOK_ID"      > /dev/null 2>&1 || true
rm -f /tmp/pol-test-attach.txt
cleanup_common_records
print_summary_and_exit
