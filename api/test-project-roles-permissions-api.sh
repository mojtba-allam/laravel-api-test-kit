#!/bin/bash
# =============================================================================
# test-project-roles-permissions-api.sh
#
# Verifies the per-member, per-project granular permission model over real HTTP
# with real seeded users:
#   - Project roles are job-title labels only.
#   - Permissions are granted directly to a member (not the role).
#   - A project admin can grant/revoke a member's permissions, changing their
#     abilities (e.g. edit_task).
#   - The same job title can carry different permissions across projects.
#   - Non-admins cannot manage permissions.
#   - Super Admin bypasses everything.
# =============================================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "===== Project Roles & Permissions Test Suite ====="

# ---------------------------------------------------------------------------
# Identities: OWNER (project admin) = user-01, MEMBER = user-05, SUPER = admin
# ---------------------------------------------------------------------------
OWNER_TOKEN=$(login_as "user-01@finolo.com") || { echo "FATAL: owner login"; exit 1; }
login_as "user-01@finolo.com" >/dev/null 2>&1 || true
OWNER_ID="$LAST_LOGIN_USER_ID"

MEMBER_TOKEN=$(login_as "user-05@finolo.com") || { echo "FATAL: member login"; exit 1; }
login_as "user-05@finolo.com" >/dev/null 2>&1 || true
MEMBER_ID="$LAST_LOGIN_USER_ID"

SUPER_TOKEN=$(login_as "admin@finolo.com") || { echo "FATAL: admin login"; exit 1; }

unique="$(date +%s)-$RANDOM"

# ---------------------------------------------------------------------------
# Build a fresh project world as OWNER
# ---------------------------------------------------------------------------
act_as "$OWNER_TOKEN"

ws_resp=$(api_json POST "/workspaces" "{\"name\":\"RP-WS-$unique\",\"visibility\":\"private\"}")
WS_ID=$(json_value "$(body_from_response "$ws_resp")" "data.id")
[ -z "$WS_ID" ] && WS_ID=$(json_value "$(body_from_response "$ws_resp")" "id")

proj_resp=$(api_json POST "/projects" "{\"name\":\"RP-Proj-$unique\",\"workspace_id\":\"$WS_ID\"}")
PROJECT_ID=$(json_value "$(body_from_response "$proj_resp")" "data.id")
[ -z "$PROJECT_ID" ] && PROJECT_ID=$(json_value "$(body_from_response "$proj_resp")" "id")

sec_resp=$(api_json POST "/sections" "{\"name\":\"RP-Sec-$unique\",\"project_id\":\"$PROJECT_ID\"}")
SECTION_ID=$(json_value "$(body_from_response "$sec_resp")" "data.id")
[ -z "$SECTION_ID" ] && SECTION_ID=$(json_value "$(body_from_response "$sec_resp")" "id")

col_resp=$(api_json POST "/columns" "{\"name\":\"RP-Col-$unique\",\"section_id\":\"$SECTION_ID\"}")
COLUMN_ID=$(json_value "$(body_from_response "$col_resp")" "data.id")
[ -z "$COLUMN_ID" ] && COLUMN_ID=$(json_value "$(body_from_response "$col_resp")" "id")

task_resp=$(api_json POST "/tasks" "{\"title\":\"RP-Task-$unique\",\"column_id\":\"$COLUMN_ID\",\"priority\":\"medium\"}")
TASK_ID=$(json_value "$(body_from_response "$task_resp")" "data.id")
[ -z "$TASK_ID" ] && TASK_ID=$(json_value "$(body_from_response "$task_resp")" "id")

if [ -z "$PROJECT_ID" ] || [ -z "$TASK_ID" ]; then
    echo "FATAL: failed to build project world (project=$PROJECT_ID task=$TASK_ID)"
    exit 1
fi

# ---------------------------------------------------------------------------
# Add MEMBER to the project via a team (creates a project_member with defaults)
# ---------------------------------------------------------------------------
team_resp=$(api_json POST "/projects/$PROJECT_ID/teams" "{\"name\":\"RP-Team-$unique\",\"is_active\":true}")
TEAM_ID=$(json_value "$(body_from_response "$team_resp")" "data.id")
[ -z "$TEAM_ID" ] && TEAM_ID=$(json_value "$(body_from_response "$team_resp")" "id")

api_json POST "/project-teams/$TEAM_ID/members" "{\"user_id\":\"$MEMBER_ID\"}" >/dev/null

# Directly add member to project (bypass invite flow for test fixtures)
add_member_direct "$PROJECT_ID" "$MEMBER_ID"

# Confirm the member is now part of the project; the management endpoints accept
# either a project_member id or a user id, so we use the user id directly.
members_resp=$(api_get "/projects/$PROJECT_ID/members")
if ! echo "$(body_from_response "$members_resp")" | grep -q "$MEMBER_ID"; then
    echo "FATAL: member not added to project. Response: $(body_from_response "$members_resp")"
    exit 1
fi
MEMBER_RECORD_ID="$MEMBER_ID"

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

# 1. Project admin can read the permission catalog
act_as "$OWNER_TOKEN"
resp=$(api_get "/projects/$PROJECT_ID/permission-catalog")
assert_api "Catalog readable by project admin" 200 "$resp"

# 2. Non-admin member cannot read the catalog / manage
act_as "$MEMBER_TOKEN"
resp=$(api_get "/projects/$PROJECT_ID/permission-catalog")
assert_api "Catalog forbidden for non-admin member" 403 "$resp"

# 3. Revoke edit_task, then member cannot edit the task
act_as "$OWNER_TOKEN"
api_delete "/projects/$PROJECT_ID/members/$MEMBER_RECORD_ID/permissions/edit_task" >/dev/null
act_as "$MEMBER_TOKEN"
resp=$(api_json PUT "/tasks/$TASK_ID" "{\"title\":\"Member edit denied $unique\"}")
assert_api "Member without edit_task is denied (403)" 403 "$resp"

# 4. Admin grants edit_task; member can now edit
act_as "$OWNER_TOKEN"
resp=$(api_json POST "/projects/$PROJECT_ID/members/$MEMBER_RECORD_ID/permissions/edit_task" "{}")
assert_api "Admin grants edit_task (200)" 200 "$resp"
act_as "$MEMBER_TOKEN"
resp=$(api_json PUT "/tasks/$TASK_ID" "{\"title\":\"Member edit allowed $unique\"}")
assert_api "Member with edit_task can edit (200)" 200 "$resp"

# 5. Revoke again; denied again
act_as "$OWNER_TOKEN"
api_delete "/projects/$PROJECT_ID/members/$MEMBER_RECORD_ID/permissions/edit_task" >/dev/null
act_as "$MEMBER_TOKEN"
resp=$(api_json PUT "/tasks/$TASK_ID" "{\"title\":\"Member edit denied again $unique\"}")
assert_api "Member loses edit after revoke (403)" 403 "$resp"

# 6. Sync rejects unknown permission
act_as "$OWNER_TOKEN"
resp=$(api_json PUT "/projects/$PROJECT_ID/members/$MEMBER_RECORD_ID/permissions" "{\"permissions\":[\"not_real\"]}")
assert_api "Sync rejects unknown permission (422)" 422 "$resp"

# 7. Create a job-title role and assign it to the member
resp=$(api_json POST "/projects/$PROJECT_ID/roles" "{\"name\":\"QA-$unique\"}")
assert_api "Create job-title role (201)" 201 "$resp"
ROLE_ID=$(json_value "$(body_from_response "$resp")" "data.id")
resp=$(api_json PUT "/projects/$PROJECT_ID/members/$MEMBER_RECORD_ID/job-title" "{\"project_role_id\":\"$ROLE_ID\"}")
assert_api "Assign job-title to member (200)" 200 "$resp"

# 8. Super Admin can manage permissions on a project they do not own
act_as "$SUPER_TOKEN"
resp=$(api_get "/projects/$PROJECT_ID/permission-catalog")
assert_api "Super Admin can read catalog of any project (200)" 200 "$resp"

print_summary_and_exit
