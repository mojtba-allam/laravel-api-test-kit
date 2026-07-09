#!/bin/bash
# Remaining time log and notification endpoint coverage
set -e

source "$(dirname "$0")/api-test-helpers.sh"

echo "=========================================="
echo "TimeLog and Notification Extended API Tests"
echo "=========================================="
login_admin
echo ""

SUFFIX="$(date +%s)"
TODAY="$(date +%Y-%m-%d)"
create_workspace "$SUFFIX"
create_project "$SUFFIX"
create_section "$SUFFIX"
create_column "$SUFFIX"
create_task "$SUFFIX" TASK_ID

echo "✓ Test task created: $TASK_ID"
echo ""

echo "=========================================="; echo "TimeLog Extended APIs"; echo "=========================================="
RESPONSE=$(api_json POST "/time-logs" "{\"task_id\":\"$TASK_ID\",\"task_name\":\"ApiTask-$SUFFIX\",\"user_id\":\"$USER_ID\",\"project_id\":\"$PROJECT_ID\",\"project_name\":\"ApiProject-$SUFFIX\",\"hours\":1,\"minutes\":15,\"logged_date\":\"$TODAY\",\"description\":\"Extended curl timelog\",\"is_billable\":true}")
TIMELOG_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
assert_api "POST /api/v1/time-logs → 201 creates time log for extended checks" "201" "$RESPONSE"

assert_api "GET /api/v1/time-logs/search → 200 searches time logs" "200" "$(api_get "/time-logs/search?query=Extended")"
assert_api "GET /api/v1/time-logs/project/{projectId} → 200 logs by project" "200" "$(api_get "/time-logs/project/$PROJECT_ID")"
assert_api "GET /api/v1/time-logs/project/{projectId}/total-hours → 200 project total hours" "200" "$(api_get "/time-logs/project/$PROJECT_ID/total-hours")"
assert_api "GET /api/v1/time-logs/project/{projectId}/billable-hours → 200 project billable hours" "200" "$(api_get "/time-logs/project/$PROJECT_ID/billable-hours")"
assert_api "GET /api/v1/time-logs/task/{taskId}/total-hours → 200 task total hours" "200" "$(api_get "/time-logs/task/$TASK_ID/total-hours")"
assert_api "GET /api/v1/time-logs/user/{userId}/total-hours → 200 user total hours" "200" "$(api_get "/time-logs/user/$USER_ID/total-hours")"

RESPONSE=$(api_json POST "/time-logs/start" "{\"task_id\":\"$TASK_ID\",\"description\":\"Started by curl suite\"}")
ACTIVE_TIMELOG_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
assert_api "POST /api/v1/time-logs/start → 201 starts timer" "201" "$RESPONSE"
if [ -n "$ACTIVE_TIMELOG_ID" ]; then
    assert_api "POST /api/v1/time-logs/stop → 200 stops timer" "200" "$(api_json POST "/time-logs/stop" "{\"time_log_id\":\"$ACTIVE_TIMELOG_ID\"}")"
fi

[ -n "${ACTIVE_TIMELOG_ID:-}" ] && api_delete "/time-logs/$ACTIVE_TIMELOG_ID" >/dev/null || true
[ -n "${TIMELOG_ID:-}" ] && assert_api "DELETE /api/v1/time-logs/{timeLog} → 200 deletes extended time log" "200" "$(api_delete "/time-logs/$TIMELOG_ID")"

echo ""; echo "=========================================="; echo "Notification Extended APIs"; echo "=========================================="
NOTIFICATION_ID=$($PHP_BIN artisan tinker --execute="
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Modules\User\Models\User;

\$id = (string) Str::uuid();
DB::table('notifications')->insert([
    'id' => \$id,
    'type' => 'api.test.notification',
    'notifiable_type' => User::class,
    'notifiable_id' => '$USER_ID',
    'data' => json_encode(['message' => 'API notification test']),
    'read_at' => null,
    'created_at' => now(),
    'updated_at' => now(),
]);
echo \$id;
" 2>/dev/null | tail -1)

assert_api "GET /api/v1/notification-preferences/types → 200 preference types" "200" "$(api_get "/notification-preferences/types")"
assert_api "POST /api/v1/notification-preferences/create-defaults → 200 creates defaults" "200" "$(api_json POST "/notification-preferences/create-defaults" '{}')"
assert_api "GET /api/v1/notifications?unread=true → 200 unread notifications" "200" "$(api_get "/notifications?unread=true")"
if [ -n "$NOTIFICATION_ID" ]; then
    assert_api "POST /api/v1/notifications/{id}/mark-read → 200 marks notification read" "200" "$(api_json POST "/notifications/$NOTIFICATION_ID/mark-read" '{}')"
fi
assert_api "POST /api/v1/notifications/mark-all-read → 200 marks all read" "200" "$(api_json POST "/notifications/mark-all-read" '{}')"
if [ -n "$NOTIFICATION_ID" ]; then
    assert_api "DELETE /api/v1/notifications/{id} → 200 deletes notification" "200" "$(api_delete "/notifications/$NOTIFICATION_ID")"
fi

cleanup_common_records
print_summary_and_exit
