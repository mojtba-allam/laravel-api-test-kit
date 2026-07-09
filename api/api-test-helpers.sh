#!/bin/bash

# Load test-kit configuration (PROJECT_ROOT, BASE_URL, auth adapter, etc.)
_API_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config/bootstrap.sh
source "$_API_HELPERS_DIR/../config/bootstrap.sh"
unset _API_HELPERS_DIR

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0
TOTAL=0
declare -a FAILED_TESTS=()

print_result() {
    local test_name="$1"
    local expected_statuses="$2"
    local actual_status="$3"
    local response="$4"

    TOTAL=$((TOTAL + 1))

    if [[ " $expected_statuses " == *" $actual_status "* ]]; then
        echo -e "${GREEN}✓${NC} $test_name (HTTP $actual_status)"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗${NC} $test_name (Expected: $expected_statuses, Got: $actual_status)"
        echo "   Response: $(echo "$response" | head -c 300)"
        FAILED=$((FAILED + 1))
        FAILED_TESTS+=("$test_name")
    fi
}

body_from_response() { echo "$1" | sed '$d'; }
status_from_response() { echo "$1" | tail -1; }

json_value() {
    local json="$1"
    local key="$2"

    JSON_INPUT="$json" KEY_INPUT="$key" php -r '
        $json = getenv("JSON_INPUT");
        $key = getenv("KEY_INPUT");
        $data = json_decode($json, true);
        if (! is_array($data)) {
            exit;
        }

        $segments = explode(".", $key);
        $value = $data;
        foreach ($segments as $segment) {
            if ($segment === "first") {
                $value = is_array($value) ? reset($value) : null;
                continue;
            }
            if (! is_array($value) || ! array_key_exists($segment, $value)) {
                exit;
            }
            $value = $value[$segment];
        }

        if (is_bool($value)) {
            echo $value ? "true" : "false";
        } elseif (is_scalar($value)) {
            echo $value;
        }
    '
}

api_json() {
    local method="$1"
    local path="$2"
    local payload="${3:-}"
    [ -z "$payload" ] && payload='{}'

    curl -s ${CURL_TLS_FLAG} -w "\n%{http_code}" -X "$method" "$BASE_URL$path" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -d "$payload"
}

api_get() {
    local path="$1"

    curl -s ${CURL_TLS_FLAG} -w "\n%{http_code}" -X GET "$BASE_URL$path" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/json"
}

api_delete() {
    local path="$1"

    curl -s ${CURL_TLS_FLAG} -w "\n%{http_code}" -X DELETE "$BASE_URL$path" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/json"
}

api_multipart() {
    local method="$1"
    local path="$2"
    shift 2

    curl -s ${CURL_TLS_FLAG} -w "\n%{http_code}" -X "$method" "$BASE_URL$path" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/json" \
        "$@"
}

assert_api() {
    local name="$1"
    local expected="$2"
    local response="$3"
    print_result "$name" "$expected" "$(status_from_response "$response")" "$(body_from_response "$response")"
}

# ============================================================================
# Token minting — fast, deterministic auth for API suites.
#
# Uses MINT_TOKEN_SCRIPT adapter (see scripts/adapters/README.md) unless
# AUTH_STRATEGY=http_login is set.
#
# On success sets MINTED_TOKEN and MINTED_USER_ID and returns 0.
# Usage: mint_token_for <email> [make_admin]
# ============================================================================

_resolve_mint_script() {
    if [[ "$MINT_TOKEN_SCRIPT" = /* ]]; then
        echo "$MINT_TOKEN_SCRIPT"
    else
        echo "$TEST_KIT_ROOT/$MINT_TOKEN_SCRIPT"
    fi
}

mint_token_for() {
    local email="$1"
    local make_admin="${2:-}"
    local mint_script args=() output

    if [ "$AUTH_STRATEGY" = "http_login" ]; then
        mint_token_via_http "$email" "$make_admin"
        return $?
    fi

    mint_script=$(_resolve_mint_script)
    if [ ! -f "$mint_script" ]; then
        echo -e "${RED}mint_token_for: adapter not found: $mint_script${NC}" >&2
        return 1
    fi

    args=(--email="$email")
    if [ -n "$make_admin" ] || echo "$email" | grep -qi "admin"; then
        args+=(--admin)
    fi

    output=$(PROJECT_ROOT="$PROJECT_ROOT" "$PHP_BIN" "$mint_script" "${args[@]}" 2>/dev/null)

    MINTED_USER_ID=$(echo "$output" | grep -oE '__UID__[^_]+__TOK__' | sed 's/__UID__//; s/__TOK__//')
    MINTED_TOKEN=$(echo "$output" | grep -oE '__TOK__[^_]+__END__' | sed 's/__TOK__//; s/__END__//')

    [ -n "$MINTED_TOKEN" ]
}

# HTTP login fallback when AUTH_STRATEGY=http_login
mint_token_via_http() {
    local email="$1"
    local password="${TEST_USER_PASSWORD:-TestPass123!}"
    local response body status token

    response=$(curl -s ${CURL_TLS_FLAG} -w "\n%{http_code}" -X POST "$BASE_URL/auth/login" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"password\":\"$password\"}")
    status=$(status_from_response "$response")
    body=$(body_from_response "$response")

    if [ "$status" != "200" ]; then
        curl -s ${CURL_TLS_FLAG} -X POST "$BASE_URL/auth/register" \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"API Test\",\"email\":\"$email\",\"password\":\"$password\",\"password_confirmation\":\"$password\"}" > /dev/null 2>&1 || true
        response=$(curl -s ${CURL_TLS_FLAG} -w "\n%{http_code}" -X POST "$BASE_URL/auth/login" \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -d "{\"email\":\"$email\",\"password\":\"$password\"}")
        body=$(body_from_response "$response")
    fi

    token=$(json_value "$body" "data.token")
    [ -z "$token" ] && token=$(json_value "$body" "token")
    MINTED_TOKEN="$token"
    MINTED_USER_ID=$(json_value "$body" "data.user.id")
    [ -z "$MINTED_USER_ID" ] && MINTED_USER_ID=$(json_value "$body" "user.id")
    [ -n "$MINTED_TOKEN" ]
}

test_email() {
    local prefix="${1:-api-test}"
    echo "${prefix}-$(date +%s)-$RANDOM@${TEST_EMAIL_DOMAIN}"
}

json_id() {
    local json="$1"
    local id
    id=$(json_value "$json" "$JSON_ID_PATH")
    if [ -z "$id" ] && [ "$JSON_ID_PATH" != "id" ]; then
        id=$(json_value "$json" "id")
    fi
    echo "$id"
}

login_admin() {
    local email
    email=$(test_email "api-test-admin")

    if mint_token_for "$email" "admin"; then
        TOKEN="$MINTED_TOKEN"
        USER_ID="$MINTED_USER_ID"
        echo "✓ Auth token obtained (test user: $email)"
        return 0
    fi

    echo -e "${RED}Failed to obtain auth token${NC}"
    exit 1
}

# Login as a super-admin user (mints a token directly and grants Super Admin).
login_as_super_admin() {
    local email
    email=$(test_email "api-super-admin")

    if mint_token_for "$email" "admin"; then
        LAST_LOGIN_USER_ID="$MINTED_USER_ID"
        echo "$MINTED_TOKEN"
        return 0
    fi

    echo -e "${RED}login_as_super_admin: failed${NC}" >&2
    return 1
}

create_workspace() {
    local suffix="$1"
    local response
    local unique_suffix="$suffix-$(date +%s)-$RANDOM"
    response=$(api_json POST "/workspaces" "{\"name\":\"ApiWorkspace-$unique_suffix\",\"description\":\"API test workspace\",\"visibility\":\"private\"}")
    WORKSPACE_ID=$(json_id "$(body_from_response "$response")")
}

create_project() {
    local suffix="$1"
    local response
    local unique_suffix="$suffix-$(date +%s)-$RANDOM"
    response=$(api_json POST "/projects" "{\"name\":\"ApiProject-$unique_suffix\",\"description\":\"API test project\",\"workspace_id\":\"$WORKSPACE_ID\"}")
    PROJECT_ID=$(json_id "$(body_from_response "$response")")
}

create_section() {
    local suffix="$1"
    local response
    local unique_suffix="$suffix-$(date +%s)-$RANDOM"
    response=$(api_json POST "/sections" "{\"name\":\"ApiSection-$unique_suffix\",\"project_id\":\"$PROJECT_ID\",\"sort_order\":1}")
    SECTION_ID=$(json_id "$(body_from_response "$response")")
}

create_column() {
    local suffix="$1"
    local response
    local unique_suffix="$suffix-$(date +%s)-$RANDOM"
    response=$(api_json POST "/columns" "{\"name\":\"ApiColumn-$unique_suffix\",\"section_id\":\"$SECTION_ID\",\"sort_order\":1}")
    COLUMN_ID=$(json_id "$(body_from_response "$response")")
}

create_task() {
    local suffix="$1"
    local var_name="${2:-TASK_ID}"
    local response task_id
    local unique_suffix="$suffix-$(date +%s)-$RANDOM"
    response=$(api_json POST "/tasks" "{\"title\":\"ApiTask-$unique_suffix\",\"column_id\":\"$COLUMN_ID\",\"priority\":\"medium\"}")
    task_id=$(json_id "$(body_from_response "$response")")
    printf -v "$var_name" '%s' "$task_id"
}

# ============================================
# Phase 1.1: Response Validation Functions
# ============================================

assert_json_field() {
    local json="$1"
    local field="$2"
    
    JSON_INPUT="$json" FIELD_INPUT="$field" php -r '
        $json = getenv("JSON_INPUT");
        $field = getenv("FIELD_INPUT");
        $data = json_decode($json, true);
        if (!is_array($data)) {
            exit(1);
        }

        $segments = explode(".", $field);
        $value = $data;
        foreach ($segments as $segment) {
            if ($segment === "first") {
                $value = is_array($value) ? reset($value) : null;
                continue;
            }
            if (!is_array($value) || !array_key_exists($segment, $value)) {
                exit(1);
            }
            $value = $value[$segment];
        }

        // Field exists if we got here
        exit(0);
    '
}

assert_json_value() {
    local json="$1"
    local field="$2"
    local expected="$3"
    local actual
    actual=$(json_value "$json" "$field")
    [ "$actual" = "$expected" ]
}

assert_json_type() {
    local json="$1"
    local field="$2"
    local expected_type="$3"
    
    JSON_INPUT="$json" FIELD_INPUT="$field" TYPE_INPUT="$expected_type" php -r '
        $json = getenv("JSON_INPUT");
        $field = getenv("FIELD_INPUT");
        $expectedType = getenv("TYPE_INPUT");
        $data = json_decode($json, true);
        
        $segments = explode(".", $field);
        $value = $data;
        foreach ($segments as $segment) {
            if ($segment === "first") {
                $value = is_array($value) ? reset($value) : null;
                continue;
            }
            if (!is_array($value) || !array_key_exists($segment, $value)) {
                exit(1);
            }
            $value = $value[$segment];
        }
        
        $actualType = gettype($value);
        if ($actualType === "integer" || $actualType === "double") {
            $actualType = "number";
        }
        if ($actualType === "boolean") {
            $actualType = "boolean";
        }
        if ($actualType === "array") {
            $actualType = is_numeric(array_key_first($value)) ? "array" : "object";
        }
        
        exit($actualType === $expectedType ? 0 : 1);
    '
}

assert_json_structure() {
    local json="$1"
    shift
    local fields=("$@")
    
    for field in "${fields[@]}"; do
        if ! assert_json_field "$json" "$field"; then
            return 1
        fi
    done
    return 0
}

assert_json_array_count() {
    local json="$1"
    local field="$2"
    local expected_count="$3"
    
    local count
    count=$(JSON_INPUT="$json" FIELD_INPUT="$field" php -r '
        $json = getenv("JSON_INPUT");
        $field = getenv("FIELD_INPUT");
        $data = json_decode($json, true);
        
        $segments = explode(".", $field);
        $value = $data;
        foreach ($segments as $segment) {
            if (!is_array($value) || !array_key_exists($segment, $value)) {
                exit;
            }
            $value = $value[$segment];
        }
        
        echo is_array($value) ? count($value) : 0;
    ')
    
    [ "$count" -eq "$expected_count" ]
}

assert_json_contains() {
    local json="$1"
    local field="$2"
    local search_value="$3"
    
    JSON_INPUT="$json" FIELD_INPUT="$field" SEARCH_INPUT="$search_value" php -r '
        $json = getenv("JSON_INPUT");
        $field = getenv("FIELD_INPUT");
        $searchValue = getenv("SEARCH_INPUT");
        $data = json_decode($json, true);
        
        $segments = explode(".", $field);
        $value = $data;
        foreach ($segments as $segment) {
            if (!is_array($value) || !array_key_exists($segment, $value)) {
                exit(1);
            }
            $value = $value[$segment];
        }
        
        if (!is_array($value)) {
            exit(1);
        }
        
        exit(in_array($searchValue, $value, true) ? 0 : 1);
    '
}

# ============================================
# Phase 1.2: Database Verification Functions
# ============================================

assert_db_has() {
    local table="$1"
    local where_clause="$2"
    
    local count
    count=$(cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="echo DB::table('$table')->whereRaw(\"$where_clause\")->count();" 2>/dev/null || echo "0")
    [ "$count" -gt 0 ]
}

assert_db_missing() {
    local table="$1"
    local where_clause="$2"
    
    local count
    count=$(cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="echo DB::table('$table')->whereRaw(\"$where_clause\")->count();" 2>/dev/null || echo "0")
    [ "$count" -eq 0 ]
}

assert_db_count() {
    local table="$1"
    local where_clause="$2"
    local expected_count="$3"
    
    local count
    count=$(cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="echo DB::table('$table')->whereRaw(\"$where_clause\")->count();" 2>/dev/null || echo "0")
    [ "$count" -eq "$expected_count" ]
}

assert_db_field_value() {
    local table="$1"
    local id="$2"
    local field="$3"
    local expected_value="$4"
    
    local actual_value
    actual_value=$(cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="echo DB::table('$table')->where('id', '$id')->value('$field');" 2>/dev/null || echo "")
    [ "$actual_value" = "$expected_value" ]
}

assert_db_relationship() {
    local parent_table="$1"
    local parent_id="$2"
    local child_table="$3"
    local foreign_key="$4"
    
    local count
    count=$(cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="echo DB::table('$child_table')->where('$foreign_key', '$parent_id')->count();" 2>/dev/null || echo "0")
    [ "$count" -gt 0 ]
}

assert_db_timestamp() {
    local table="$1"
    local id="$2"
    local timestamp_field="$3"
    
    local value
    value=$(cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="echo DB::table('$table')->where('id', '$id')->value('$timestamp_field');" 2>/dev/null || echo "")
    [ -n "$value" ] && [ "$value" != "null" ]
}

# ============================================
# Phase 1.3: Test Data Isolation Functions
# ============================================

generate_unique_email() {
    test_email "test"
}

create_test_user() {
    local suffix="${1:-$(date +%s)}"
    local email
    email=$(generate_unique_email)
    
    local response
    response=$(api_json POST "/users" "{\"name\":\"TestUser-$suffix\",\"email\":\"$email\",\"password\":\"password123\",\"password_confirmation\":\"password123\"}")
    
    TEST_USER_ID=$(json_value "$(body_from_response "$response")" "data.id")
    if [ -z "$TEST_USER_ID" ]; then
        TEST_USER_ID=$(json_value "$(body_from_response "$response")" "id")
    fi
    TEST_USER_EMAIL="$email"
}

create_test_workspace() {
    local suffix="${1:-$(date +%s)-$RANDOM}"
    local response
    response=$(api_json POST "/workspaces" "{\"name\":\"TestWorkspace-$suffix\",\"description\":\"Test workspace\",\"visibility\":\"private\"}")
    
    TEST_WORKSPACE_ID=$(json_value "$(body_from_response "$response")" "data.id")
    if [ -z "$TEST_WORKSPACE_ID" ]; then
        TEST_WORKSPACE_ID=$(json_value "$(body_from_response "$response")" "id")
    fi
}

create_test_project() {
    local suffix="${1:-$(date +%s)-$RANDOM}"
    local workspace_id="${2:-$TEST_WORKSPACE_ID}"
    local response
    response=$(api_json POST "/projects" "{\"name\":\"TestProject-$suffix\",\"description\":\"Test project\",\"workspace_id\":\"$workspace_id\"}")
    
    TEST_PROJECT_ID=$(json_value "$(body_from_response "$response")" "data.id")
    if [ -z "$TEST_PROJECT_ID" ]; then
        TEST_PROJECT_ID=$(json_value "$(body_from_response "$response")" "id")
    fi
}

cleanup_test_user() {
    [ -n "${TEST_USER_ID:-}" ] && api_delete "/users/$TEST_USER_ID" > /dev/null 2>&1 || true
}

cleanup_common_records() {
    # Cleanup test-specific records
    [ -n "${TEST_USER_ID:-}" ] && api_delete "/users/$TEST_USER_ID" > /dev/null 2>&1 || true
    [ -n "${TEST_PROJECT_ID:-}" ] && api_delete "/projects/$TEST_PROJECT_ID" > /dev/null 2>&1 || true
    [ -n "${TEST_WORKSPACE_ID:-}" ] && api_delete "/workspaces/$TEST_WORKSPACE_ID" > /dev/null 2>&1 || true
    
    # Cleanup original records
    [ -n "${TASK_ID:-}" ] && api_delete "/tasks/$TASK_ID" > /dev/null 2>&1 || true
    [ -n "${TASK_ID_2:-}" ] && api_delete "/tasks/$TASK_ID_2" > /dev/null 2>&1 || true
    [ -n "${TASK_ID_3:-}" ] && api_delete "/tasks/$TASK_ID_3" > /dev/null 2>&1 || true
    [ -n "${COLUMN_ID:-}" ] && api_delete "/columns/$COLUMN_ID" > /dev/null 2>&1 || true
    [ -n "${SECTION_ID:-}" ] && api_delete "/sections/$SECTION_ID" > /dev/null 2>&1 || true
    [ -n "${PROJECT_ID:-}" ] && api_delete "/projects/$PROJECT_ID" > /dev/null 2>&1 || true
    [ -n "${WORKSPACE_ID:-}" ] && api_delete "/workspaces/$WORKSPACE_ID" > /dev/null 2>&1 || true
}

# ============================================
# Phase 1.4: Validation Testing Functions
# ============================================

assert_validation_error() {
    local response="$1"
    local status
    status=$(status_from_response "$response")
    [ "$status" = "422" ]
}

assert_validation_field() {
    local response="$1"
    local field="$2"
    local body
    body=$(body_from_response "$response")
    
    # Check if errors object contains the field
    JSON_INPUT="$body" FIELD_INPUT="$field" php -r '
        $json = getenv("JSON_INPUT");
        $field = getenv("FIELD_INPUT");
        $data = json_decode($json, true);
        
        if (isset($data["errors"][$field])) {
            exit(0);
        }
        if (isset($data["message"]) && strpos($data["message"], $field) !== false) {
            exit(0);
        }
        exit(1);
    '
}

assert_unauthorized() {
    local response="$1"
    local status
    status=$(status_from_response "$response")
    [ "$status" = "401" ]
}

assert_forbidden() {
    local response="$1"
    local status
    status=$(status_from_response "$response")
    [ "$status" = "403" ]
}

assert_not_found() {
    local response="$1"
    local status
    status=$(status_from_response "$response")
    [ "$status" = "404" ]
}

print_summary_and_exit() {
    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo -e "Total:  $TOTAL"
    echo -e "${GREEN}Passed: $PASSED${NC}"
    echo -e "${RED}Failed: $FAILED${NC}"
    echo ""

    if [ "$FAILED" -gt 0 ]; then
        echo -e "${RED}Failed tests:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
        exit 1
    fi

    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
}

# ============================================
# Phase: Multi-user authorization test helpers
# ============================================

# Generic login helper. Returns a non-empty token string on stdout, or
# returns non-zero (and logs to stderr) when a token could not be obtained.
# Mints a Sanctum token directly (find-or-create verified user) so it works
# for both seeded users (e.g. admin@test.local) and fresh identities, without
# depending on passwords or the email-verification HTTP flow.
login_as() {
    local email="$1"

    if mint_token_for "$email"; then
        LAST_LOGIN_USER_ID="$MINTED_USER_ID"
        echo "$MINTED_TOKEN"
        return 0
    fi

    echo -e "${RED}login_as: failed to obtain token for $email${NC}" >&2
    return 1
}

# Switch the active identity by assigning the global TOKEN used by
# api_get / api_json / api_delete.
act_as() { TOKEN="$1"; }

# Direct member addition for test fixture setup (optional).
# Set ADD_MEMBER_SCRIPT in config/test.env to a PHP script: add-member.php <project_id> <user_id>
add_member_direct() {
    local project_id="$1"
    local user_id="$2"
    local script="${ADD_MEMBER_SCRIPT:-}"

    if [ -z "$script" ]; then
        echo -e "${YELLOW}add_member_direct: ADD_MEMBER_SCRIPT not configured — skipping${NC}" >&2
        return 0
    fi

    if [[ "$script" != /* ]]; then
        script="$TEST_KIT_ROOT/$script"
    fi

    if [ -f "$script" ]; then
        PROJECT_ROOT="$PROJECT_ROOT" "$PHP_BIN" "$script" "$project_id" "$user_id" > /dev/null 2>&1
    fi
}

# expected_gap and skip_case helpers (no pass/fail increment)
# Does NOT increment PASSED/FAILED.
expected_gap() {
    local name="$1" detail="$2"
    echo -e "${YELLOW}➖ EXPECTED-GAP${NC} $name — $detail"
}

# Explicit skip for undefined abilities (➖) or empty policies.
# Does NOT increment PASSED/FAILED.
skip_case() {
    local name="$1" reason="$2"
    echo -e "  ↷ SKIP $name — $reason"
}
