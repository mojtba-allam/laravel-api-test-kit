#!/bin/bash
# Webhook and real-time notification API coverage
set -e

source "$(dirname "$0")/api-test-helpers.sh"

echo "=========================================="
echo "Webhook and Realtime API Tests"
echo "=========================================="
login_admin
echo ""

SUFFIX="$(date +%s)"
create_workspace "$SUFFIX"
create_project "$SUFFIX"
create_section "$SUFFIX"
create_column "$SUFFIX"
create_task "$SUFFIX" TASK_ID

echo "✓ Test project/task created: $PROJECT_ID / $TASK_ID"
echo ""

echo "=========================================="; echo "Webhook APIs"; echo "=========================================="
assert_api "GET /api/v1/webhook-events → 200 webhook events" "200" "$(api_get "/webhook-events")"
assert_api "GET /api/v1/webhooks → 200 webhook list" "200" "$(api_get "/webhooks")"
assert_api "GET /api/v1/projects/{projectId}/webhooks → 200 project webhooks" "200" "$(api_get "/projects/$PROJECT_ID/webhooks")"

RESPONSE=$(api_json POST "/projects/$PROJECT_ID/webhooks" "{\"project_id\":\"$PROJECT_ID\",\"name\":\"API Webhook $SUFFIX\",\"url\":\"https://example.com/webhook\",\"secret\":\"api-secret-$SUFFIX\",\"events\":[\"task.created\",\"task.updated\"],\"is_active\":true}")
WEBHOOK_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
assert_api "POST /api/v1/projects/{projectId}/webhooks → 201 creates webhook" "201" "$RESPONSE"

if [ -n "$WEBHOOK_ID" ]; then
    assert_api "GET /api/v1/webhooks/{id} → 200 webhook details" "200" "$(api_get "/webhooks/$WEBHOOK_ID")"
    assert_api "PUT /api/v1/webhooks/{id} → 200 updates webhook" "200" "$(api_json PUT "/webhooks/$WEBHOOK_ID" '{"name":"Updated API Webhook","events":["task.created"],"is_active":true}')"
    assert_api "POST /api/v1/webhooks/{id}/deactivate → 200 deactivates webhook" "200" "$(api_json POST "/webhooks/$WEBHOOK_ID/deactivate" '{}')"
    assert_api "POST /api/v1/webhooks/{id}/activate → 200 activates webhook" "200" "$(api_json POST "/webhooks/$WEBHOOK_ID/activate" '{}')"
    RESPONSE=$(api_json POST "/webhooks/$WEBHOOK_ID/test" '{}')
    DELIVERY_ID=$(json_value "$(body_from_response "$RESPONSE")" "delivery.id")
    assert_api "POST /api/v1/webhooks/{id}/test → 200 sends test webhook" "200" "$RESPONSE"
    assert_api "GET /api/v1/webhooks/{id}/deliveries → 200 webhook deliveries" "200" "$(api_get "/webhooks/$WEBHOOK_ID/deliveries")"
    if [ -n "$DELIVERY_ID" ]; then
        assert_api "POST /api/v1/webhook-deliveries/{deliveryId}/retry → 200 retries delivery" "200" "$(api_json POST "/webhook-deliveries/$DELIVERY_ID/retry" '{}')"
    fi
fi

echo ""; echo "=========================================="; echo "Realtime Notification APIs"; echo "=========================================="
assert_api "POST /api/v1/realtime-notifications/user-presence/online → 200 online" "200" "$(api_json POST "/realtime-notifications/user-presence/online" '{}')"
assert_api "POST /api/v1/realtime-notifications/user-typing/{taskId} → 200 user typing" "200" "$(api_json POST "/realtime-notifications/user-typing/$TASK_ID" '{}')"
assert_api "GET /api/v1/realtime-notifications/channels/auth → 200 global auth" "200" "$(api_get "/realtime-notifications/channels/auth?channel_name=presence.global")"
assert_api "GET /api/v1/realtime-notifications/channels/auth project → 200 project auth" "200" "$(api_get "/realtime-notifications/channels/auth?channel_name=project.$PROJECT_ID")"
assert_api "GET /api/v1/realtime-notifications/boards/{project}/presence → 200 board presence" "200" "$(api_get "/realtime-notifications/boards/$PROJECT_ID/presence")"
assert_api "POST /api/v1/realtime-notifications/boards/{project}/presence/heartbeat → 200 heartbeat" "200" "$(api_json POST "/realtime-notifications/boards/$PROJECT_ID/presence/heartbeat" '{}')"
assert_api "POST /api/v1/realtime-notifications/boards/{project}/typing → 200 board typing" "200" "$(api_json POST "/realtime-notifications/boards/$PROJECT_ID/typing" "{\"is_typing\":true,\"task_id\":\"$TASK_ID\",\"context\":\"board\"}")"
assert_api "DELETE /api/v1/realtime-notifications/boards/{project}/presence → 200 board offline" "200" "$(api_delete "/realtime-notifications/boards/$PROJECT_ID/presence")"
assert_api "POST /api/v1/realtime-notifications/user-presence/offline → 200 offline" "200" "$(api_json POST "/realtime-notifications/user-presence/offline" '{}')"

[ -n "${WEBHOOK_ID:-}" ] && assert_api "DELETE /api/v1/webhooks/{id} → 200 deletes webhook" "200" "$(api_delete "/webhooks/$WEBHOOK_ID")"

cleanup_common_records
print_summary_and_exit
