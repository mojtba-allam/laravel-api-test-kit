#!/bin/bash
# Sections 10U-10V: TimeLog and Notification Module API Tests
set -e
BASE_URL="http://127.0.0.1:8000/api/v1"
PASSED=0; FAILED=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
declare -a FAILED_TESTS=()

print_result() {
    TOTAL=$((TOTAL + 1))
    if [ "$3" -eq "$2" ]; then echo -e "${GREEN}✓${NC} $1 (HTTP $3)"; PASSED=$((PASSED + 1))
    else echo -e "${RED}✗${NC} $1 (Expected: $2, Got: $3)"; echo "   Response: $(echo "$4" | head -c 200)"; FAILED=$((FAILED + 1)); FAILED_TESTS+=("$1"); fi
}

json_value() { echo "$1" | grep -o "\"$2\":[^,}]*" | sed 's/"[^"]*"://;s/"//g;s/}//g' | head -1; }

echo "=========================================="; echo "TimeLog & Notification API Tests"; echo "=========================================="
LOGIN_RESPONSE=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/auth/login" -H "Content-Type: application/json" -d '{"email": "$SEED_ADMIN_EMAIL", "password": "password"}')
TOKEN=$(json_value "$(echo "$LOGIN_RESPONSE" | sed '$d')" "token")
USER_ID=$(json_value "$(echo "$LOGIN_RESPONSE" | sed '$d')" "id")
echo "✓ Auth token obtained"; echo ""

# Get task ID
TASKS_RESPONSE=$(curl -sk -X GET "$BASE_URL/tasks" -H "Authorization: Bearer $TOKEN")
TASK_ID=$($PHP_BIN artisan tinker --execute="echo \Modules\Task\Models\Task::whereHas('column.section.project')->latest()->value('id');" 2>/dev/null | tail -1)
[ -z "$TASK_ID" ] && TASK_ID=$(echo "$TASKS_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | sed 's/"id":"//;s/"//')
TASK_NAME=$($PHP_BIN artisan tinker --execute="\$task = \Modules\Task\Models\Task::find('$TASK_ID'); echo \$task?->title ?? 'API Task';" 2>/dev/null | tail -1)
PROJECT_ID=$($PHP_BIN artisan tinker --execute="\$task = \Modules\Task\Models\Task::find('$TASK_ID'); \$project = \$task?->getProject(); echo \$project?->id ?? '';" 2>/dev/null | tail -1)
PROJECT_NAME=$($PHP_BIN artisan tinker --execute="\$task = \Modules\Task\Models\Task::find('$TASK_ID'); \$project = \$task?->getProject(); echo \$project?->name ?? 'API Project';" 2>/dev/null | tail -1)

echo "=========================================="; echo "10U: Time Log Module"; echo "=========================================="

RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/time-logs" -H "Authorization: Bearer $TOKEN")
print_result "GET /api/v1/time-logs → 200 paginated time log list" 200 "$(echo "$RESPONSE" | tail -1)" "$(echo "$RESPONSE" | sed '$d')"

RESPONSE=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/time-logs" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "{\"task_id\": \"$TASK_ID\", \"task_name\": \"$TASK_NAME\", \"project_id\": \"$PROJECT_ID\", \"project_name\": \"$PROJECT_NAME\", \"hours\": 2, \"minutes\": 30, \"logged_date\": \"$(date +%Y-%m-%d)\", \"description\": \"Test work\"}")
TIMELOG_ID=$(json_value "$(echo "$RESPONSE" | sed '$d')" "id")
print_result "POST /api/v1/time-logs → 201 creates time log" 201 "$(echo "$RESPONSE" | tail -1)" "$(echo "$RESPONSE" | sed '$d')"

if [ -n "$TIMELOG_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/time-logs/$TIMELOG_ID" -H "Authorization: Bearer $TOKEN")
    print_result "GET /api/v1/time-logs/{timeLog} → 200 time log details" 200 "$(echo "$RESPONSE" | tail -1)" "$(echo "$RESPONSE" | sed '$d')"
    
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X PUT "$BASE_URL/time-logs/$TIMELOG_ID" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"hours": 3, "minutes": 0}')
    print_result "PUT /api/v1/time-logs/{timeLog} → 200 updates time log" 200 "$(echo "$RESPONSE" | tail -1)" "$(echo "$RESPONSE" | sed '$d')"
    
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X DELETE "$BASE_URL/time-logs/$TIMELOG_ID" -H "Authorization: Bearer $TOKEN")
    print_result "DELETE /api/v1/time-logs/{timeLog} → 200 deletes time log" 200 "$(echo "$RESPONSE" | tail -1)" "$(echo "$RESPONSE" | sed '$d')"
fi

RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/time-logs/active" -H "Authorization: Bearer $TOKEN")
print_result "GET /api/v1/time-logs/active → 200 active timers" 200 "$(echo "$RESPONSE" | tail -1)" "$(echo "$RESPONSE" | sed '$d')"

RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/time-logs/summary" -H "Authorization: Bearer $TOKEN")
print_result "GET /api/v1/time-logs/summary → 200 summary data" 200 "$(echo "$RESPONSE" | tail -1)" "$(echo "$RESPONSE" | sed '$d')"

if [ -n "$TASK_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/time-logs/task/$TASK_ID" -H "Authorization: Bearer $TOKEN")
    print_result "GET /api/v1/time-logs/task/{taskId} → 200 logs by task" 200 "$(echo "$RESPONSE" | tail -1)" "$(echo "$RESPONSE" | sed '$d')"
fi

if [ -n "$USER_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/time-logs/user/$USER_ID" -H "Authorization: Bearer $TOKEN")
    print_result "GET /api/v1/time-logs/user/{userId} → 200 logs by user" 200 "$(echo "$RESPONSE" | tail -1)" "$(echo "$RESPONSE" | sed '$d')"
fi

echo ""; echo "=========================================="; echo "10V: Notification Module"; echo "=========================================="

RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/notifications" -H "Authorization: Bearer $TOKEN")
print_result "GET /api/v1/notifications → 200 paginated notifications" 200 "$(echo "$RESPONSE" | tail -1)" "$(echo "$RESPONSE" | sed '$d')"

RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/notifications/unread-count" -H "Authorization: Bearer $TOKEN")
print_result "GET /api/v1/notifications/unread-count → 200 unread count" 200 "$(echo "$RESPONSE" | tail -1)" "$(echo "$RESPONSE" | sed '$d')"

RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/notification-preferences" -H "Authorization: Bearer $TOKEN")
print_result "GET /api/v1/notification-preferences → 200 user preferences" 200 "$(echo "$RESPONSE" | tail -1)" "$(echo "$RESPONSE" | sed '$d')"

RESPONSE=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/notification-preferences" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"notification_type": "task_assigned", "email_enabled": true, "in_app_enabled": true}')
print_result "POST /api/v1/notification-preferences → 200 updates preferences" 200 "$(echo "$RESPONSE" | tail -1)" "$(echo "$RESPONSE" | sed '$d')"

echo ""; echo "=========================================="; echo "Test Summary"; echo "=========================================="
echo -e "Total:  $TOTAL"; echo -e "${GREEN}Passed: $PASSED${NC}"; echo -e "${RED}Failed: $FAILED${NC}"; echo ""
if [ $FAILED -gt 0 ]; then echo -e "${RED}Failed tests:${NC}"; for test in "${FAILED_TESTS[@]}"; do echo "  - $test"; done; exit 1
else echo -e "${GREEN}All tests passed!${NC}"; exit 0; fi
