#!/bin/bash

# =============================================================================
# Notifications Cross-User API Test Suite
# =============================================================================
#
# Verifies that when User A performs actions across multiple modules, the
# expected notifications appear in User B's (and User C's) notifications feed.
#
# Scenario A → B → C
#   - User A: seeded admin ($SEED_ADMIN_EMAIL)
#   - User B: freshly registered user, added to A's workspace + project as a
#             member, assignee/watcher of tasks
#   - User C: freshly registered user, added to A's workspace only
#             (used to verify workspace-invitation notifications)
#
# Modules / actions exercised by User A that SHOULD trigger notifications:
#   1. Task module      -> creates task assigning B             -> task_assigned (B)
#   2. Task module      -> updates task, re-assign B            -> task_assigned (B)
#   3. Comment module   -> comment mentioning B                  -> comment_mention (B)
#   4. Comment module   -> comment without mention (B assignee)  -> comment_added  (B)
#   5. Task module      -> PATCH status to in_progress           -> task_status_changed (B)
#   6. Task module      -> POST /tasks/{id}/complete             -> task_completed (B)
#   7. Attachment module-> upload file to task                   -> attachment_added (B)
#   8. Workspace module -> invite C by email                     -> project_invitation (C)
#   9. Task module      -> create 2nd task B watches, change st. -> task_status_changed (B)
#   10. Task module     -> assign B to 3rd task & complete it    -> task_completed (B)
#
# After each action we re-authenticate as B (or C) and verify the notification
# arrived in their feed. We also test unread-count, mark-read, mark-all-read,
# and cross-user isolation.
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "=========================================="
echo "Notifications Cross-User API Test Suite"
echo "User A → performs actions, verify B / C feeds"
echo "=========================================="
echo ""

# -----------------------------------------------------------------------------
# Helpers specific to this script
# -----------------------------------------------------------------------------

# Returns 0 (true) iff the authenticated user has a notification of $type whose
# data.entity_id == $entity_id (when provided). Pulls up to per_page=100.
notification_exists_for_current_user() {
    local type="$1"
    local entity_id="${2:-}"

    local response body
    response=$(api_get "/notifications?per_page=100")
    body=$(body_from_response "$response")

    BODY_INPUT="$body" TYPE_INPUT="$type" ENTITY_INPUT="$entity_id" php -r '
        $body = getenv("BODY_INPUT");
        $type = getenv("TYPE_INPUT");
        $entityId = getenv("ENTITY_INPUT");
        $data = json_decode($body, true);
        if (!is_array($data) || !isset($data["data"]) || !is_array($data["data"])) {
            exit(1);
        }
        foreach ($data["data"] as $n) {
            if (($n["type"] ?? null) !== $type) {
                continue;
            }
            if ($entityId === "") {
                exit(0);
            }
            $payload = $n["data"] ?? [];
            if (is_string($payload)) {
                $payload = json_decode($payload, true) ?? [];
            }
            if (($payload["entity_id"] ?? null) === $entityId) {
                exit(0);
            }
        }
        exit(1);
    '
}

# Find a notification id by type/entity_id for the current user. Stdout is the
# id or empty string.
find_notification_id_for_current_user() {
    local type="$1"
    local entity_id="${2:-}"

    local response body
    response=$(api_get "/notifications?per_page=100")
    body=$(body_from_response "$response")

    BODY_INPUT="$body" TYPE_INPUT="$type" ENTITY_INPUT="$entity_id" php -r '
        $body = getenv("BODY_INPUT");
        $type = getenv("TYPE_INPUT");
        $entityId = getenv("ENTITY_INPUT");
        $data = json_decode($body, true);
        if (!is_array($data) || !isset($data["data"])) {
            exit;
        }
        foreach ($data["data"] as $n) {
            if (($n["type"] ?? null) !== $type) {
                continue;
            }
            $payload = $n["data"] ?? [];
            if (is_string($payload)) {
                $payload = json_decode($payload, true) ?? [];
            }
            if ($entityId !== "" && ($payload["entity_id"] ?? null) !== $entityId) {
                continue;
            }
            echo $n["id"];
            return;
        }
    '
}

assert_notification() {
    local who="$1"
    local type="$2"
    local entity_id="${3:-}"

    if notification_exists_for_current_user "$type" "$entity_id"; then
        print_result "$who receives '$type'${entity_id:+ (entity)}" "200" "200" "found"
    else
        local body
        body=$(body_from_response "$(api_get "/notifications?per_page=100")")
        print_result "$who receives '$type'${entity_id:+ (entity)}" "200" "FAIL" "$body"
    fi
}

assert_no_notification() {
    local who="$1"
    local type="$2"
    local entity_id="${3:-}"

    if notification_exists_for_current_user "$type" "$entity_id"; then
        local body
        body=$(body_from_response "$(api_get "/notifications?per_page=100")")
        print_result "$who does NOT receive '$type'${entity_id:+ (entity)}" "200" "FAIL" "$body"
    else
        print_result "$who does NOT receive '$type'${entity_id:+ (entity)}" "200" "200" "absent"
    fi
}

# Count total notifications for the current user.
count_notifications() {
    local response body
    response=$(api_get "/notifications?per_page=100")
    body=$(body_from_response "$response")

    BODY_INPUT="$body" php -r '
        $b = json_decode(getenv("BODY_INPUT"), true);
        echo isset($b["data"]) && is_array($b["data"]) ? count($b["data"]) : 0;
    '
}

# Registers a new user and outputs token/id/email.
register_user() {
    local name_prefix="$1"
    local out_token_var="$2"
    local out_id_var="$3"
    local out_email_var="$4"

    local stamp="$(date +%s)-$RANDOM"
    local email="${name_prefix}-${stamp}@test.example.com"
    local password="Notif1234!@"
    local laravel_log="$PROJECT_ROOT/storage/logs/laravel.log"

    > "$laravel_log" 2>/dev/null || true

    local response body token user_id
    response=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/auth/register" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"${name_prefix}-${stamp}\",\"email\":\"$email\",\"password\":\"$password\",\"password_confirmation\":\"$password\"}")

    body=$(body_from_response "$response")
    token=$(json_value "$body" "data.token")
    user_id=$(json_value "$body" "data.user.id")

    if [ -z "$token" ] || [ -z "$user_id" ]; then
        echo -e "${RED}Failed to register $name_prefix${NC}" >&2
        echo "$body" >&2
        exit 1
    fi

    # Verify email via API
    sleep 1
    local vcode
    vcode=$(grep "letter-spacing" "$laravel_log" 2>/dev/null | grep -oP '\d{6}' | tail -1)
    if [ -n "$vcode" ]; then
        curl -sk -X POST "$BASE_URL/auth/verify-email-code" \
            -H "Authorization: Bearer $token" \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -d "{\"code\": \"$vcode\"}" > /dev/null 2>&1
    fi

    printf -v "$out_token_var" '%s' "$token"
    printf -v "$out_id_var" '%s' "$user_id"
    printf -v "$out_email_var" '%s' "$email"

    echo "✓ Registered $name_prefix as $email (id=$user_id)"
}

# Adds a user as a workspace member using the current TOKEN.
add_workspace_member() {
    local workspace_id="$1"
    local user_id="$2"

    api_json POST "/workspaces/$workspace_id/members" \
        "{\"user_id\":\"$user_id\"}" > /dev/null
}

# Adds a user to the project_members table directly via artisan tinker.
# This is needed because there's no dedicated "add project member" API endpoint.
add_project_member() {
    local project_id="$1"
    local user_id="$2"

    cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="
        use Illuminate\Support\Str;
        use Modules\Project\Models\ProjectMember;

        // Skip if already a member
        if (ProjectMember::where('project_id', '$project_id')->where('user_id', '$user_id')->exists()) {
            echo 'already_member';
            return;
        }

        // Get or create global role
        \$globalRole = \Modules\Project\Models\GlobalRole::firstOrCreate(
            ['name' => 'User'],
            ['description' => 'Standard user role', 'is_system_role' => true]
        );

        // Get or create project role
        \$projectRole = \Modules\Project\Models\ProjectRole::firstOrCreate(
            ['project_id' => '$project_id', 'name' => 'Contributor'],
            ['description' => 'Can create and edit tasks', 'is_default' => true]
        );

        ProjectMember::create([
            'id' => Str::uuid()->toString(),
            'project_id' => '$project_id',
            'user_id' => '$user_id',
            'global_role_id' => \$globalRole->id,
            'project_role_id' => \$projectRole->id,
            'joined_at' => now(),
        ]);
        echo 'added';
    " 2>/dev/null | tail -1
}

# Enable notification preferences for a user (calls API as that user).
# This is crucial because some notification types are disabled by default:
# comment_added, attachment_added, task_status_changed.
enable_all_notification_preferences() {
    local user_token="$1"
    local old_token="$TOKEN"
    TOKEN="$user_token"

    # Create default preferences first
    api_json POST "/notification-preferences/create-defaults" '{}' > /dev/null 2>&1 || true

    # Enable the notification types that are disabled by default
    local types_to_enable=(
        "comment_added"
        "attachment_added"
        "task_status_changed"
    )

    for type in "${types_to_enable[@]}"; do
        api_json POST "/notification-preferences" \
            "{\"notification_type\":\"$type\",\"email_enabled\":true,\"in_app_enabled\":true}" > /dev/null 2>&1 || true
    done

    TOKEN="$old_token"
}

# -----------------------------------------------------------------------------
# Setup: User A (admin), register B and C, build workspace/project structure
# -----------------------------------------------------------------------------

echo "Setting up test environment..."

login_admin
TOKEN_A="$TOKEN"
USER_A_ID="$USER_ID"

register_user "userB" TOKEN_B USER_B_ID EMAIL_B
register_user "userC" TOKEN_C USER_C_ID EMAIL_C

# Enable notification preferences for User B and C (some types are disabled by default)
echo "Enabling notification preferences for User B..."
enable_all_notification_preferences "$TOKEN_B"
echo "Enabling notification preferences for User C..."
enable_all_notification_preferences "$TOKEN_C"

# Switch to A and create workspace + project + section + column
act_as "$TOKEN_A"

create_workspace "notif-cross-$(date +%s)"
echo "✓ Workspace $WORKSPACE_ID"

# Add B and C to the workspace so they can see workspace-scoped resources
add_workspace_member "$WORKSPACE_ID" "$USER_B_ID"
add_workspace_member "$WORKSPACE_ID" "$USER_C_ID"
echo "✓ Added B and C as workspace members"

create_project "notif-cross-$(date +%s)"
echo "✓ Project $PROJECT_ID"

# Add B as a project member (needed for TaskPolicy view/update checks)
MEMBER_RESULT=$(add_project_member "$PROJECT_ID" "$USER_B_ID")
echo "✓ User B project membership: $MEMBER_RESULT"

create_section "notif-cross-$(date +%s)"
echo "✓ Section $SECTION_ID"

create_column "notif-cross-$(date +%s)"
echo "✓ Column $COLUMN_ID"

echo ""

# =============================================================================
# Phase 1: Task Assignment (User A creates task with B as assignee)
# =============================================================================
echo "=========================================="
echo "Phase 1: task_assigned (create with assignee)"
echo "=========================================="
echo ""

act_as "$TOKEN_A"

RESPONSE=$(api_json POST "/tasks" "{
    \"title\":\"NotifCross-Task1-$(date +%s)\",
    \"column_id\":\"$COLUMN_ID\",
    \"priority\":\"medium\",
    \"assignee_ids\":[\"$USER_B_ID\"]
}")
assert_api "User A creates task assigned to B → 201" "201 200" "$RESPONSE"

TASK_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$TASK_ID" ] && TASK_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")
echo "✓ Task $TASK_ID"

# B should receive task_assigned
act_as "$TOKEN_B"
assert_notification "User B" "task_assigned" "$TASK_ID"

# A (actor) should NOT receive task_assigned
act_as "$TOKEN_A"
assert_no_notification "User A (actor exclusion)" "task_assigned" "$TASK_ID"

echo ""

# =============================================================================
# Phase 2: Re-assignment (User A updates task to add B again via assignee_ids)
# =============================================================================
echo "=========================================="
echo "Phase 2: task_assigned (update with assignee_ids)"
echo "=========================================="
echo ""

act_as "$TOKEN_A"

# Create a second task, then update to assign B
RESPONSE=$(api_json POST "/tasks" "{
    \"title\":\"NotifCross-Task2-$(date +%s)\",
    \"column_id\":\"$COLUMN_ID\",
    \"priority\":\"low\"
}")
assert_api "User A creates 2nd task (no assignees) → 201" "201 200" "$RESPONSE"
TASK_ID_2=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$TASK_ID_2" ] && TASK_ID_2=$(json_value "$(body_from_response "$RESPONSE")" "id")
echo "✓ Task 2 = $TASK_ID_2"

# Assign B via update
RESPONSE=$(api_json PATCH "/tasks/$TASK_ID_2" "{\"assignee_ids\":[\"$USER_B_ID\"]}")
assert_api "User A updates task 2 assigning B → 200" "200" "$RESPONSE"

act_as "$TOKEN_B"
assert_notification "User B" "task_assigned" "$TASK_ID_2"

echo ""

# =============================================================================
# Phase 3: Comment with @mention (User A mentions B)
# =============================================================================
echo "=========================================="
echo "Phase 3: comment_mention"
echo "=========================================="
echo ""

act_as "$TOKEN_A"

RESPONSE=$(api_json POST "/comments" "{
    \"task_id\":\"$TASK_ID\",
    \"content\":\"Hey @userB please review this task urgently\",
    \"mentions\":[\"$USER_B_ID\"]
}")
assert_api "User A comments mentioning B → 201" "201 200" "$RESPONSE"

# B should receive comment_mention
act_as "$TOKEN_B"
assert_notification "User B" "comment_mention" "$TASK_ID"

echo ""

# =============================================================================
# Phase 4: Comment without mention (B is assignee, should get comment_added)
# =============================================================================
echo "=========================================="
echo "Phase 4: comment_added (B is assignee)"
echo "=========================================="
echo ""

act_as "$TOKEN_A"

RESPONSE=$(api_json POST "/comments" "{
    \"task_id\":\"$TASK_ID\",
    \"content\":\"Adding a general progress update for the team\"
}")
assert_api "User A adds plain comment on task → 201" "201 200" "$RESPONSE"

# B is assignee of TASK_ID and not mentioned → should get comment_added
act_as "$TOKEN_B"
assert_notification "User B (assignee, no mention)" "comment_added" "$TASK_ID"

echo ""

# =============================================================================
# Phase 5: Task status change to in_progress
# =============================================================================
echo "=========================================="
echo "Phase 5: task_status_changed"
echo "=========================================="
echo ""

act_as "$TOKEN_A"

RESPONSE=$(api_json PATCH "/tasks/$TASK_ID" '{"status":"in_progress"}')
assert_api "User A changes task status to in_progress → 200" "200" "$RESPONSE"

# B (assignee) should receive task_status_changed
act_as "$TOKEN_B"
assert_notification "User B (assignee)" "task_status_changed" "$TASK_ID"

# Should NOT get task_completed for non-completed change
assert_no_notification "User B (no false completion)" "task_completed" "$TASK_ID"

echo ""

# =============================================================================
# Phase 6: Task completion
# =============================================================================
echo "=========================================="
echo "Phase 6: task_completed"
echo "=========================================="
echo ""

act_as "$TOKEN_A"

RESPONSE=$(api_json POST "/tasks/$TASK_ID/complete" '{}')
assert_api "User A completes task → 200" "200" "$RESPONSE"

# B should receive task_completed
act_as "$TOKEN_B"
assert_notification "User B (assignee)" "task_completed" "$TASK_ID"

echo ""

# =============================================================================
# Phase 7: Attachment upload (User A uploads to task where B is assignee)
# =============================================================================
echo "=========================================="
echo "Phase 7: attachment_added"
echo "=========================================="
echo ""

act_as "$TOKEN_A"

# Create a small temp file to upload
TMP_FILE="$(mktemp /tmp/api-test-notif-XXXXXX.txt)"
echo "notification test attachment content" > "$TMP_FILE"

RESPONSE=$(api_multipart POST "/attachments/upload" \
    -F "file=@${TMP_FILE};type=text/plain" \
    -F "task_id=$TASK_ID" \
    -F "description=Cross-user notification test")
STATUS_UP=$(status_from_response "$RESPONSE")

if [ "$STATUS_UP" = "201" ] || [ "$STATUS_UP" = "200" ]; then
    print_result "User A uploads attachment → 201/200" "201 200" "$STATUS_UP" "ok"

    # B (assignee) should receive attachment_added
    act_as "$TOKEN_B"
    assert_notification "User B (assignee)" "attachment_added" "$TASK_ID"
else
    # Upload failure (e.g., storage not configured) — record failure and move on
    print_result "User A uploads attachment → 201/200" "201 200" "$STATUS_UP" "$(body_from_response "$RESPONSE")"
fi

rm -f "$TMP_FILE"

echo ""

# =============================================================================
# Phase 8: Workspace invitation (User A invites C by email)
# =============================================================================
echo "=========================================="
echo "Phase 8: project_invitation (workspace invite)"
echo "=========================================="
echo ""

act_as "$TOKEN_A"

# Create a new workspace specifically for this invite test (C isn't already a member)
RESPONSE=$(api_json POST "/workspaces" "{\"name\":\"InviteWS-$(date +%s)-$RANDOM\",\"description\":\"For invite test\",\"visibility\":\"private\"}")
INVITE_WORKSPACE_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$INVITE_WORKSPACE_ID" ] && INVITE_WORKSPACE_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")
echo "✓ Created invite workspace: $INVITE_WORKSPACE_ID"

RESPONSE=$(api_json POST "/workspaces/$INVITE_WORKSPACE_ID/invites" \
    "{\"email\":\"$EMAIL_C\"}")
STATUS_INV=$(status_from_response "$RESPONSE")

if [ "$STATUS_INV" = "200" ] || [ "$STATUS_INV" = "201" ]; then
    print_result "User A invites C to workspace → 201" "200 201" "$STATUS_INV" "ok"

    # C should receive project_invitation
    act_as "$TOKEN_C"
    assert_notification "User C" "project_invitation" "$INVITE_WORKSPACE_ID"
else
    print_result "User A invites C to workspace → 201" "200 201" "$STATUS_INV" "$(body_from_response "$RESPONSE")"
fi

echo ""

# =============================================================================
# Phase 9: Watcher notification (B watches task, A changes status)
# =============================================================================
echo "=========================================="
echo "Phase 9: task_status_changed (watcher)"
echo "=========================================="
echo ""

act_as "$TOKEN_A"

# Create a new task (no assignees)
RESPONSE=$(api_json POST "/tasks" "{
    \"title\":\"NotifCross-WatchTask-$(date +%s)\",
    \"column_id\":\"$COLUMN_ID\",
    \"priority\":\"high\"
}")
assert_api "User A creates task for watcher test → 201" "201 200" "$RESPONSE"
TASK_ID_3=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$TASK_ID_3" ] && TASK_ID_3=$(json_value "$(body_from_response "$RESPONSE")" "id")
echo "✓ Task 3 = $TASK_ID_3"

# B watches the task (B is a project member so should have view access)
act_as "$TOKEN_B"
RESPONSE=$(api_json POST "/tasks/$TASK_ID_3/watchers/me" '{}')
assert_api "User B watches Task 3 → 200/201" "200 201" "$RESPONSE"

# A changes status of task 3
act_as "$TOKEN_A"
RESPONSE=$(api_json PATCH "/tasks/$TASK_ID_3" '{"status":"in_progress"}')
assert_api "User A changes Task 3 status → 200" "200" "$RESPONSE"

# B (watcher) should receive task_status_changed
act_as "$TOKEN_B"
assert_notification "User B (watcher)" "task_status_changed" "$TASK_ID_3"

echo ""

# =============================================================================
# Phase 10: Assign + Complete a 3rd task to generate another task_completed
# =============================================================================
echo "=========================================="
echo "Phase 10: task_assigned + task_completed (3rd task)"
echo "=========================================="
echo ""

act_as "$TOKEN_A"

RESPONSE=$(api_json POST "/tasks" "{
    \"title\":\"NotifCross-Complete3-$(date +%s)\",
    \"column_id\":\"$COLUMN_ID\",
    \"priority\":\"high\",
    \"assignee_ids\":[\"$USER_B_ID\"]
}")
assert_api "User A creates 4th task assigned to B → 201" "201 200" "$RESPONSE"
TASK_ID_4=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$TASK_ID_4" ] && TASK_ID_4=$(json_value "$(body_from_response "$RESPONSE")" "id")
echo "✓ Task 4 = $TASK_ID_4"

# Verify B got task_assigned
act_as "$TOKEN_B"
assert_notification "User B" "task_assigned" "$TASK_ID_4"

# A completes it
act_as "$TOKEN_A"
RESPONSE=$(api_json POST "/tasks/$TASK_ID_4/complete" '{}')
assert_api "User A completes Task 4 → 200" "200" "$RESPONSE"

# B should get task_completed
act_as "$TOKEN_B"
assert_notification "User B" "task_completed" "$TASK_ID_4"

echo ""

# =============================================================================
# Phase 11: Comment with mention on a task where B is NOT assigned
# =============================================================================
echo "=========================================="
echo "Phase 11: comment_mention (non-assignee)"
echo "=========================================="
echo ""

act_as "$TOKEN_A"

# Use Task 3 where B is a watcher but not an assignee
RESPONSE=$(api_json POST "/comments" "{
    \"task_id\":\"$TASK_ID_3\",
    \"content\":\"FYI @userB — important update for you here\",
    \"mentions\":[\"$USER_B_ID\"]
}")
assert_api "User A comments on Task 3 mentioning B → 201" "201 200" "$RESPONSE"

act_as "$TOKEN_B"
assert_notification "User B (mention on non-assigned task)" "comment_mention" "$TASK_ID_3"

echo ""

# =============================================================================
# Phase 12: User B feed integrity — multiple notification types present
# =============================================================================
echo "=========================================="
echo "Phase 12: User B feed integrity"
echo "=========================================="
echo ""

act_as "$TOKEN_B"

# Count total notifications
NOTIF_COUNT=$(count_notifications)
echo "User B total notifications: $NOTIF_COUNT"

if [ "${NOTIF_COUNT:-0}" -ge 6 ]; then
    print_result "User B has at least 6 notifications across modules" "200" "200" "count=$NOTIF_COUNT"
else
    print_result "User B has at least 6 notifications across modules" "200" "FAIL" "count=$NOTIF_COUNT"
fi

# Unread count should be > 0
RESPONSE=$(api_get "/notifications/unread-count")
BODY=$(body_from_response "$RESPONSE")
UNREAD=$(json_value "$BODY" "unread_count")
if [ -n "$UNREAD" ] && [ "$UNREAD" -gt 0 ]; then
    print_result "User B unread_count > 0" "200" "200" "unread=$UNREAD"
else
    print_result "User B unread_count > 0" "200" "FAIL" "$BODY"
fi

echo ""

# =============================================================================
# Phase 13: Mark individual notification as read / unread round-trip
# =============================================================================
echo "=========================================="
echo "Phase 13: Mark read / unread round-trip"
echo "=========================================="
echo ""

act_as "$TOKEN_B"

# Find one task_assigned notification to test mark-read
NOTIF_ID=$(find_notification_id_for_current_user "task_assigned" "$TASK_ID")
if [ -n "$NOTIF_ID" ]; then
    # Mark read
    RESPONSE=$(api_json POST "/notifications/$NOTIF_ID/mark-read" '{}')
    assert_api "User B marks notification read → 200" "200" "$RESPONSE"

    # Verify excluded from unread feed
    RESPONSE=$(api_get "/notifications?unread=1&per_page=100")
    BODY=$(body_from_response "$RESPONSE")
    if echo "$BODY" | grep -q "$NOTIF_ID"; then
        print_result "Marked-read excluded from unread feed" "200" "FAIL" "still present"
    else
        print_result "Marked-read excluded from unread feed" "200" "200" "ok"
    fi

    # Mark unread (round-trip)
    RESPONSE=$(api_json POST "/notifications/$NOTIF_ID/mark-unread" '{}')
    assert_api "User B marks notification unread → 200" "200" "$RESPONSE"

    # Verify it appears in unread feed again
    RESPONSE=$(api_get "/notifications?unread=1&per_page=100")
    BODY=$(body_from_response "$RESPONSE")
    if echo "$BODY" | grep -q "$NOTIF_ID"; then
        print_result "Marked-unread appears in unread feed" "200" "200" "ok"
    else
        print_result "Marked-unread appears in unread feed" "200" "FAIL" "not found"
    fi
else
    echo "  ↷ No task_assigned notification found to test mark-read"
fi

echo ""

# =============================================================================
# Phase 14: Mark all read
# =============================================================================
echo "=========================================="
echo "Phase 14: Mark all read"
echo "=========================================="
echo ""

act_as "$TOKEN_B"

RESPONSE=$(api_json POST "/notifications/mark-all-read" '{}')
assert_api "User B mark-all-read → 200" "200" "$RESPONSE"

RESPONSE=$(api_get "/notifications/unread-count")
BODY=$(body_from_response "$RESPONSE")
UNREAD=$(json_value "$BODY" "unread_count")
if [ "$UNREAD" = "0" ]; then
    print_result "Unread count == 0 after mark-all-read" "200" "200" "ok"
else
    print_result "Unread count == 0 after mark-all-read" "200" "FAIL" "unread=$UNREAD"
fi

echo ""

# =============================================================================
# Phase 15: Cross-user isolation (A cannot operate on B's notifications)
# =============================================================================
echo "=========================================="
echo "Phase 15: Cross-user isolation"
echo "=========================================="
echo ""

act_as "$TOKEN_A"

# Try to mark B's notification as read — should get 404
if [ -n "$NOTIF_ID" ]; then
    RESPONSE=$(api_json POST "/notifications/$NOTIF_ID/mark-read" '{}')
    assert_api "User A cannot mark B's notification → 404" "404" "$RESPONSE"

    RESPONSE=$(api_json POST "/notifications/$NOTIF_ID/mark-unread" '{}')
    assert_api "User A cannot mark-unread B's notification → 404" "404" "$RESPONSE"

    RESPONSE=$(api_delete "/notifications/$NOTIF_ID")
    assert_api "User A cannot delete B's notification → 404" "404" "$RESPONSE"
fi

echo ""

# =============================================================================
# Phase 16: Delete notification (User B deletes one)
# =============================================================================
echo "=========================================="
echo "Phase 16: Delete notification"
echo "=========================================="
echo ""

act_as "$TOKEN_B"

# Find any notification to delete
DEL_NOTIF_ID=$(find_notification_id_for_current_user "task_completed" "$TASK_ID")
if [ -n "$DEL_NOTIF_ID" ]; then
    RESPONSE=$(api_delete "/notifications/$DEL_NOTIF_ID")
    assert_api "User B deletes notification → 200" "200" "$RESPONSE"

    # Verify it's gone from list
    RESPONSE=$(api_get "/notifications?per_page=100")
    BODY=$(body_from_response "$RESPONSE")
    if echo "$BODY" | grep -q "$DEL_NOTIF_ID"; then
        print_result "Deleted notification absent from list" "200" "FAIL" "still present"
    else
        print_result "Deleted notification absent from list" "200" "200" "ok"
    fi
else
    echo "  ↷ No notification found to delete"
fi

echo ""

# =============================================================================
# Phase 17: Filtering (unread, mentions, assignments)
# =============================================================================
echo "=========================================="
echo "Phase 17: Notification filters"
echo "=========================================="
echo ""

act_as "$TOKEN_B"

# Unread filter (all are read from mark-all-read)
RESPONSE=$(api_get "/notifications?unread=1")
assert_api "GET /notifications?unread=1 → 200" "200" "$RESPONSE"

# Mentions filter
RESPONSE=$(api_get "/notifications?filter=mentions")
assert_api "GET /notifications?filter=mentions → 200" "200" "$RESPONSE"
BODY=$(body_from_response "$RESPONSE")
# B should have at least 2 comment_mention notifications
MENTIONS_COUNT=$(BODY_INPUT="$BODY" php -r '
    $b = json_decode(getenv("BODY_INPUT"), true);
    $c = 0;
    foreach ($b["data"] ?? [] as $n) {
        if (str_contains($n["type"] ?? "", "mention")) $c++;
    }
    echo $c;
')
if [ "${MENTIONS_COUNT:-0}" -ge 2 ]; then
    print_result "Mentions filter returns ≥2 mention notifications" "200" "200" "count=$MENTIONS_COUNT"
else
    print_result "Mentions filter returns ≥2 mention notifications" "200" "FAIL" "count=$MENTIONS_COUNT"
fi

# Assignments filter
RESPONSE=$(api_get "/notifications?filter=assignments")
assert_api "GET /notifications?filter=assignments → 200" "200" "$RESPONSE"
BODY=$(body_from_response "$RESPONSE")
ASSIGN_COUNT=$(BODY_INPUT="$BODY" php -r '
    $b = json_decode(getenv("BODY_INPUT"), true);
    $c = 0;
    foreach ($b["data"] ?? [] as $n) {
        if (str_contains($n["type"] ?? "", "assign")) $c++;
    }
    echo $c;
')
if [ "${ASSIGN_COUNT:-0}" -ge 2 ]; then
    print_result "Assignments filter returns ≥2 assign notifications" "200" "200" "count=$ASSIGN_COUNT"
else
    print_result "Assignments filter returns ≥2 assign notifications" "200" "FAIL" "count=$ASSIGN_COUNT"
fi

echo ""

# =============================================================================
# Phase 18: Unauthenticated access → 401
# =============================================================================
echo "=========================================="
echo "Phase 18: Unauthenticated access"
echo "=========================================="
echo ""

OLD_TOKEN="$TOKEN"
TOKEN=""

RESPONSE=$(api_get "/notifications")
if assert_unauthorized "$RESPONSE"; then
    print_result "GET /notifications without auth → 401" "401" "401" "ok"
else
    print_result "GET /notifications without auth → 401" "401" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

RESPONSE=$(api_get "/notifications/unread-count")
if assert_unauthorized "$RESPONSE"; then
    print_result "GET /unread-count without auth → 401" "401" "401" "ok"
else
    print_result "GET /unread-count without auth → 401" "401" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

RESPONSE=$(api_json POST "/notifications/mark-all-read" '{}')
if assert_unauthorized "$RESPONSE"; then
    print_result "POST /mark-all-read without auth → 401" "401" "401" "ok"
else
    print_result "POST /mark-all-read without auth → 401" "401" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

TOKEN="$OLD_TOKEN"

echo ""

# =============================================================================
# Cleanup
# =============================================================================
echo "=========================================="
echo "Cleanup"
echo "=========================================="

act_as "$TOKEN_A"
[ -n "${TASK_ID_4:-}" ] && api_delete "/tasks/$TASK_ID_4" > /dev/null 2>&1 || true
[ -n "${TASK_ID_3:-}" ] && api_delete "/tasks/$TASK_ID_3" > /dev/null 2>&1 || true
[ -n "${TASK_ID_2:-}" ] && api_delete "/tasks/$TASK_ID_2" > /dev/null 2>&1 || true
[ -n "${TASK_ID:-}" ] && api_delete "/tasks/$TASK_ID" > /dev/null 2>&1 || true
[ -n "${COLUMN_ID:-}" ] && api_delete "/columns/$COLUMN_ID" > /dev/null 2>&1 || true
[ -n "${SECTION_ID:-}" ] && api_delete "/sections/$SECTION_ID" > /dev/null 2>&1 || true
[ -n "${PROJECT_ID:-}" ] && api_delete "/projects/$PROJECT_ID" > /dev/null 2>&1 || true
[ -n "${INVITE_WORKSPACE_ID:-}" ] && api_delete "/workspaces/$INVITE_WORKSPACE_ID" > /dev/null 2>&1 || true
[ -n "${WORKSPACE_ID:-}" ] && api_delete "/workspaces/$WORKSPACE_ID" > /dev/null 2>&1 || true
[ -n "${USER_B_ID:-}" ] && api_delete "/users/$USER_B_ID" > /dev/null 2>&1 || true
[ -n "${USER_C_ID:-}" ] && api_delete "/users/$USER_C_ID" > /dev/null 2>&1 || true

echo ""
print_summary_and_exit
