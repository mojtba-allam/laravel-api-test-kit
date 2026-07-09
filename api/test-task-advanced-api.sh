#!/bin/bash
# Sections 10J-10O plus remaining 10H task actions
set -e

source "$(dirname "$0")/api-test-helpers.sh"

echo "=========================================="
echo "Task Advanced API Tests"
echo "=========================================="
login_admin
echo ""

SUFFIX="$(date +%s)"
create_workspace "$SUFFIX"
create_project "$SUFFIX"
create_section "$SUFFIX"
create_column "$SUFFIX"
create_task "$SUFFIX-a" TASK_ID
create_task "$SUFFIX-b" TASK_ID_2
create_task "$SUFFIX-c" TASK_ID_3

echo "✓ Test board created: $PROJECT_ID"
echo ""

echo "=========================================="; echo "10H: Remaining Task Actions"; echo "=========================================="
assert_api "GET /api/v1/tasks/column/{columnId} → 200 tasks by column" "200" "$(api_get "/tasks/column/$COLUMN_ID")"
assert_api "GET /api/v1/tasks/status/{status} → 200 tasks by status" "200" "$(api_get "/tasks/status/open")"
assert_api "POST /api/v1/tasks/{id}/move → 200 moves task to another column" "200" "$(api_json POST "/tasks/$TASK_ID/move" "{\"column_id\":\"$COLUMN_ID\",\"sort_order\":5}")"
assert_api "POST /api/v1/tasks/{id}/block → 200 blocks task" "200" "$(api_json POST "/tasks/$TASK_ID/block" '{"reason":"API test block"}')"
assert_api "POST /api/v1/tasks/{id}/unblock → 200 unblocks task" "200" "$(api_json POST "/tasks/$TASK_ID/unblock" '{}')"
assert_api "PATCH /api/v1/tasks/{id} → 200 partially updates task" "200" "$(api_json PATCH "/tasks/$TASK_ID" '{"description":"Patched by API test"}')"

echo ""; echo "=========================================="; echo "10J: Task Dependencies"; echo "=========================================="
assert_api "GET /api/v1/task-dependencies → 200 all dependencies" "200" "$(api_get "/task-dependencies?task_id=$TASK_ID")"
RESPONSE=$(api_json POST "/task-dependencies" "{\"task_id\":\"$TASK_ID\",\"depends_on_task_id\":\"$TASK_ID_2\",\"dependency_type\":\"blocks\",\"lag_days\":1}")
DEPENDENCY_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
assert_api "POST /api/v1/task-dependencies → 201 creates dependency" "201" "$RESPONSE"
if [ -n "$DEPENDENCY_ID" ]; then
    assert_api "GET /api/v1/task-dependencies/{id} → 200 dependency details" "200" "$(api_get "/task-dependencies/$DEPENDENCY_ID")"
    assert_api "PUT /api/v1/task-dependencies/{id} → 200 updates dependency" "200" "$(api_json PUT "/task-dependencies/$DEPENDENCY_ID" '{"dependency_type":"relates_to","lag_days":2}')"
fi
assert_api "GET /api/v1/tasks/{taskId}/dependencies/blocking → 200 blocking dependencies" "200" "$(api_get "/tasks/$TASK_ID/dependencies/blocking")"
assert_api "GET /api/v1/tasks/{taskId}/dependencies/blocked-by → 200 blocked-by dependencies" "200" "$(api_get "/tasks/$TASK_ID/dependencies/blocked-by")"
assert_api "GET /api/v1/tasks/{taskId}/dependencies/related → 200 related dependencies" "200" "$(api_get "/tasks/$TASK_ID/dependencies/related")"
assert_api "GET /api/v1/tasks/{taskId}/dependencies/unresolved → 200 unresolved deps" "200" "$(api_get "/tasks/$TASK_ID/dependencies/unresolved")"
assert_api "GET /api/v1/tasks/{taskId}/dependencies/graph → 200 dependency graph" "200" "$(api_get "/tasks/$TASK_ID/dependencies/graph")"
if [ -n "$DEPENDENCY_ID" ]; then
    assert_api "DELETE /api/v1/task-dependencies/{id} → 200 deletes dependency" "200" "$(api_delete "/task-dependencies/$DEPENDENCY_ID")"
fi

echo ""; echo "=========================================="; echo "10K: Task Relationships"; echo "=========================================="
assert_api "GET /api/v1/tasks/{taskId}/relationships → 200 task relationships" "200" "$(api_get "/tasks/$TASK_ID/relationships")"
RESPONSE=$(api_json POST "/tasks/$TASK_ID/relationships" "{\"related_task_id\":\"$TASK_ID_2\",\"relationship_type\":\"related_to\",\"description\":\"API related task\"}")
RELATIONSHIP_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
assert_api "POST /api/v1/tasks/{taskId}/relationships → 201 creates relationship" "201" "$RESPONSE"
if [ -n "$RELATIONSHIP_ID" ]; then
    assert_api "GET /api/v1/task-relationships/{relationship} → 200 relationship details" "200" "$(api_get "/task-relationships/$RELATIONSHIP_ID")"
    assert_api "PUT /api/v1/task-relationships/{relationship} → 200 updates relationship" "200" "$(api_json PUT "/task-relationships/$RELATIONSHIP_ID" '{"description":"Updated relationship"}')"
fi
for path in graph duplicates duplicated-by references related related-tasks; do
    assert_api "GET /api/v1/tasks/{taskId}/relationships/$path → 200" "200" "$(api_get "/tasks/$TASK_ID/relationships/$path")"
done
if [ -n "$RELATIONSHIP_ID" ]; then
    assert_api "DELETE /api/v1/task-relationships/{relationship} → 200 deletes relationship" "200" "$(api_delete "/task-relationships/$RELATIONSHIP_ID")"
fi

echo ""; echo "=========================================="; echo "10L: Task Hierarchy"; echo "=========================================="
assert_api "GET /api/v1/tasks/{taskId}/parent → 200 parent task" "200" "$(api_get "/tasks/$TASK_ID_2/parent")"
assert_api "GET /api/v1/tasks/{taskId}/children → 200 child tasks" "200" "$(api_get "/tasks/$TASK_ID/children")"
assert_api "POST /api/v1/tasks/{parentTaskId}/children → 201 adds child task" "201" "$(api_json POST "/tasks/$TASK_ID/children" "{\"child_task_id\":\"$TASK_ID_2\",\"sort_order\":1}")"
assert_api "GET /api/v1/tasks/{taskId}/descendants → 200 all descendants" "200" "$(api_get "/tasks/$TASK_ID/descendants")"
assert_api "GET /api/v1/tasks/{taskId}/ancestors → 200 all ancestors" "200" "$(api_get "/tasks/$TASK_ID_2/ancestors")"
assert_api "GET /api/v1/tasks/{taskId}/tree → 200 task tree" "200" "$(api_get "/tasks/$TASK_ID/tree")"
assert_api "GET /api/v1/tasks/{taskId}/progress → 200 hierarchy progress" "200" "$(api_get "/tasks/$TASK_ID/progress")"
assert_api "POST /api/v1/tasks/{parentTaskId}/children/reorder → 200 reorders child tasks" "200" "$(api_json POST "/tasks/$TASK_ID/children/reorder" "{\"child_task_ids\":[\"$TASK_ID_2\"]}")"
assert_api "POST /api/v1/tasks/{childTaskId}/move-parent → 200 moves parent" "200" "$(api_json POST "/tasks/$TASK_ID_2/move-parent" "{\"new_parent_task_id\":\"$TASK_ID_3\",\"sort_order\":1}")"
assert_api "DELETE /api/v1/tasks/{parentTaskId}/children/{childTaskId} → 200 removes child" "200" "$(api_delete "/tasks/$TASK_ID_3/children/$TASK_ID_2")"

echo ""; echo "=========================================="; echo "10M: Task Templates"; echo "=========================================="
assert_api "GET /api/v1/task-templates → 200 all templates" "200" "$(api_get "/task-templates")"
assert_api "GET /api/v1/task-templates/most-used → 200 most used templates" "200" "$(api_get "/task-templates/most-used")"
assert_api "GET /api/v1/task-templates/public → 200 public templates" "200" "$(api_get "/task-templates/public")"
assert_api "GET /api/v1/projects/{projectId}/task-templates → 200 project templates" "200" "$(api_get "/projects/$PROJECT_ID/task-templates")"
assert_api "GET /api/v1/users/{userId}/task-templates → 200 user templates" "200" "$(api_get "/users/$USER_ID/task-templates")"
RESPONSE=$(api_json POST "/projects/$PROJECT_ID/task-templates" '{"name":"API Template","description":"Template from curl","priority":"medium","estimated_hours":2,"visibility":"private","checklist_templates":[{"title":"Template Checklist","items":[{"title":"Template Item"}]}]}')
TEMPLATE_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
assert_api "POST /api/v1/projects/{projectId}/task-templates → 201 creates template" "201" "$RESPONSE"
if [ -n "$TEMPLATE_ID" ]; then
    assert_api "GET /api/v1/task-templates/{id} → 200 template details" "200" "$(api_get "/task-templates/$TEMPLATE_ID")"
    assert_api "PUT /api/v1/task-templates/{id} → 200 updates template" "200" "$(api_json PUT "/task-templates/$TEMPLATE_ID" '{"name":"Updated API Template"}')"
    assert_api "POST /api/v1/task-templates/{templateId}/create-task → 201 creates task from template" "201" "$(api_json POST "/task-templates/$TEMPLATE_ID/create-task" "{\"column_id\":\"$COLUMN_ID\",\"title\":\"Task From Template\"}")"
    assert_api "POST /api/v1/task-templates/{templateId}/duplicate → 201 duplicates template" "201" "$(api_json POST "/task-templates/$TEMPLATE_ID/duplicate" '{}')"
fi

echo ""; echo "=========================================="; echo "10N: Custom Fields"; echo "=========================================="
assert_api "GET /api/v1/projects/{projectId}/custom-fields → 200 project custom fields" "200" "$(api_get "/projects/$PROJECT_ID/custom-fields")"
RESPONSE=$(api_json POST "/projects/$PROJECT_ID/custom-fields" '{"field_name":"API Text Field","field_type":"text","field_options":{"max_length":255},"is_required":false,"sort_order":1}')
FIELD_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
assert_api "POST /api/v1/projects/{projectId}/custom-fields → 201 creates custom field" "201" "$RESPONSE"
if [ -n "$FIELD_ID" ]; then
    assert_api "POST /api/v1/projects/{projectId}/custom-fields/reorder → 200 reorders fields" "200" "$(api_json POST "/projects/$PROJECT_ID/custom-fields/reorder" "{\"field_ids\":[\"$FIELD_ID\"]}")"
    assert_api "GET /api/v1/custom-fields/{id} → 200 field details" "200" "$(api_get "/custom-fields/$FIELD_ID")"
    assert_api "PUT /api/v1/custom-fields/{id} → 200 updates field" "200" "$(api_json PUT "/custom-fields/$FIELD_ID" '{"field_name":"Updated API Text Field"}')"
    assert_api "GET /api/v1/tasks/{taskId}/custom-field-values → 200 task field values" "200" "$(api_get "/tasks/$TASK_ID/custom-field-values")"
    assert_api "POST /api/v1/tasks/{taskId}/custom-field-values → 201 sets value" "201" "$(api_json POST "/tasks/$TASK_ID/custom-field-values" "{\"custom_field_id\":\"$FIELD_ID\",\"field_value\":\"hello\"}")"
    assert_api "POST /api/v1/tasks/{taskId}/custom-field-values/bulk → 200 sets values in bulk" "200" "$(api_json POST "/tasks/$TASK_ID/custom-field-values/bulk" "{\"values\":{\"$FIELD_ID\":\"bulk hello\"}}")"
    assert_api "DELETE /api/v1/tasks/{taskId}/custom-field-values/{fieldId} → 200 clears value" "200" "$(api_delete "/tasks/$TASK_ID/custom-field-values/$FIELD_ID")"
    assert_api "DELETE /api/v1/tasks/{taskId}/custom-field-values → 200 clears all values" "200" "$(api_delete "/tasks/$TASK_ID/custom-field-values")"
    assert_api "DELETE /api/v1/custom-fields/{id} → 200 deletes field" "200" "$(api_delete "/custom-fields/$FIELD_ID")"
fi

echo ""; echo "=========================================="; echo "10O: Recurring Tasks"; echo "=========================================="
RRULE='FREQ=DAILY;COUNT=3'
assert_api "POST /api/v1/recurring/validate-rrule → 200 validates rrule string" "200" "$(api_json POST "/recurring/validate-rrule" "{\"recurrence_rrule\":\"$RRULE\"}")"
assert_api "POST /api/v1/tasks/{taskId}/recurring/enable → 200 enables recurrence" "200" "$(api_json POST "/tasks/$TASK_ID/recurring/enable" "{\"recurrence_rrule\":\"$RRULE\"}")"
assert_api "GET /api/v1/tasks/{taskId}/recurring/occurrences → 200 occurrences preview" "200" "$(api_get "/tasks/$TASK_ID/recurring/occurrences")"
assert_api "GET /api/v1/tasks/{taskId}/recurring/instances → 200 recurring instances" "200" "$(api_get "/tasks/$TASK_ID/recurring/instances")"
assert_api "PUT /api/v1/tasks/{taskId}/recurring/rrule → 200 updates recurrence rule" "200" "$(api_json PUT "/tasks/$TASK_ID/recurring/rrule" '{"recurrence_rrule":"FREQ=WEEKLY;COUNT=2"}')"
assert_api "POST /api/v1/tasks/{taskId}/recurring/generate → hits generate instances endpoint" "200 201 422" "$(api_json POST "/tasks/$TASK_ID/recurring/generate" '{}')"
assert_api "POST /api/v1/tasks/{taskId}/recurring/disable → 200 disables recurrence" "200" "$(api_json POST "/tasks/$TASK_ID/recurring/disable" '{}')"

if [ -n "${TEMPLATE_ID:-}" ]; then
    assert_api "DELETE /api/v1/task-templates/{id} → 200 deletes template" "200" "$(api_delete "/task-templates/$TEMPLATE_ID")"
fi

cleanup_common_records
print_summary_and_exit
