#!/bin/bash

# Analytics Export API Test Suite
#
# Verifies the server-side Excel export endpoint
#   GET /api/v1/analytics/export
# works on its own AND keeps working while a long-lived SSE stream
#   GET /api/v1/analytics/stream
# is held open concurrently.
#
# The concurrent case is the regression this suite guards: the dashboard opens
# a long-lived SSE connection that pins a PHP worker for its lifetime. If the
# dev server runs with a single worker, the export request queues behind the
# stream and the browser reports a "Network Error" / interrupted connection.
# Running the server with PHP_CLI_SERVER_WORKERS>=2 lets both be served.
#
# Usage:
#   ./test-analytics-export-api.sh
#   BASE_URL="http://127.0.0.1:8000/api/v1" ./test-analytics-export-api.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

# Root URL (without the /api/v1 suffix) for building absolute export/stream URLs.
ROOT_URL="${BASE_URL%/api/v1}"
EXPORT_URL="$BASE_URL/analytics/export"
STREAM_URL="$BASE_URL/analytics/stream"

XLSX_ACCEPT="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
OUT_DIR="${OUT_DIR:-/tmp/api-test-analytics-export}"
mkdir -p "$OUT_DIR"

echo "=========================================="
echo "Analytics Export API Test Suite"
echo "=========================================="
echo " Base URL : $BASE_URL"
echo " Output   : $OUT_DIR"
echo ""

# Setup: login + provision a workspace/project/section/column/tasks/time-logs so
# every export sheet has real rows to render.
echo "Setting up test environment..."
login_admin
create_workspace "export"
create_project "export"
create_section "export"
create_column "export"
create_task "export-a" TASK_ID
create_task "export-b" TASK_ID_2

# A couple of time logs so the Time Logs / Top Performers sheets fill.
if [ -n "${TASK_ID:-}" ]; then
    NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    START_ISO=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-1H +%Y-%m-%dT%H:%M:%SZ)
    api_json POST "/time-logs" "{\"task_id\":\"$TASK_ID\",\"start_time\":\"$START_ISO\",\"end_time\":\"$NOW_ISO\",\"description\":\"Export log\",\"is_billable\":true}" > /dev/null || true
fi
echo ""

# ─── Helpers ────────────────────────────────────────────────────────────────

# Download an export and assert it is a valid, non-empty xlsx (PK zip magic).
# $1 = test name, $2 = output file, $3.. = extra --data-urlencode "k=v" pairs
assert_export_xlsx() {
    local name="$1"; shift
    local out="$1"; shift
    local args=()
    local kv
    for kv in "$@"; do
        args+=(--data-urlencode "$kv")
    done

    local code
    code=$(curl -s -G "$EXPORT_URL" \
        "${args[@]}" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Accept: $XLSX_ACCEPT" \
        -o "$out" -w '%{http_code}' --max-time 30 || echo "000")

    TOTAL=$((TOTAL + 1))
    local magic=""
    [ -s "$out" ] && magic="$(head -c 2 "$out")"

    if [ "$code" = "200" ] && [ "$magic" = "PK" ]; then
        echo -e "${GREEN}✓${NC} $name (HTTP 200, valid xlsx, $(wc -c < "$out" | tr -d ' ') bytes)"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗${NC} $name (HTTP $code, magic='$magic')"
        [ -s "$out" ] && echo "   Body: $(head -c 200 "$out")"
        FAILED=$((FAILED + 1))
        FAILED_TESTS+=("$name")
    fi
}

# ─── 1. Baseline exports (no concurrent stream) ───────────────────────────────
echo "--- Baseline exports ---"

END_DATE="$(date +%Y-%m-%d)"
START_DATE="$(date -d '30 days ago' +%Y-%m-%d 2>/dev/null || date -v-30d +%Y-%m-%d)"

assert_export_xlsx "Export: all sheets (default)" "$OUT_DIR/all-default.xlsx"
assert_export_xlsx "Export: date-range filtered" "$OUT_DIR/date-range.xlsx" \
    "start_date=$START_DATE" "end_date=$END_DATE"
assert_export_xlsx "Export: summary sheet only" "$OUT_DIR/summary-only.xlsx" \
    "sheets=summary"

# ─── 2. Validation ────────────────────────────────────────────────────────────
echo ""
echo "--- Validation ---"

# start_date after end_date should 422
RESPONSE=$(curl -sk -w "\n%{http_code}" -G "$EXPORT_URL" \
    --data-urlencode "start_date=$END_DATE" \
    --data-urlencode "end_date=$START_DATE" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/json")
assert_api "Export: invalid date range → 422" "422" "$RESPONSE"

# project scope without project_id should 422
RESPONSE=$(curl -sk -w "\n%{http_code}" -G "$EXPORT_URL" \
    --data-urlencode "scope=project" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/json")
assert_api "Export: project scope without project_id → 422" "422" "$RESPONSE"

# user scope without user_id should 422
RESPONSE=$(curl -sk -w "\n%{http_code}" -G "$EXPORT_URL" \
    --data-urlencode "scope=user" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/json")
assert_api "Export: user scope without user_id → 422" "422" "$RESPONSE"

# user scope WITH a valid user_id should succeed (the bug: the UI sent scope=user
# with no user_id, producing a 422). With a user_id it must return a valid xlsx.
assert_export_xlsx "Export: user scope with user_id" "$OUT_DIR/user-report.xlsx" \
    "scope=user" "user_id=$USER_ID"

# project scope WITH a valid project_id should succeed.
if [ -n "${PROJECT_ID:-}" ]; then
    assert_export_xlsx "Export: project scope with project_id" "$OUT_DIR/project-report.xlsx" \
        "scope=project" "project_id=$PROJECT_ID"
fi

# unauthenticated should be rejected (302 redirect to login, or 401)
RESPONSE=$(curl -sk -w "\n%{http_code}" -G "$EXPORT_URL" -H "Accept: application/json")
assert_api "Export: unauthenticated → 401" "401 302" "$RESPONSE"

# ─── 3. Export WHILE an SSE stream is held open (the regression) ──────────────
echo ""
echo "--- Export concurrent with a live SSE stream ---"

# Open the SSE stream in the background; it uses ?_token= because EventSource
# can't send Authorization headers. Hold it open for the duration of the export.
curl -s -N -G "$STREAM_URL" \
    --data-urlencode "type=individual" \
    --data-urlencode "_token=$TOKEN" \
    -o "$OUT_DIR/stream.out" --max-time 25 >/dev/null 2>&1 &
STREAM_PID=$!

# Give the stream a moment to connect and pin a worker.
sleep 2

# This export must succeed even though the stream is still open. On a
# single-worker server it would hang until the curl --max-time fires (HTTP 000).
assert_export_xlsx "Export succeeds while SSE stream is open" "$OUT_DIR/concurrent.xlsx"

# Tear the stream down.
kill "$STREAM_PID" 2>/dev/null || true
wait "$STREAM_PID" 2>/dev/null || true

# Confirm the stream actually delivered at least one event (it wasn't starved
# either).
TOTAL=$((TOTAL + 1))
if grep -q "analytics.update" "$OUT_DIR/stream.out" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} SSE stream delivered at least one analytics.update event"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗${NC} SSE stream delivered no events"
    FAILED=$((FAILED + 1))
    FAILED_TESTS+=("SSE stream delivered at least one analytics.update event")
fi

# Cleanup
cleanup_common_records

print_summary_and_exit
