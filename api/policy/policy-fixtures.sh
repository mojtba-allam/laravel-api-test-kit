#!/bin/bash
# =============================================================================
# policy-fixtures.sh — Shared fixture setup/teardown for policy test suites
#
# Exposes:
#   setup_policy_fixtures   — build the full fixture world; populates all POL_*
#                             variables plus the six *_TOKEN variables
#   teardown_policy_fixtures — remove everything created by setup; idempotent
#
# Source this file AFTER sourcing api-test-helpers.sh:
#   source "$SCRIPT_DIR/api-test-helpers.sh"
#   source "$SCRIPT_DIR/policy/policy-fixtures.sh"
# =============================================================================

# ---------------------------------------------------------------------------
# Seeded-user token variables (populated by setup_policy_fixtures)
# ---------------------------------------------------------------------------
ADMIN_TOKEN=""
OWNER_TOKEN=""
CREATOR_TOKEN=""
MEMBER_TOKEN=""
AUTHOR_TOKEN=""
OTHER_TOKEN=""

# User IDs captured during login (needed for team-member add)
ADMIN_USER_ID=""
OWNER_USER_ID=""
CREATOR_USER_ID=""
MEMBER_USER_ID=""
AUTHOR_USER_ID=""
OTHER_USER_ID=""

# Fixture resource IDs (populated by setup_policy_fixtures)
POL_WORKSPACE_ID=""
POL_PROJECT_ID=""
POL_SECTION_ID=""
POL_COLUMN_ID=""
POL_TASK_ID=""
POL_TASK_ID_2=""
POL_TEAM_ID=""
POL_COMMENT_A=""
POL_COMMENT_B=""
POL_ATTACHMENT_A=""
POL_ATTACHMENT_B=""
POL_TIMELOG_ID=""
POL_ACTIVITY_ID=""
POL_TAG_ID=""
POL_TAG_ID_2=""
POL_AUTO_BTN_ID=""
POL_WEBHOOK_ID=""

# ---------------------------------------------------------------------------
# setup_policy_fixtures
# ---------------------------------------------------------------------------
setup_policy_fixtures() {
    echo "--- Setting up policy fixtures ---"

    # ------------------------------------------------------------------
    # Step 1: Authenticate all seeded users; capture tokens + user IDs
    #
    # NOTE: login_as is called via $(...) subshell capture to get the token,
    # which means LAST_LOGIN_USER_ID set inside the subshell does NOT propagate
    # back to the parent.  We work around this by calling login_as a second time
    # (without token capture) immediately after, just to populate LAST_LOGIN_USER_ID
    # in the current shell context.  The second call is cheap (single HTTP request)
    # and the token from the first call is still valid.
    # ------------------------------------------------------------------
    echo "  [1/15] Logging in seeded users..."

    ADMIN_TOKEN=$(login_as "$SEED_ADMIN_EMAIL") || {
        echo "ERROR: failed to log in $SEED_ADMIN_EMAIL" >&2; return 1
    }
    login_as "$SEED_ADMIN_EMAIL" > /dev/null 2>&1 || true
    ADMIN_USER_ID="$LAST_LOGIN_USER_ID"

    OWNER_TOKEN=$(login_as "$SEED_OWNER_EMAIL") || {
        echo "ERROR: failed to log in $SEED_OWNER_EMAIL" >&2; return 1
    }
    login_as "$SEED_OWNER_EMAIL" > /dev/null 2>&1 || true
    OWNER_USER_ID="$LAST_LOGIN_USER_ID"

    CREATOR_TOKEN=$(login_as "$SEED_CREATOR_EMAIL") || {
        echo "ERROR: failed to log in $SEED_CREATOR_EMAIL" >&2; return 1
    }
    login_as "$SEED_CREATOR_EMAIL" > /dev/null 2>&1 || true
    CREATOR_USER_ID="$LAST_LOGIN_USER_ID"

    MEMBER_TOKEN=$(login_as "$SEED_MEMBER_EMAIL") || {
        echo "ERROR: failed to log in $SEED_MEMBER_EMAIL" >&2; return 1
    }
    login_as "$SEED_MEMBER_EMAIL" > /dev/null 2>&1 || true
    MEMBER_USER_ID="$LAST_LOGIN_USER_ID"

    AUTHOR_TOKEN=$(login_as "$SEED_AUTHOR_EMAIL") || {
        echo "ERROR: failed to log in $SEED_AUTHOR_EMAIL" >&2; return 1
    }
    login_as "$SEED_AUTHOR_EMAIL" > /dev/null 2>&1 || true
    AUTHOR_USER_ID="$LAST_LOGIN_USER_ID"

    OTHER_TOKEN=$(login_as "$SEED_OTHER_EMAIL") || {
        echo "ERROR: failed to log in $SEED_OTHER_EMAIL" >&2; return 1
    }
    login_as "$SEED_OTHER_EMAIL" > /dev/null 2>&1 || true
    OTHER_USER_ID="$LAST_LOGIN_USER_ID"

    # ------------------------------------------------------------------
    # Step 2: Build core fixture world as project OWNER
    # ------------------------------------------------------------------
    act_as "$OWNER_TOKEN"

    echo "  [2/15] Creating workspace..."
    local ws_resp
    local unique="pol-$(date +%s)-$RANDOM"
    ws_resp=$(api_json POST "/workspaces" \
        "{\"name\":\"ApiWorkspace-${unique}\",\"description\":\"Policy test workspace\",\"visibility\":\"private\"}")
    POL_WORKSPACE_ID=$(json_value "$(body_from_response "$ws_resp")" "data.id")
    [ -z "$POL_WORKSPACE_ID" ] && POL_WORKSPACE_ID=$(json_value "$(body_from_response "$ws_resp")" "id")
    if [ -z "$POL_WORKSPACE_ID" ]; then
        echo "ERROR: failed to create workspace. Response: $(body_from_response "$ws_resp")" >&2
        return 1
    fi

    echo "  [3/15] Creating project..."
    local proj_resp
    proj_resp=$(api_json POST "/projects" \
        "{\"name\":\"ApiProject-${unique}\",\"description\":\"Policy test project\",\"workspace_id\":\"$POL_WORKSPACE_ID\"}")
    POL_PROJECT_ID=$(json_value "$(body_from_response "$proj_resp")" "data.id")
    [ -z "$POL_PROJECT_ID" ] && POL_PROJECT_ID=$(json_value "$(body_from_response "$proj_resp")" "id")
    if [ -z "$POL_PROJECT_ID" ]; then
        echo "ERROR: failed to create project. Response: $(body_from_response "$proj_resp")" >&2
        return 1
    fi

    echo "  [4/15] Creating section..."
    local sec_resp
    sec_resp=$(api_json POST "/sections" \
        "{\"name\":\"ApiSection-${unique}\",\"project_id\":\"$POL_PROJECT_ID\",\"sort_order\":1}")
    POL_SECTION_ID=$(json_value "$(body_from_response "$sec_resp")" "data.id")
    [ -z "$POL_SECTION_ID" ] && POL_SECTION_ID=$(json_value "$(body_from_response "$sec_resp")" "id")
    if [ -z "$POL_SECTION_ID" ]; then
        echo "ERROR: failed to create section. Response: $(body_from_response "$sec_resp")" >&2
        return 1
    fi

    echo "  [5/15] Creating column..."
    local col_resp
    col_resp=$(api_json POST "/columns" \
        "{\"name\":\"ApiColumn-${unique}\",\"section_id\":\"$POL_SECTION_ID\",\"sort_order\":1}")
    POL_COLUMN_ID=$(json_value "$(body_from_response "$col_resp")" "data.id")
    [ -z "$POL_COLUMN_ID" ] && POL_COLUMN_ID=$(json_value "$(body_from_response "$col_resp")" "id")
    if [ -z "$POL_COLUMN_ID" ]; then
        echo "ERROR: failed to create column. Response: $(body_from_response "$col_resp")" >&2
        return 1
    fi

    echo "  [6/15] Creating tasks..."
    local task1_resp task2_resp
    task1_resp=$(api_json POST "/tasks" \
        "{\"title\":\"ApiTask-${unique}-1\",\"column_id\":\"$POL_COLUMN_ID\",\"priority\":\"medium\"}")
    POL_TASK_ID=$(json_value "$(body_from_response "$task1_resp")" "data.id")
    [ -z "$POL_TASK_ID" ] && POL_TASK_ID=$(json_value "$(body_from_response "$task1_resp")" "id")
    if [ -z "$POL_TASK_ID" ]; then
        echo "ERROR: failed to create task 1. Response: $(body_from_response "$task1_resp")" >&2
        return 1
    fi

    task2_resp=$(api_json POST "/tasks" \
        "{\"title\":\"ApiTask-${unique}-2\",\"column_id\":\"$POL_COLUMN_ID\",\"priority\":\"low\"}")
    POL_TASK_ID_2=$(json_value "$(body_from_response "$task2_resp")" "data.id")
    [ -z "$POL_TASK_ID_2" ] && POL_TASK_ID_2=$(json_value "$(body_from_response "$task2_resp")" "id")
    if [ -z "$POL_TASK_ID_2" ]; then
        echo "ERROR: failed to create task 2. Response: $(body_from_response "$task2_resp")" >&2
        return 1
    fi

    # ------------------------------------------------------------------
    # Step 7: Add MEMBER and AUTHOR to the project team (Contributor role)
    #
    # Flow:
    #   a) Create a project team under the project
    #   b) Add MEMBER user and AUTHOR user to that team by user_id
    # ------------------------------------------------------------------
    echo "  [7/15] Adding MEMBER and AUTHOR to project team..."
    local team_resp
    team_resp=$(api_json POST "/projects/$POL_PROJECT_ID/teams" \
        "{\"name\":\"PolTestTeam-${unique}\",\"is_active\":true}")
    POL_TEAM_ID=$(json_value "$(body_from_response "$team_resp")" "data.id")
    [ -z "$POL_TEAM_ID" ] && POL_TEAM_ID=$(json_value "$(body_from_response "$team_resp")" "id")
    if [ -z "$POL_TEAM_ID" ]; then
        echo "ERROR: failed to create project team. Response: $(body_from_response "$team_resp")" >&2
        return 1
    fi

    # Add CREATOR (user-02), MEMBER (user-03), and AUTHOR (user-04) to the project team.
    # CREATOR is added so that "creator" tests (which expect project-member privileges)
    # work correctly.  CREATOR represents a distinct user who is a member of the project
    # but is NOT the project owner (owner = user-01).

    # Add CREATOR (user-02) to project directly (bypass invite flow for test fixtures)
    add_member_direct "$POL_PROJECT_ID" "$CREATOR_USER_ID"

    # Add MEMBER (user-03) to project directly
    add_member_direct "$POL_PROJECT_ID" "$MEMBER_USER_ID"

    # Add AUTHOR (user-04) to project directly
    add_member_direct "$POL_PROJECT_ID" "$AUTHOR_USER_ID"

    # ------------------------------------------------------------------
    # Step 8: Author creates 2 comments
    # ------------------------------------------------------------------
    act_as "$AUTHOR_TOKEN"
    echo "  [8/15] Creating comments as AUTHOR..."

    local cmt_a_resp cmt_b_resp
    cmt_a_resp=$(api_json POST "/comments" \
        "{\"task_id\":\"$POL_TASK_ID\",\"content\":\"Policy test comment A\"}")
    POL_COMMENT_A=$(json_value "$(body_from_response "$cmt_a_resp")" "data.id")
    [ -z "$POL_COMMENT_A" ] && POL_COMMENT_A=$(json_value "$(body_from_response "$cmt_a_resp")" "id")
    if [ -z "$POL_COMMENT_A" ]; then
        echo "ERROR: failed to create comment A. Response: $(body_from_response "$cmt_a_resp")" >&2
        return 1
    fi

    cmt_b_resp=$(api_json POST "/comments" \
        "{\"task_id\":\"$POL_TASK_ID\",\"content\":\"Policy test comment B\"}")
    POL_COMMENT_B=$(json_value "$(body_from_response "$cmt_b_resp")" "data.id")
    [ -z "$POL_COMMENT_B" ] && POL_COMMENT_B=$(json_value "$(body_from_response "$cmt_b_resp")" "id")
    if [ -z "$POL_COMMENT_B" ]; then
        echo "ERROR: failed to create comment B. Response: $(body_from_response "$cmt_b_resp")" >&2
        return 1
    fi

    # ------------------------------------------------------------------
    # Step 9: Author uploads 2 attachments
    # ------------------------------------------------------------------
    echo "  [9/15] Uploading attachments as AUTHOR..."
    echo "policy-test-fixture" > /tmp/pol-test-attach.txt

    local att_a_resp att_b_resp
    att_a_resp=$(api_multipart POST "/attachments/upload" \
        -F "file=@/tmp/pol-test-attach.txt" \
        -F "task_id=$POL_TASK_ID")
    POL_ATTACHMENT_A=$(json_value "$(body_from_response "$att_a_resp")" "data.id")
    [ -z "$POL_ATTACHMENT_A" ] && POL_ATTACHMENT_A=$(json_value "$(body_from_response "$att_a_resp")" "id")
    if [ -z "$POL_ATTACHMENT_A" ]; then
        echo "ERROR: failed to upload attachment A. Response: $(body_from_response "$att_a_resp")" >&2
        return 1
    fi

    att_b_resp=$(api_multipart POST "/attachments/upload" \
        -F "file=@/tmp/pol-test-attach.txt" \
        -F "task_id=$POL_TASK_ID")
    POL_ATTACHMENT_B=$(json_value "$(body_from_response "$att_b_resp")" "data.id")
    [ -z "$POL_ATTACHMENT_B" ] && POL_ATTACHMENT_B=$(json_value "$(body_from_response "$att_b_resp")" "id")
    if [ -z "$POL_ATTACHMENT_B" ]; then
        echo "ERROR: failed to upload attachment B. Response: $(body_from_response "$att_b_resp")" >&2
        return 1
    fi

    # ------------------------------------------------------------------
    # Step 10: Author creates a time log
    # ------------------------------------------------------------------
    echo "  [10/15] Creating time log as AUTHOR..."
    local tl_resp
    local today
    today=$(date +%Y-%m-%d)
    tl_resp=$(api_json POST "/time-logs" \
        "{\"task_id\":\"$POL_TASK_ID\",\"minutes\":30,\"hours\":0,\"description\":\"Policy test timelog\",\"logged_date\":\"$today\"}")
    POL_TIMELOG_ID=$(json_value "$(body_from_response "$tl_resp")" "data.id")
    [ -z "$POL_TIMELOG_ID" ] && POL_TIMELOG_ID=$(json_value "$(body_from_response "$tl_resp")" "id")
    if [ -z "$POL_TIMELOG_ID" ]; then
        echo "ERROR: failed to create time log. Response: $(body_from_response "$tl_resp")" >&2
        return 1
    fi

    # ------------------------------------------------------------------
    # Step 11: Admin finds an activity row
    # ------------------------------------------------------------------
    act_as "$ADMIN_TOKEN"
    echo "  [11/15] Fetching activity ID as ADMIN..."
    local act_resp
    act_resp=$(api_get "/activities")
    POL_ACTIVITY_ID=$(json_value "$(body_from_response "$act_resp")" "data.first.id")
    [ -z "$POL_ACTIVITY_ID" ] && POL_ACTIVITY_ID=$(json_value "$(body_from_response "$act_resp")" "data.0.id")
    if [ -z "$POL_ACTIVITY_ID" ]; then
        echo "WARNING: could not capture a POL_ACTIVITY_ID (activity list may be empty)" >&2
    fi

    # ------------------------------------------------------------------
    # Step 12: Create two tags (as OWNER — project owner)
    # ------------------------------------------------------------------
    act_as "$OWNER_TOKEN"
    echo "  [12/15] Creating tags as OWNER..."

    local tag_a_resp tag_b_resp
    tag_a_resp=$(api_json POST "/tags" \
        "{\"name\":\"pol-tag-a-${unique}\",\"project_id\":\"$POL_PROJECT_ID\",\"color\":\"#3B82F6\"}")
    POL_TAG_ID=$(json_value "$(body_from_response "$tag_a_resp")" "data.id")
    [ -z "$POL_TAG_ID" ] && POL_TAG_ID=$(json_value "$(body_from_response "$tag_a_resp")" "id")
    if [ -z "$POL_TAG_ID" ]; then
        echo "ERROR: failed to create tag A. Response: $(body_from_response "$tag_a_resp")" >&2
        return 1
    fi

    tag_b_resp=$(api_json POST "/tags" \
        "{\"name\":\"pol-tag-b-${unique}\",\"project_id\":\"$POL_PROJECT_ID\",\"color\":\"#10B981\"}")
    POL_TAG_ID_2=$(json_value "$(body_from_response "$tag_b_resp")" "data.id")
    [ -z "$POL_TAG_ID_2" ] && POL_TAG_ID_2=$(json_value "$(body_from_response "$tag_b_resp")" "id")
    if [ -z "$POL_TAG_ID_2" ]; then
        echo "ERROR: failed to create tag B. Response: $(body_from_response "$tag_b_resp")" >&2
        return 1
    fi

    # ------------------------------------------------------------------
    # Step 13: Create an automation button
    #
    # Required fields (from StoreAutomationButtonRequest):
    #   project_id, name, button_label, scope, actions[].type, actions[].config
    # ------------------------------------------------------------------
    echo "  [13/15] Creating automation button as OWNER..."
    local btn_resp
    btn_resp=$(api_json POST "/automation-buttons" \
        "{\"project_id\":\"$POL_PROJECT_ID\",\"name\":\"PolTestBtn-${unique}\",\"button_label\":\"Run Policy Test\",\"scope\":\"task\",\"actions\":[{\"type\":\"add_comment\",\"config\":{\"content\":\"automated\"}}],\"is_active\":true}")
    POL_AUTO_BTN_ID=$(json_value "$(body_from_response "$btn_resp")" "data.id")
    [ -z "$POL_AUTO_BTN_ID" ] && POL_AUTO_BTN_ID=$(json_value "$(body_from_response "$btn_resp")" "id")
    if [ -z "$POL_AUTO_BTN_ID" ]; then
        echo "WARNING: failed to create automation button. Response: $(body_from_response "$btn_resp")" >&2
        # Non-fatal — button assertions will simply produce a 404 or skip
    fi

    # ------------------------------------------------------------------
    # Step 14: Create a webhook
    #
    # Endpoint: POST /projects/{projectId}/webhooks
    # Required fields: project_id, name, url, events[]
    # ------------------------------------------------------------------
    echo "  [14/15] Creating webhook as OWNER..."
    local wh_resp
    wh_resp=$(api_json POST "/projects/$POL_PROJECT_ID/webhooks" \
        "{\"project_id\":\"$POL_PROJECT_ID\",\"name\":\"PolTestWebhook-${unique}\",\"url\":\"https://webhook.site/policy-test\",\"events\":[\"task.created\"],\"is_active\":true}")
    POL_WEBHOOK_ID=$(json_value "$(body_from_response "$wh_resp")" "data.id")
    [ -z "$POL_WEBHOOK_ID" ] && POL_WEBHOOK_ID=$(json_value "$(body_from_response "$wh_resp")" "id")
    if [ -z "$POL_WEBHOOK_ID" ]; then
        echo "ERROR: failed to create webhook. Response: $(body_from_response "$wh_resp")" >&2
        return 1
    fi

    # ------------------------------------------------------------------
    # Step 15: Expose WORKSPACE_ID / PROJECT_ID etc. under the canonical
    # names that cleanup_common_records() uses, so the shared teardown
    # helper can also clean up the pol-test resources when needed.
    # ------------------------------------------------------------------
    echo "  [15/15] Fixtures ready."

    # Mirror into the global names used by cleanup_common_records
    WORKSPACE_ID="$POL_WORKSPACE_ID"
    PROJECT_ID="$POL_PROJECT_ID"
    SECTION_ID="$POL_SECTION_ID"
    COLUMN_ID="$POL_COLUMN_ID"
    TASK_ID="$POL_TASK_ID"
    TASK_ID_2="$POL_TASK_ID_2"

    echo "--- Policy fixtures ready ---"
    echo "    POL_WORKSPACE_ID=$POL_WORKSPACE_ID"
    echo "    POL_PROJECT_ID=$POL_PROJECT_ID"
    echo "    POL_TASK_ID=$POL_TASK_ID"
    echo "    POL_COMMENT_A=$POL_COMMENT_A"
    echo "    POL_COMMENT_B=$POL_COMMENT_B"
    echo "    POL_ATTACHMENT_A=$POL_ATTACHMENT_A"
    echo "    POL_ATTACHMENT_B=$POL_ATTACHMENT_B"
}

# ---------------------------------------------------------------------------
# teardown_policy_fixtures
# ---------------------------------------------------------------------------
# Removes all resources created by setup_policy_fixtures, in reverse order.
# All deletes run as ADMIN_TOKEN (broadest rights).
# Every delete is guarded so partial-setup teardowns are safe.
# Seeded users (user-01..user-05) are NOT deleted.
# ---------------------------------------------------------------------------
teardown_policy_fixtures() {
    echo "--- Tearing down policy fixtures ---"
    act_as "$ADMIN_TOKEN"

    # Comments
    [ -n "${POL_COMMENT_A:-}" ] && api_delete "/comments/$POL_COMMENT_A"     > /dev/null 2>&1 || true
    [ -n "${POL_COMMENT_B:-}" ] && api_delete "/comments/$POL_COMMENT_B"     > /dev/null 2>&1 || true

    # Attachments
    [ -n "${POL_ATTACHMENT_A:-}" ] && api_delete "/attachments/$POL_ATTACHMENT_A" > /dev/null 2>&1 || true
    [ -n "${POL_ATTACHMENT_B:-}" ] && api_delete "/attachments/$POL_ATTACHMENT_B" > /dev/null 2>&1 || true

    # Time log
    [ -n "${POL_TIMELOG_ID:-}" ] && api_delete "/time-logs/$POL_TIMELOG_ID"  > /dev/null 2>&1 || true

    # Webhook
    [ -n "${POL_WEBHOOK_ID:-}" ] && api_delete "/webhooks/$POL_WEBHOOK_ID"   > /dev/null 2>&1 || true

    # Automation button
    [ -n "${POL_AUTO_BTN_ID:-}" ] && api_delete "/automation-buttons/$POL_AUTO_BTN_ID" > /dev/null 2>&1 || true

    # Tags
    [ -n "${POL_TAG_ID:-}"   ] && api_delete "/tags/$POL_TAG_ID"             > /dev/null 2>&1 || true
    [ -n "${POL_TAG_ID_2:-}" ] && api_delete "/tags/$POL_TAG_ID_2"           > /dev/null 2>&1 || true

    # Temp file
    rm -f /tmp/pol-test-attach.txt

    # Tasks → column → section → project → workspace
    # (cleanup_common_records reads TASK_ID/TASK_ID_2/COLUMN_ID/SECTION_ID/
    #  PROJECT_ID/WORKSPACE_ID which were mirrored from the POL_* vars in setup)
    cleanup_common_records

    echo "--- Policy fixtures torn down ---"
}
