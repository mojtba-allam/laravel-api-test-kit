#!/bin/bash

# Finolo Task Required Skills API Test Suite
# Tests all Task Required Skills endpoints with real database records

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

# Helper function to print test results
print_result() {
    local test_name="$1"
    local expected_status="$2"
    local actual_status="$3"
    local response="$4"
    
    TOTAL=$((TOTAL + 1))
    
    if [ "$actual_status" -eq "$expected_status" ]; then
        echo -e "${GREEN}✓${NC} $test_name (HTTP $actual_status)"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗${NC} $test_name (Expected: $expected_status, Got: $actual_status)"
        echo "   Response: $(echo "$response" | head -c 200)"
        FAILED=$((FAILED + 1))
        FAILED_TESTS+=("$test_name")
    fi
}

# Helper function to extract JSON value
json_value() {
    echo "$1" | grep -o "\"$2\":[^,}]*" | sed 's/"[^"]*"://;s/"//g;s/}//g' | head -1
}

echo "=========================================="
echo "Task Required Skills API Test Suite"
echo "=========================================="
echo ""

# Setup: mint a fresh authenticated admin user
echo "Setting up test environment..."

login_admin

# Create a skill for testing
SKILL_NAME="TestSkill-$(date +%s)"
SKILL_RESPONSE=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/skills" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"$SKILL_NAME\",
        \"category\": \"Testing\",
        \"description\": \"Test skill\"
    }")
SKILL_ID=$(json_value "$(echo "$SKILL_RESPONSE" | sed '$d')" "id")

# Get a task ID from existing tasks
TASKS_RESPONSE=$(curl -sk -X GET "$BASE_URL/tasks" \
    -H "Authorization: Bearer $TOKEN")
TASK_ID=$(echo "$TASKS_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | sed 's/"id":"//;s/"//')

if [ -z "$TASK_ID" ]; then
    echo -e "${RED}No tasks found in database${NC}"
    exit 1
fi

echo "✓ Test environment ready"
echo "✓ Auth token obtained"
echo "✓ Test skill created: $SKILL_ID"
echo "✓ Using task: $TASK_ID"
echo ""

# ==========================================
# Section 10E: Task Required Skills Tests
# ==========================================
echo "=========================================="
echo "10E: Task Required Skills API Tests"
echo "=========================================="
echo ""

# Test: POST /api/v1/tasks/{taskId}/required-skills - Add required skill
RESPONSE=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/tasks/$TASK_ID/required-skills" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"skill_id\": \"$SKILL_ID\",
        \"required_proficiency_level\": \"intermediate\",
        \"is_mandatory\": true
    }")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
TASK_REQUIRED_SKILL_ID=$(json_value "$BODY" "id")
print_result "POST /api/v1/tasks/{taskId}/required-skills → 201 adds required skill" 201 "$STATUS" "$BODY"

# Test: GET /api/v1/tasks/{taskId}/required-skills - List task's required skills
RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/tasks/$TASK_ID/required-skills" \
    -H "Authorization: Bearer $TOKEN")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
print_result "GET /api/v1/tasks/{taskId}/required-skills → 200 task's required skills" 200 "$STATUS" "$BODY"

# Test: GET /api/v1/tasks/{taskId}/required-skills/mandatory - Get mandatory skills
RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/tasks/$TASK_ID/required-skills/mandatory" \
    -H "Authorization: Bearer $TOKEN")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
print_result "GET /api/v1/tasks/{taskId}/required-skills/mandatory → 200 mandatory skills" 200 "$STATUS" "$BODY"

# Test: GET /api/v1/tasks/{taskId}/required-skills/suggest-assignees - Suggest assignees
RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/tasks/$TASK_ID/required-skills/suggest-assignees" \
    -H "Authorization: Bearer $TOKEN")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
print_result "GET /api/v1/tasks/{taskId}/required-skills/suggest-assignees → 200 suggested assignees" 200 "$STATUS" "$BODY"

# Get admin user ID for qualification check
ADMIN_USER_ID="$USER_ID"

# Test: GET /api/v1/tasks/{taskId}/required-skills/check-qualification/{userId} - Check qualification
RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/tasks/$TASK_ID/required-skills/check-qualification/$ADMIN_USER_ID" \
    -H "Authorization: Bearer $TOKEN")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
print_result "GET /api/v1/tasks/{taskId}/required-skills/check-qualification/{userId} → 200 qualification check" 200 "$STATUS" "$BODY"

# Test: GET /api/v1/task-required-skills/{id} - Show task required skill
if [ -n "$TASK_REQUIRED_SKILL_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/task-required-skills/$TASK_REQUIRED_SKILL_ID" \
        -H "Authorization: Bearer $TOKEN")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "GET /api/v1/task-required-skills/{id} → 200 detail" 200 "$STATUS" "$BODY"
fi

# Test: PUT /api/v1/task-required-skills/{id} - Update task required skill
if [ -n "$TASK_REQUIRED_SKILL_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X PUT "$BASE_URL/task-required-skills/$TASK_REQUIRED_SKILL_ID" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "required_proficiency_level": "advanced",
            "is_mandatory": false
        }')
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "PUT /api/v1/task-required-skills/{id} → 200 update" 200 "$STATUS" "$BODY"
fi

# Test: DELETE /api/v1/task-required-skills/{id} - Delete task required skill
if [ -n "$TASK_REQUIRED_SKILL_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X DELETE "$BASE_URL/task-required-skills/$TASK_REQUIRED_SKILL_ID" \
        -H "Authorization: Bearer $TOKEN")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "DELETE /api/v1/task-required-skills/{id} → 200 delete" 200 "$STATUS" "$BODY"
fi

echo ""

# ==========================================
# Summary
# ==========================================
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "Total:  $TOTAL"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed tests:${NC}"
    for test in "${FAILED_TESTS[@]}"; do
        echo "  - $test"
    done
    echo ""
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
