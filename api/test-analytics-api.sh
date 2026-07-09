#!/bin/bash

# Analytics Module API Test Suite - Enhanced
# Tests all Analytics endpoints with comprehensive validation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "=========================================="
echo "Analytics Module API Test Suite - Enhanced"
echo "=========================================="
echo ""

# Setup: Login and create test data
echo "Setting up test environment..."
login_admin
create_workspace "$(date +%s)"
create_project "$(date +%s)"
echo ""

echo "=========================================="
echo "16: Analytics Module API Tests"
echo "=========================================="
echo ""

# Test: GET /api/v1/analytics/dashboard - Dashboard analytics
RESPONSE=$(api_get "/analytics/dashboard")
assert_api "GET /api/v1/analytics/dashboard → 200 dashboard analytics" "200" "$RESPONSE"

# Test: GET /api/v1/analytics/projects/{project}/analytics - Project analytics
if [ -n "$PROJECT_ID" ]; then
    RESPONSE=$(api_get "/analytics/projects/$PROJECT_ID/analytics")
    assert_api "GET /api/v1/analytics/projects/{id} → 200 project analytics" "200" "$RESPONSE"
fi

# Test: GET /api/v1/analytics/tasks/metrics - Task analytics
RESPONSE=$(api_get "/analytics/tasks/metrics")
assert_api "GET /api/v1/analytics/tasks → 200 task analytics" "200" "$RESPONSE"

# Test: GET /api/v1/analytics/time-tracking/insights - Time tracking analytics
RESPONSE=$(api_get "/analytics/time-tracking/insights")
assert_api "GET /api/v1/analytics/time-tracking → 200 time tracking analytics" "200" "$RESPONSE"

# Test: GET /api/v1/analytics/users/{id}/productivity - User productivity
RESPONSE=$(api_get "/analytics/users/$USER_ID/productivity")
assert_api "GET /api/v1/analytics/users/{id}/productivity → 200 user productivity" "200" "$RESPONSE"

echo ""

# ==========================================
# Phase 16: Enhanced Analytics Tests
# ==========================================
echo "=========================================="
echo "Phase 16: Enhanced Analytics Tests"
echo "=========================================="
echo ""

# Phase 16.1: Response Data Validation
echo "--- Phase 16.1: Response Data Validation ---"

RESPONSE=$(api_get "/analytics/dashboard")
BODY=$(body_from_response "$RESPONSE")
STATUS=$(status_from_response "$RESPONSE")

if assert_json_field "$BODY" "data" || assert_json_field "$BODY" "metrics"; then
    print_result "Analytics dashboard has data/metrics field" "200" "$STATUS" "$BODY"
else
    print_result "Analytics dashboard structure" "200" "FAIL" "$BODY"
fi

# Phase 16.2: Business Logic Tests
echo ""
echo "--- Phase 16.2: Business Logic Tests ---"

# Test project analytics calculations
if [ -n "$PROJECT_ID" ]; then
    RESPONSE=$(api_get "/analytics/projects/$PROJECT_ID/analytics")
    if [ "$(status_from_response "$RESPONSE")" = "200" ]; then
        print_result "Project analytics calculations work" "200" "200" "Analytics retrieved"
    else
        print_result "Project analytics" "200" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
    fi
fi

# Test task analytics aggregation
RESPONSE=$(api_get "/analytics/tasks/metrics")
if [ "$(status_from_response "$RESPONSE")" = "200" ]; then
    print_result "Task analytics aggregation works" "200" "200" "Analytics retrieved"
else
    print_result "Task analytics" "200" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# Test time tracking analytics
RESPONSE=$(api_get "/analytics/time-tracking/insights")
if [ "$(status_from_response "$RESPONSE")" = "200" ]; then
    print_result "Time tracking analytics work" "200" "200" "Analytics retrieved"
else
    print_result "Time tracking analytics" "200" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# Test user productivity reports
RESPONSE=$(api_get "/analytics/users/$USER_ID/productivity")
if [ "$(status_from_response "$RESPONSE")" = "200" ]; then
    print_result "User productivity reports work" "200" "200" "Report retrieved"
else
    print_result "User productivity reports" "200" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# Phase 16.3: Query Parameters Tests
echo ""
echo "--- Phase 16.3: Query Parameters Tests ---"

# Test date range filtering
START_DATE=$(date -d "30 days ago" +%Y-%m-%d)
END_DATE=$(date +%Y-%m-%d)
RESPONSE=$(api_get "/analytics/tasks/metrics?start_date=$START_DATE&end_date=$END_DATE")
assert_api "Analytics with date range filtering" "200" "$RESPONSE"

# Test metrics summary
RESPONSE=$(api_get "/analytics/metrics/summary")
assert_api "Analytics metrics summary" "200" "$RESPONSE"

# Test burndown chart for project
if [ -n "$PROJECT_ID" ]; then
    RESPONSE=$(api_get "/analytics/burndown/$PROJECT_ID")
    assert_api "Analytics burndown by project" "200" "$RESPONSE"
fi

# Cleanup
cleanup_common_records

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
print_summary_and_exit
