#!/bin/bash

# Interactive Import Project via JSON API
# Asks the user about project structure then generates, imports, and verifies.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "=========================================="
echo "  Project Import — Interactive Generator"
echo "=========================================="
echo ""
echo "This script will ask you about the project you want to build,"
echo "generate the JSON, import it via the API, and verify the result."
echo ""

# ==========================================
# Interactive Prompts
# ==========================================

read -rp "📋 Project name: " PROJECT_NAME
PROJECT_NAME="${PROJECT_NAME:-My Imported Project}"

read -rp "📝 Project description (optional): " PROJECT_DESC

read -rp "📌 Project status [active/inactive/completed/on_hold/archived] (default: active): " PROJECT_STATUS
PROJECT_STATUS="${PROJECT_STATUS:-active}"

read -rp "🗂️  Board type [kanban/list/tree/graph/calendar/timeline/scrum/custom] (default: kanban): " BOARD_TYPE
BOARD_TYPE="${BOARD_TYPE:-kanban}"

read -rp "👁️  Visibility [public/private/internal] (default: private): " VISIBILITY
VISIBILITY="${VISIBILITY:-private}"

echo ""
echo "--- Sections ---"
read -rp "🔢 How many sections? (default: 10): " NUM_SECTIONS
NUM_SECTIONS="${NUM_SECTIONS:-10}"

read -rp "📛 Section name pattern (use {n} for number, e.g. 'Sprint {n}'): " SECTION_PATTERN
SECTION_PATTERN="${SECTION_PATTERN:-Section {n}}"

echo ""
echo "--- Columns ---"
read -rp "🔢 How many columns per section? (default: 10): " NUM_COLUMNS
NUM_COLUMNS="${NUM_COLUMNS:-10}"

echo "Enter column names separated by commas (e.g. 'To Do,In Progress,Done')."
echo "If you provide fewer names than columns, the rest will be auto-numbered."
read -rp "📛 Column names: " COLUMN_NAMES_INPUT

# Parse column names into array
IFS=',' read -ra CUSTOM_COL_NAMES <<< "$COLUMN_NAMES_INPUT"

echo ""
echo "--- Tasks ---"
read -rp "🔢 How many tasks per column? (default: 1): " TASKS_PER_COLUMN
TASKS_PER_COLUMN="${TASKS_PER_COLUMN:-1}"

read -rp "📛 Task title pattern (use {n} for global number, e.g. 'Task {n}'): " TASK_PATTERN
TASK_PATTERN="${TASK_PATTERN:-Task {n}}"

read -rp "📌 Default task status for ALL tasks? [open/in_progress/completed/blocked/on_hold/cancelled/archived] (leave empty to cycle): " DEFAULT_STATUS

read -rp "🔥 Default task priority for ALL tasks? [low/medium/high/urgent] (leave empty to cycle): " DEFAULT_PRIORITY

read -rp "⏱️  Default estimated hours per task? (leave empty to cycle 1-8): " DEFAULT_HOURS

read -rp "🚨 Default urgency level for ALL tasks? [1-5] (leave empty to cycle): " DEFAULT_URGENCY

echo ""
TOTAL_TASKS=$((NUM_SECTIONS * NUM_COLUMNS * TASKS_PER_COLUMN))
echo "📊 Summary: $NUM_SECTIONS sections × $NUM_COLUMNS columns × $TASKS_PER_COLUMN tasks = $TOTAL_TASKS tasks total"
echo ""
read -rp "✅ Proceed with import? [Y/n]: " CONFIRM
CONFIRM="${CONFIRM:-Y}"
if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "=========================================="
echo "  Running Import Test"
echo "=========================================="
echo ""

login_admin
create_workspace "import-gen"
echo ""

IMPORTED_PROJECT_ID=""

# ==========================================
# Phase 1: Generate JSON payload
# ==========================================
echo "--- Phase 1: Generating JSON payload ---"

PRIORITIES=("low" "medium" "high" "urgent")
STATUSES=("open" "in_progress" "completed" "blocked" "on_hold")
COLUMN_TYPES=("default" "wip" "done")

SECTIONS_JSON=""
TASK_NUM=0

for s in $(seq 1 "$NUM_SECTIONS"); do
    COLUMNS_JSON=""
    SECTION_NAME=$(echo "$SECTION_PATTERN" | sed "s/{n}/$s/g")

    for c in $(seq 1 "$NUM_COLUMNS"); do
        # Determine column name
        COL_IDX=$((c - 1))
        if [ $COL_IDX -lt ${#CUSTOM_COL_NAMES[@]} ] && [ -n "${CUSTOM_COL_NAMES[$COL_IDX]}" ]; then
            COL_NAME=$(echo "${CUSTOM_COL_NAMES[$COL_IDX]}" | xargs)
        else
            COL_NAME="Column $c"
        fi

        COL_TYPE=${COLUMN_TYPES[$(( (c - 1) % 3 ))]}

        # Build tasks for this column
        TASKS_JSON=""
        for t in $(seq 1 "$TASKS_PER_COLUMN"); do
            TASK_NUM=$((TASK_NUM + 1))
            TASK_TITLE=$(echo "$TASK_PATTERN" | sed "s/{n}/$TASK_NUM/g")

            # Priority
            if [ -n "$DEFAULT_PRIORITY" ]; then
                PRIORITY="$DEFAULT_PRIORITY"
            else
                PRIORITY=${PRIORITIES[$(( (TASK_NUM - 1) % 4 ))]}
            fi

            # Status
            if [ -n "$DEFAULT_STATUS" ]; then
                STATUS="$DEFAULT_STATUS"
            else
                STATUS=${STATUSES[$(( (TASK_NUM - 1) % 5 ))]}
            fi

            # Estimated hours
            if [ -n "$DEFAULT_HOURS" ]; then
                HOURS="$DEFAULT_HOURS"
            else
                HOURS=$(( (TASK_NUM % 8) + 1 ))
            fi

            # Urgency
            if [ -n "$DEFAULT_URGENCY" ]; then
                URGENCY="$DEFAULT_URGENCY"
            else
                URGENCY=$(( (TASK_NUM % 5) + 1 ))
            fi

            TASK_ENTRY=$(cat <<TEOF
{
  "title": "$TASK_TITLE",
  "description": "Auto-generated task $TASK_NUM in $SECTION_NAME / $COL_NAME",
  "priority": "$PRIORITY",
  "status": "$STATUS",
  "urgency_level": $URGENCY,
  "estimated_hours": $HOURS,
  "sort_order": $((t - 1))
}
TEOF
)
            if [ -n "$TASKS_JSON" ]; then
                TASKS_JSON="$TASKS_JSON,$TASK_ENTRY"
            else
                TASKS_JSON="$TASK_ENTRY"
            fi
        done

        COLUMN_ENTRY=$(cat <<CEOF
{
  "name": "$COL_NAME",
  "column_type": "$COL_TYPE",
  "sort_order": $((c - 1)),
  "tasks": [$TASKS_JSON]
}
CEOF
)
        if [ -n "$COLUMNS_JSON" ]; then
            COLUMNS_JSON="$COLUMNS_JSON,$COLUMN_ENTRY"
        else
            COLUMNS_JSON="$COLUMN_ENTRY"
        fi
    done

    SECTION_ENTRY=$(cat <<SEOF
{
  "name": "$SECTION_NAME",
  "description": "Section $s of the imported project",
  "section_type": "active",
  "sort_order": $((s - 1)),
  "columns": [$COLUMNS_JSON]
}
SEOF
)
    if [ -n "$SECTIONS_JSON" ]; then
        SECTIONS_JSON="$SECTIONS_JSON,$SECTION_ENTRY"
    else
        SECTIONS_JSON="$SECTION_ENTRY"
    fi
done

# Escape description for JSON
ESCAPED_DESC=$(echo "$PROJECT_DESC" | sed 's/"/\\"/g')

FULL_PAYLOAD=$(cat <<PEOF
{
  "name": "$PROJECT_NAME",
  "description": "$ESCAPED_DESC",
  "status": "$PROJECT_STATUS",
  "board_type": "$BOARD_TYPE",
  "visibility": "$VISIBILITY",
  "workspace_id": "$WORKSPACE_ID",
  "sections": [$SECTIONS_JSON]
}
PEOF
)

echo "   ✅ Payload generated: $TASK_NUM tasks across $NUM_SECTIONS sections × $NUM_COLUMNS columns"
echo ""

# ==========================================
# Phase 2: Import the project
# ==========================================
echo "--- Phase 2: Import project via API ---"

RESPONSE=$(api_json POST "/projects/import" "$FULL_PAYLOAD")
assert_api "POST /projects/import → 201 imports project ($TOTAL_TASKS tasks)" "201" "$RESPONSE"

BODY=$(body_from_response "$RESPONSE")
IMPORTED_PROJECT_ID=$(json_value "$BODY" "data.id")
echo "   Project ID: $IMPORTED_PROJECT_ID"
echo ""

# ==========================================
# Phase 3: Verify structure via export
# ==========================================
echo "--- Phase 3: Verify structure via export ---"

if [ -z "$IMPORTED_PROJECT_ID" ]; then
    print_result "Import returned a project ID" "201" "FAIL" "No project ID in response"
else
    RESPONSE=$(api_get "/projects/$IMPORTED_PROJECT_ID/export")
    assert_api "GET /projects/{id}/export → 200" "200" "$RESPONSE"

    EXPORT_BODY=$(body_from_response "$RESPONSE")

    # Count sections
    SECTION_COUNT=$(JSON_INPUT="$EXPORT_BODY" php -r '
        $data = json_decode(getenv("JSON_INPUT"), true)["data"];
        echo count($data["sections"] ?? []);
    ')
    if [ "$SECTION_COUNT" -eq "$NUM_SECTIONS" ]; then
        print_result "Exported project has $NUM_SECTIONS sections" "$NUM_SECTIONS" "$NUM_SECTIONS" "sections=$SECTION_COUNT"
    else
        print_result "Exported project sections count" "$NUM_SECTIONS" "$SECTION_COUNT" "Expected $NUM_SECTIONS sections"
    fi

    # Count total columns
    COLUMN_COUNT=$(JSON_INPUT="$EXPORT_BODY" php -r '
        $data = json_decode(getenv("JSON_INPUT"), true)["data"];
        $count = 0;
        foreach ($data["sections"] ?? [] as $s) {
            $count += count($s["columns"] ?? []);
        }
        echo $count;
    ')
    EXPECTED_COLS=$((NUM_SECTIONS * NUM_COLUMNS))
    if [ "$COLUMN_COUNT" -eq "$EXPECTED_COLS" ]; then
        print_result "Exported project has $EXPECTED_COLS columns" "$EXPECTED_COLS" "$EXPECTED_COLS" "columns=$COLUMN_COUNT"
    else
        print_result "Exported project columns count" "$EXPECTED_COLS" "$COLUMN_COUNT" "Expected $EXPECTED_COLS columns"
    fi

    # Count total tasks
    TASK_COUNT=$(JSON_INPUT="$EXPORT_BODY" php -r '
        $data = json_decode(getenv("JSON_INPUT"), true)["data"];
        $count = 0;
        foreach ($data["sections"] ?? [] as $s) {
            foreach ($s["columns"] ?? [] as $c) {
                $count += count($c["tasks"] ?? []);
            }
        }
        echo $count;
    ')
    if [ "$TASK_COUNT" -eq "$TOTAL_TASKS" ]; then
        print_result "Exported project has $TOTAL_TASKS tasks" "$TOTAL_TASKS" "$TOTAL_TASKS" "tasks=$TASK_COUNT"
    else
        print_result "Exported project tasks count" "$TOTAL_TASKS" "$TASK_COUNT" "Expected $TOTAL_TASKS tasks"
    fi

    # Verify first section name
    FIRST_SECTION=$(JSON_INPUT="$EXPORT_BODY" php -r '
        $data = json_decode(getenv("JSON_INPUT"), true)["data"];
        echo $data["sections"][0]["name"] ?? "MISSING";
    ')
    EXPECTED_FIRST=$(echo "$SECTION_PATTERN" | sed 's/{n}/1/g')
    if [ "$FIRST_SECTION" = "$EXPECTED_FIRST" ]; then
        print_result "First section name matches '$EXPECTED_FIRST'" "match" "match" "$FIRST_SECTION"
    else
        print_result "First section name" "$EXPECTED_FIRST" "$FIRST_SECTION" "Mismatch"
    fi

    # Verify first task title
    FIRST_TASK=$(JSON_INPUT="$EXPORT_BODY" php -r '
        $data = json_decode(getenv("JSON_INPUT"), true)["data"];
        echo $data["sections"][0]["columns"][0]["tasks"][0]["title"] ?? "MISSING";
    ')
    EXPECTED_FIRST_TASK=$(echo "$TASK_PATTERN" | sed 's/{n}/1/g')
    if [ "$FIRST_TASK" = "$EXPECTED_FIRST_TASK" ]; then
        print_result "First task title matches '$EXPECTED_FIRST_TASK'" "match" "match" "$FIRST_TASK"
    else
        print_result "First task title" "$EXPECTED_FIRST_TASK" "$FIRST_TASK" "Mismatch"
    fi

    # Verify default status if set
    if [ -n "$DEFAULT_STATUS" ]; then
        ALL_STATUS_OK=$(JSON_INPUT="$EXPORT_BODY" DEFAULT_S="$DEFAULT_STATUS" php -r '
            $data = json_decode(getenv("JSON_INPUT"), true)["data"];
            $expected = getenv("DEFAULT_S");
            $ok = true;
            foreach ($data["sections"] as $s) {
                foreach ($s["columns"] as $c) {
                    foreach ($c["tasks"] as $t) {
                        if (($t["status"] ?? "") !== $expected) { $ok = false; break 3; }
                    }
                }
            }
            echo $ok ? "true" : "false";
        ')
        if [ "$ALL_STATUS_OK" = "true" ]; then
            print_result "All tasks have status '$DEFAULT_STATUS'" "true" "true" "All match"
        else
            print_result "All tasks status = $DEFAULT_STATUS" "true" "false" "Some tasks have wrong status"
        fi
    fi

    # Verify default priority if set
    if [ -n "$DEFAULT_PRIORITY" ]; then
        ALL_PRIORITY_OK=$(JSON_INPUT="$EXPORT_BODY" DEFAULT_P="$DEFAULT_PRIORITY" php -r '
            $data = json_decode(getenv("JSON_INPUT"), true)["data"];
            $expected = getenv("DEFAULT_P");
            $ok = true;
            foreach ($data["sections"] as $s) {
                foreach ($s["columns"] as $c) {
                    foreach ($c["tasks"] as $t) {
                        if (($t["priority"] ?? "") !== $expected) { $ok = false; break 3; }
                    }
                }
            }
            echo $ok ? "true" : "false";
        ')
        if [ "$ALL_PRIORITY_OK" = "true" ]; then
            print_result "All tasks have priority '$DEFAULT_PRIORITY'" "true" "true" "All match"
        else
            print_result "All tasks priority = $DEFAULT_PRIORITY" "true" "false" "Some tasks have wrong priority"
        fi
    fi

    # DB verification
    if assert_db_count "tasks" "column_id IN (SELECT id FROM columns WHERE section_id IN (SELECT id FROM sections WHERE project_id = '$IMPORTED_PROJECT_ID'))" "$TOTAL_TASKS"; then
        print_result "DB has exactly $TOTAL_TASKS tasks for imported project" "$TOTAL_TASKS" "$TOTAL_TASKS" "DB count verified"
    else
        print_result "DB task count" "$TOTAL_TASKS" "FAIL" "DB count mismatch"
    fi
fi

# ==========================================
# Cleanup
# ==========================================
echo ""
echo "--- Cleanup ---"
[ -n "$IMPORTED_PROJECT_ID" ] && api_delete "/projects/$IMPORTED_PROJECT_ID" > /dev/null 2>&1 || true
cleanup_common_records

print_summary_and_exit
