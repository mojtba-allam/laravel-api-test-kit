#!/bin/bash
# Search, activity, and analytics API coverage
set -e

source "$(dirname "$0")/api-test-helpers.sh"

echo "=========================================="
echo "Search, Activity, and Analytics API Tests"
echo "=========================================="
login_admin
echo ""

SUFFIX="$(date +%s)"
create_workspace "$SUFFIX"
create_project "$SUFFIX"
create_section "$SUFFIX"
create_column "$SUFFIX"
create_task "$SUFFIX" TASK_ID

RESPONSE=$(api_json POST "/projects/$PROJECT_ID/teams" '{"name":"Analytics API Team","description":"Team for analytics curl coverage","color":"#0EA5E9","is_active":true}')
TEAM_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")

ACTIVITY_ID=$($PHP_BIN artisan tinker --execute="
use Illuminate\Support\Str;
use Modules\Activity\Models\Activity;
use Modules\Task\Models\Task;

\$activity = Activity::query()->create([
    'id' => (string) Str::uuid(),
    'user_id' => '$USER_ID',
    'subject_type' => Task::class,
    'subject_id' => '$TASK_ID',
    'action' => 'created',
    'description' => 'API activity test',
    'properties' => ['source' => 'curl-suite'],
]);
echo \$activity->id;
" 2>/dev/null | tail -1)

echo "✓ Test data created: $WORKSPACE_ID / $PROJECT_ID / $TASK_ID"
echo ""

echo "=========================================="; echo "Search APIs"; echo "=========================================="
assert_api "GET /api/v1/search → 200 global search" "200" "$(api_get "/search?q=ApiTask&workspace_id=$WORKSPACE_ID&types[]=tasks&types[]=projects&limit=10")"
assert_api "GET /api/v1/search/command-palette → 200 command palette" "200" "$(api_get "/search/command-palette?q=Api&workspace_id=$WORKSPACE_ID&limit=5")"
assert_api "GET /api/v1/search/recent → 200 recent searches" "200" "$(api_get "/search/recent")"
assert_api "GET /api/v1/search/saved → 200 saved searches" "200" "$(api_get "/search/saved")"
RESPONSE=$(api_json POST "/search/saved" "{\"name\":\"API Saved Search $SUFFIX\",\"query\":\"ApiTask\",\"workspace_id\":\"$WORKSPACE_ID\",\"filters\":{\"types\":[\"tasks\"]}}")
SAVED_SEARCH_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
assert_api "POST /api/v1/search/saved → 201 creates saved search" "201" "$RESPONSE"
if [ -n "$SAVED_SEARCH_ID" ]; then
    assert_api "DELETE /api/v1/search/saved/{id} → 200 deletes saved search" "200" "$(api_delete "/search/saved/$SAVED_SEARCH_ID")"
fi

echo ""; echo "=========================================="; echo "Activity APIs"; echo "=========================================="
assert_api "GET /api/v1/activities → 200 activity list" "200" "$(api_get "/activities?per_page=10")"
if [ -n "$ACTIVITY_ID" ]; then
    assert_api "GET /api/v1/activities/{id} → 200 activity details" "200" "$(api_get "/activities/$ACTIVITY_ID")"
fi
assert_api "GET /api/v1/users/{userId}/activities → 200 user activities" "200" "$(api_get "/users/$USER_ID/activities?per_page=10")"
assert_api "GET /api/v1/activities/task/{taskId} → 200 task activities" "200" "$(api_get "/activities/task/$TASK_ID?per_page=10")"
assert_api "GET /api/v1/activities/action/{action} → 200 action activities" "200" "$(api_get "/activities/action/created?per_page=10")"
assert_api "GET /api/v1/activities/search → 200 activity search" "200" "$(api_get "/activities/search?user_id=$USER_ID&action=created&search=API&per_page=10")"
assert_api "GET /api/v1/activities/statistics → 200 activity statistics" "200" "$(api_get "/activities/statistics")"
assert_api "DELETE /api/v1/activities/cleanup → 200 cleanup old activities" "200" "$(api_delete "/activities/cleanup?days=999999")"

echo ""; echo "=========================================="; echo "Analytics APIs"; echo "=========================================="
assert_api "GET /api/v1/analytics/tasks/metrics → 200 task metrics" "200" "$(api_get "/analytics/tasks/metrics?metric_type=task&period=month")"
assert_api "GET /api/v1/analytics/projects/{project}/analytics → 200 project analytics" "200" "$(api_get "/analytics/projects/$PROJECT_ID/analytics")"
assert_api "GET /api/v1/analytics/users/{user}/productivity → 200 user productivity" "200" "$(api_get "/analytics/users/$USER_ID/productivity?period=month")"
assert_api "GET /api/v1/analytics/teams/{team}/performance → 200 team performance" "200" "$(api_get "/analytics/teams/$PROJECT_ID/performance")"
assert_api "GET /api/v1/analytics/time-tracking/insights → 200 time insights" "200" "$(api_get "/analytics/time-tracking/insights?metric_type=time&period=month")"
assert_api "GET /api/v1/analytics/burndown/{project} → 200 burndown" "200" "$(api_get "/analytics/burndown/$PROJECT_ID")"
assert_api "GET /api/v1/analytics/heatmap/{user} → 200 heatmap" "200" "$(api_get "/analytics/heatmap/$USER_ID")"
assert_api "GET /api/v1/analytics/charts/{metricType} → 200 chart data" "200" "$(api_get "/analytics/charts/task?chart_type=line")"
assert_api "GET /api/v1/analytics/metrics/summary → 200 metrics summary" "200" "$(api_get "/analytics/metrics/summary")"
assert_api "GET /api/v1/analytics/metrics/{metricType}/available → 200 available metrics" "200" "$(api_get "/analytics/metrics/task/available")"
assert_api "GET /api/v1/analytics/realtime/{metricType} → 200 realtime analytics" "200" "$(api_get "/analytics/realtime/task")"
assert_api "DELETE /api/v1/analytics/cache → hits clear cache" "200 403" "$(api_delete "/analytics/cache")"
assert_api "GET /api/v1/analytics/admin/system/usage → 200 system usage" "200" "$(api_get "/analytics/admin/system/usage")"
assert_api "GET /api/v1/analytics/admin/performance/metrics → 200 performance metrics" "200" "$(api_get "/analytics/admin/performance/metrics")"

echo ""; echo "=========================================="; echo "Analytics Dashboard APIs"; echo "=========================================="
assert_api "GET /api/v1/analytics/dashboard → 200 available dashboards" "200" "$(api_get "/analytics/dashboard")"
assert_api "GET /api/v1/analytics/dashboard/individual/data → 200 individual dashboard" "200" "$(api_get "/analytics/dashboard/individual/data")"
assert_api "GET /api/v1/analytics/dashboard/{type} → 200 individual dashboard by type" "200" "$(api_get "/analytics/dashboard/individual")"
assert_api "GET /api/v1/analytics/dashboard/{type}/widgets/{widget} → 200 widget config" "200" "$(api_get "/analytics/dashboard/individual/widgets/personal_productivity")"
assert_api "GET /api/v1/analytics/dashboard/{type}/realtime → 200 realtime dashboard" "200" "$(api_get "/analytics/dashboard/individual/realtime")"
assert_api "GET /api/v1/analytics/dashboard/executive/data → hits executive dashboard" "200 403" "$(api_get "/analytics/dashboard/executive/data")"
assert_api "GET /api/v1/analytics/dashboard/project-manager/data → hits project manager dashboard" "200 403" "$(api_get "/analytics/dashboard/project-manager/data")"
assert_api "GET /api/v1/analytics/dashboard/team-lead/data → hits team lead dashboard" "200 403" "$(api_get "/analytics/dashboard/team-lead/data")"

[ -n "${ACTIVITY_ID:-}" ] && $PHP_BIN artisan tinker --execute="\Modules\Activity\Models\Activity::whereKey('$ACTIVITY_ID')->delete();" >/dev/null 2>&1 || true
[ -n "${TEAM_ID:-}" ] && api_delete "/project-teams/$TEAM_ID" >/dev/null || true
cleanup_common_records
print_summary_and_exit
