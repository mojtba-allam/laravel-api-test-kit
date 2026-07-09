#!/bin/bash
# Workspace subresources and project team API coverage
set -e

source "$(dirname "$0")/api-test-helpers.sh"

echo "=========================================="
echo "Workspace and Project Extended API Tests"
echo "=========================================="
login_admin
echo ""

SUFFIX="$(date +%s)"
create_workspace "$SUFFIX"
create_project "$SUFFIX"
$PHP_BIN artisan tinker --execute="\Modules\Project\Models\Project::whereKey('$PROJECT_ID')->update(['workspace_id' => '$WORKSPACE_ID']);" >/dev/null 2>&1 || true

OTHER_USER_ID=$($PHP_BIN artisan tinker --execute="echo \Modules\User\Models\User::where('id', '!=', '$USER_ID')->value('id');" 2>/dev/null | tail -1)
PROJECT_MEMBER_ID=$($PHP_BIN artisan tinker --execute="
use Illuminate\Support\Str;
use Modules\Project\Models\GlobalRole;
use Modules\Project\Models\ProjectMember;
use Modules\Project\Models\ProjectRole;

\$globalRoleId = GlobalRole::query()->value('id');
\$projectRole = ProjectRole::query()->firstOrCreate(
    ['project_id' => '$PROJECT_ID', 'name' => 'API Member'],
    ['id' => (string) Str::uuid(), 'description' => 'API test member role', 'is_default' => true, 'based_on_global_role_id' => \$globalRoleId]
);
\$member = ProjectMember::query()->firstOrCreate(
    ['project_id' => '$PROJECT_ID', 'user_id' => '$USER_ID'],
    ['id' => (string) Str::uuid(), 'global_role_id' => \$globalRoleId, 'project_role_id' => \$projectRole->id]
);
echo \$member->id;
" 2>/dev/null | tail -1)

echo "✓ Workspace/project created: $WORKSPACE_ID / $PROJECT_ID"
echo ""

echo "=========================================="; echo "Workspace Settings, Reporting, Exports"; echo "=========================================="
assert_api "GET /api/v1/workspaces/{workspace}/settings → 200 workspace settings" "200" "$(api_get "/workspaces/$WORKSPACE_ID/settings")"
assert_api "PUT /api/v1/workspaces/{workspace}/settings → 200 updates settings" "200" "$(api_json PUT "/workspaces/$WORKSPACE_ID/settings" '{"settings":{"timezone":"UTC","notifications":true}}')"
assert_api "GET /api/v1/workspaces/{workspace}/reporting → 200 reporting summary" "200" "$(api_get "/workspaces/$WORKSPACE_ID/reporting")"
assert_api "GET /api/v1/workspaces/{workspace}/exports → 200 exports list" "200" "$(api_get "/workspaces/$WORKSPACE_ID/exports")"
assert_api "POST /api/v1/workspaces/{workspace}/exports → 202 requests export" "202" "$(api_json POST "/workspaces/$WORKSPACE_ID/exports" '{"format":"json"}')"

echo ""; echo "=========================================="; echo "Workspace Collections and Members"; echo "=========================================="
assert_api "GET /api/v1/workspaces/{workspace}/collections → 200 collections list" "200" "$(api_get "/workspaces/$WORKSPACE_ID/collections")"
RESPONSE=$(api_json POST "/workspaces/$WORKSPACE_ID/collections" '{"name":"API Collection","description":"Created by curl suite","color":"#3B82F6","sort_order":1}')
COLLECTION_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
assert_api "POST /api/v1/workspaces/{workspace}/collections → 201 creates collection" "201" "$RESPONSE"
if [ -n "$COLLECTION_ID" ]; then
    assert_api "PUT /api/v1/workspaces/{workspace}/collections/{collection} → 200 updates collection" "200" "$(api_json PUT "/workspaces/$WORKSPACE_ID/collections/$COLLECTION_ID" '{"name":"Updated API Collection","color":"#10B981"}')"
    assert_api "POST /api/v1/workspaces/{workspace}/collections/{collection}/projects → 200 attaches project" "200" "$(api_json POST "/workspaces/$WORKSPACE_ID/collections/$COLLECTION_ID/projects" "{\"project_id\":\"$PROJECT_ID\"}")"
fi
assert_api "POST /api/v1/workspaces/{workspace}/invites → 201 creates invite" "201" "$(api_json POST "/workspaces/$WORKSPACE_ID/invites" "{\"email\":\"api-invite-$SUFFIX@example.com\"}")"
if [ -n "$OTHER_USER_ID" ]; then
    assert_api "POST /api/v1/workspaces/{workspace}/members → 201 adds member" "201" "$(api_json POST "/workspaces/$WORKSPACE_ID/members" "{\"user_id\":\"$OTHER_USER_ID\"}")"
fi
if [ -n "$COLLECTION_ID" ]; then
    assert_api "DELETE /api/v1/workspaces/{workspace}/collections/{collection} → 200 deletes collection" "200" "$(api_delete "/workspaces/$WORKSPACE_ID/collections/$COLLECTION_ID")"
fi

echo ""; echo "=========================================="; echo "Project Teams"; echo "=========================================="
assert_api "GET /api/v1/projects/{projectId}/teams → 200 project teams" "200" "$(api_get "/projects/$PROJECT_ID/teams")"
assert_api "GET /api/v1/projects/{projectId}/teams/active → 200 active teams" "200" "$(api_get "/projects/$PROJECT_ID/teams/active")"
RESPONSE=$(api_json POST "/projects/$PROJECT_ID/teams" '{"name":"API Team","description":"Created by curl suite","color":"#6366F1","is_active":true}')
TEAM_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
assert_api "POST /api/v1/projects/{projectId}/teams → 201 creates team" "201" "$RESPONSE"
if [ -n "$TEAM_ID" ]; then
    assert_api "GET /api/v1/project-teams/{id} → 200 team details" "200" "$(api_get "/project-teams/$TEAM_ID")"
    assert_api "PUT /api/v1/project-teams/{id} → 200 updates team" "200" "$(api_json PUT "/project-teams/$TEAM_ID" '{"name":"Updated API Team","is_active":true}')"
    assert_api "POST /api/v1/project-teams/{id}/deactivate → 200 deactivates team" "200" "$(api_json POST "/project-teams/$TEAM_ID/deactivate" '{}')"
    assert_api "POST /api/v1/project-teams/{id}/activate → 200 activates team" "200" "$(api_json POST "/project-teams/$TEAM_ID/activate" '{}')"
    assert_api "GET /api/v1/project-teams/{id}/members → 200 team members" "200" "$(api_get "/project-teams/$TEAM_ID/members")"
    if [ -n "$PROJECT_MEMBER_ID" ]; then
        assert_api "POST /api/v1/project-teams/{id}/members → 200 adds team member" "200" "$(api_json POST "/project-teams/$TEAM_ID/members" "{\"member_id\":\"$PROJECT_MEMBER_ID\"}")"
        assert_api "DELETE /api/v1/project-teams/{id}/members/{memberId} → 200 removes member" "200" "$(api_delete "/project-teams/$TEAM_ID/members/$PROJECT_MEMBER_ID")"
    fi
    assert_api "DELETE /api/v1/project-teams/{id} → 200 deletes team" "200" "$(api_delete "/project-teams/$TEAM_ID")"
fi

cleanup_common_records
print_summary_and_exit
