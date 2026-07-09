#!/bin/bash

# User Module API Test Suite - Enhanced
# Tests all User, Skills, and User Skills endpoints with comprehensive validation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "=========================================="
echo "User Module API Test Suite - Enhanced"
echo "=========================================="
echo ""

# Setup: Login with existing admin user
echo "Setting up test environment..."
login_admin
echo ""

# ==========================================
# Section 10C: User Module Tests
# ==========================================
echo "=========================================="
echo "10C: User Module API Tests"
echo "=========================================="
echo ""

# Test: GET /api/v1/users - List users
RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/users" \
    -H "Authorization: Bearer $TOKEN")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
print_result "GET /api/v1/users → 200 paginated user list" 200 "$STATUS" "$BODY"

# Test: POST /api/v1/users - Create user
UNIQUE_EMAIL="john-$(date +%s)@example.com"
RESPONSE=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/users" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"John Doe\",
        \"email\": \"$UNIQUE_EMAIL\",
        \"password\": \"Password123!\",
        \"password_confirmation\": \"Password123!\",
        \"job_title\": \"Developer\"
    }")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
USER_ID=$(json_value "$BODY" "id")
print_result "POST /api/v1/users → 201 or 403 (admin only)" "201 403" "$STATUS" "$BODY"

# Test: GET /api/v1/users/{user} - Show user
if [ -n "$USER_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/users/$USER_ID" \
        -H "Authorization: Bearer $TOKEN")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "GET /api/v1/users/{user} → 200 user details" 200 "$STATUS" "$BODY"
fi

# Test: PUT /api/v1/users/{user} - Update user
if [ -n "$USER_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X PUT "$BASE_URL/users/$USER_ID" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "John Updated",
            "job_title": "Senior Developer"
        }')
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "PUT /api/v1/users/{user} → 200 updates user" 200 "$STATUS" "$BODY"
fi

# Test: DELETE /api/v1/users/{user} - Delete user
if [ -n "$USER_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X DELETE "$BASE_URL/users/$USER_ID" \
        -H "Authorization: Bearer $TOKEN")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "DELETE /api/v1/users/{user} → 200 deletes user" 200 "$STATUS" "$BODY"
fi

echo ""

# ==========================================
# Section 10D: Skills & User Skills Tests
# ==========================================
echo "=========================================="
echo "10D: Skills & User Skills API Tests"
echo "=========================================="
echo ""

# Test: POST /api/v1/skills - Create skill
UNIQUE_SKILL_NAME="PHP-$(date +%s)"
RESPONSE=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/skills" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"$UNIQUE_SKILL_NAME\",
        \"category\": \"Programming\",
        \"description\": \"PHP programming language\"
    }")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
SKILL_ID=$(json_value "$BODY" "id")
print_result "POST /api/v1/skills → 201 creates skill" 201 "$STATUS" "$BODY"

# Test: GET /api/v1/skills - List skills
RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/skills" \
    -H "Authorization: Bearer $TOKEN")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
print_result "GET /api/v1/skills → 200 paginated skill list" 200 "$STATUS" "$BODY"

# Test: GET /api/v1/skills/active - Active skills only
RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/skills/active" \
    -H "Authorization: Bearer $TOKEN")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
print_result "GET /api/v1/skills/active → 200 active skills only" 200 "$STATUS" "$BODY"

# Test: GET /api/v1/skills/categories - Skill categories
RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/skills/categories" \
    -H "Authorization: Bearer $TOKEN")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
print_result "GET /api/v1/skills/categories → 200 skill categories" 200 "$STATUS" "$BODY"

# Test: GET /api/v1/skills/category/{category} - Skills by category
RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/skills/category/Programming" \
    -H "Authorization: Bearer $TOKEN")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
print_result "GET /api/v1/skills/category/{category} → 200 skills by category" 200 "$STATUS" "$BODY"

# Test: GET /api/v1/skills/search - Search skills
RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/skills/search?q=PHP" \
    -H "Authorization: Bearer $TOKEN")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
print_result "GET /api/v1/skills/search → 200 search results" 200 "$STATUS" "$BODY"

# Test: GET /api/v1/skills/{id} - Show skill
if [ -n "$SKILL_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/skills/$SKILL_ID" \
        -H "Authorization: Bearer $TOKEN")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "GET /api/v1/skills/{id} → 200 skill details" 200 "$STATUS" "$BODY"
fi

# Test: PUT /api/v1/skills/{id} - Update skill
if [ -n "$SKILL_ID" ]; then
    UPDATED_SKILL_NAME="PHP-Advanced-$(date +%s)"
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X PUT "$BASE_URL/skills/$SKILL_ID" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"$UPDATED_SKILL_NAME\",
            \"description\": \"Advanced PHP programming\"
        }")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "PUT /api/v1/skills/{id} → 200 updates skill" 200 "$STATUS" "$BODY"
fi

# Test: POST /api/v1/skills/{id}/activate - Activate skill
if [ -n "$SKILL_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/skills/$SKILL_ID/activate" \
        -H "Authorization: Bearer $TOKEN")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "POST /api/v1/skills/{id}/activate → 200 activates skill" 200 "$STATUS" "$BODY"
fi

# Test: POST /api/v1/skills/{id}/deactivate - Deactivate skill
if [ -n "$SKILL_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/skills/$SKILL_ID/deactivate" \
        -H "Authorization: Bearer $TOKEN")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "POST /api/v1/skills/{id}/deactivate → 200 deactivates skill" 200 "$STATUS" "$BODY"
fi

# Create a new user for user-skills tests
UNIQUE_TEST_EMAIL="jane-$(date +%s)@example.com"
RESPONSE=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/users" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"Jane Developer\",
        \"email\": \"$UNIQUE_TEST_EMAIL\",
        \"password\": \"Password123!\",
        \"password_confirmation\": \"Password123!\"
    }")
TEST_USER_ID=$(json_value "$(echo "$RESPONSE" | sed '$d')" "id")

# Test: POST /api/v1/users/{userId}/skills - Assign skill to user
if [ -n "$TEST_USER_ID" ] && [ -n "$SKILL_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X POST "$BASE_URL/users/$TEST_USER_ID/skills" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"skill_id\": \"$SKILL_ID\",
            \"proficiency_level\": \"intermediate\",
            \"years_of_experience\": 3
        }")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    USER_SKILL_ID=$(json_value "$BODY" "id")
    print_result "POST /api/v1/users/{userId}/skills → 201 assigns skill to user" 201 "$STATUS" "$BODY"
fi

# Test: GET /api/v1/users/{userId}/skills - User's skills
if [ -n "$TEST_USER_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/users/$TEST_USER_ID/skills" \
        -H "Authorization: Bearer $TOKEN")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "GET /api/v1/users/{userId}/skills → 200 user's skills" 200 "$STATUS" "$BODY"
fi

# Test: GET /api/v1/users/{userId}/skills/matrix - Skill matrix
if [ -n "$TEST_USER_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/users/$TEST_USER_ID/skills/matrix" \
        -H "Authorization: Bearer $TOKEN")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "GET /api/v1/users/{userId}/skills/matrix → 200 skill matrix" 200 "$STATUS" "$BODY"
fi

# Test: GET /api/v1/skills/{skillId}/users - Users with skill
if [ -n "$SKILL_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/skills/$SKILL_ID/users" \
        -H "Authorization: Bearer $TOKEN")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "GET /api/v1/skills/{skillId}/users → 200 users with skill" 200 "$STATUS" "$BODY"
fi

# Test: GET /api/v1/user-skills/{id} - User-skill details
if [ -n "$USER_SKILL_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X GET "$BASE_URL/user-skills/$USER_SKILL_ID" \
        -H "Authorization: Bearer $TOKEN")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "GET /api/v1/user-skills/{id} → 200 user-skill details" 200 "$STATUS" "$BODY"
fi

# Test: PUT /api/v1/user-skills/{id} - Update user-skill
if [ -n "$USER_SKILL_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X PUT "$BASE_URL/user-skills/$USER_SKILL_ID" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "proficiency_level": "advanced",
            "years_of_experience": 5
        }')
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "PUT /api/v1/user-skills/{id} → 200 updates user-skill" 200 "$STATUS" "$BODY"
fi

# Test: DELETE /api/v1/user-skills/{id} - Remove user-skill
if [ -n "$USER_SKILL_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X DELETE "$BASE_URL/user-skills/$USER_SKILL_ID" \
        -H "Authorization: Bearer $TOKEN")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "DELETE /api/v1/user-skills/{id} → 200 removes user-skill" 200 "$STATUS" "$BODY"
fi

# Test: DELETE /api/v1/skills/{id} - Delete skill
if [ -n "$SKILL_ID" ]; then
    RESPONSE=$(curl -sk -w "\n%{http_code}" -X DELETE "$BASE_URL/skills/$SKILL_ID" \
        -H "Authorization: Bearer $TOKEN")
    STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    print_result "DELETE /api/v1/skills/{id} → 200 deletes skill" 200 "$STATUS" "$BODY"
fi

echo ""

# ==========================================
# Phase 2: Enhanced User Module Tests
# ==========================================
echo "=========================================="
echo "Phase 2: Enhanced User Module Tests"
echo "=========================================="
echo ""

# Phase 2.1: Response Data Validation
echo "--- Phase 2.1: Response Data Validation ---"

RESPONSE=$(api_get "/users")
BODY=$(body_from_response "$RESPONSE")
STATUS=$(status_from_response "$RESPONSE")

# Validate response structure
if assert_json_field "$BODY" "data" && assert_json_field "$BODY" "meta"; then
    print_result "User list has data and meta fields" "200" "$STATUS" "$BODY"
else
    print_result "User list structure validation" "200" "FAIL" "$BODY"
fi

# Validate first user object structure
if assert_json_structure "$BODY" "data.first.id" "data.first.name" "data.first.email" "data.first.created_at"; then
    print_result "User object contains required fields" "200" "$STATUS" "$BODY"
else
    print_result "User object structure validation" "200" "FAIL" "$BODY"
fi

# Phase 2.2: Database Verification Tests
echo ""
echo "--- Phase 2.2: Database Verification ---"

# Create user for database verification
UNIQUE_EMAIL=$(generate_unique_email)
RESPONSE=$(api_json POST "/users" "{\"name\":\"DBTestUser\",\"email\":\"$UNIQUE_EMAIL\",\"password\":\"Password123!\",\"password_confirmation\":\"Password123!\"}")
DB_TEST_USER_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$DB_TEST_USER_ID" ] && DB_TEST_USER_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")

if [ -n "$DB_TEST_USER_ID" ]; then
    # Verify user exists in database
    if assert_db_has "users" "id = '$DB_TEST_USER_ID'"; then
        print_result "User exists in database after creation" "200" "200" "DB verification passed"
    else
        print_result "User exists in database" "200" "FAIL" "DB verification failed"
    fi
    
    # Verify email saved correctly
    if assert_db_field_value "users" "$DB_TEST_USER_ID" "email" "$UNIQUE_EMAIL"; then
        print_result "User email saved correctly in database" "200" "200" "DB verification passed"
    else
        print_result "User email in database" "200" "FAIL" "DB verification failed"
    fi
    
    # Verify timestamps are set
    if assert_db_timestamp "users" "$DB_TEST_USER_ID" "created_at"; then
        print_result "User created_at timestamp is set" "200" "200" "DB verification passed"
    else
        print_result "User created_at timestamp" "200" "FAIL" "DB verification failed"
    fi
    
    # Update user and verify changes persisted
    RESPONSE=$(api_json PUT "/users/$DB_TEST_USER_ID" '{"name":"UpdatedName"}')
    if assert_db_field_value "users" "$DB_TEST_USER_ID" "name" "UpdatedName"; then
        print_result "User update persisted to database" "200" "200" "DB verification passed"
    else
        print_result "User update in database" "200" "FAIL" "DB verification failed"
    fi
    
    # Cleanup
    api_delete "/users/$DB_TEST_USER_ID" > /dev/null 2>&1 || true
fi

# Phase 2.3: Validation & Error Tests
echo ""
echo "--- Phase 2.3: Validation & Error Tests ---"

# Test creating user without required fields
RESPONSE=$(api_json POST "/users" '{}')
assert_api "Create user without required fields → 422" "422" "$RESPONSE"

# Test creating user without name
RESPONSE=$(api_json POST "/users" "{\"email\":\"$(generate_unique_email)\",\"password\":\"Password123!\",\"password_confirmation\":\"Password123!\"}")
if assert_validation_error "$RESPONSE"; then
    print_result "Create user without name → 422" "422" "422" "Validation error"
else
    print_result "Create user without name → 422" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# Test creating user without email
RESPONSE=$(api_json POST "/users" '{"name":"Test","password":"Password123!","password_confirmation":"Password123!"}')
if assert_validation_error "$RESPONSE"; then
    print_result "Create user without email → 422" "422" "422" "Validation error"
else
    print_result "Create user without email → 422" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# Test creating user with invalid email format
RESPONSE=$(api_json POST "/users" '{"name":"Test","email":"invalid-email","password":"Password123!","password_confirmation":"Password123!"}')
if assert_validation_error "$RESPONSE"; then
    print_result "Create user with invalid email → 422" "422" "422" "Validation error"
else
    print_result "Create user with invalid email → 422" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# Test creating user with duplicate email
DUPLICATE_EMAIL=$(generate_unique_email)
api_json POST "/users" "{\"name\":\"First\",\"email\":\"$DUPLICATE_EMAIL\",\"password\":\"Password123!\",\"password_confirmation\":\"Password123!\"}" > /dev/null
RESPONSE=$(api_json POST "/users" "{\"name\":\"Second\",\"email\":\"$DUPLICATE_EMAIL\",\"password\":\"Password123!\",\"password_confirmation\":\"Password123!\"}")
if assert_validation_error "$RESPONSE"; then
    print_result "Create user with duplicate email → 422 or 403" "422 403" "422" "Validation error"
else
    print_result "Create user with duplicate email → 422 or 403" "422 403" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# Test password confirmation mismatch
RESPONSE=$(api_json POST "/users" "{\"name\":\"Test\",\"email\":\"$(generate_unique_email)\",\"password\":\"Password123!\",\"password_confirmation\":\"DifferentPassword!\"}")
if assert_validation_error "$RESPONSE"; then
    print_result "Create user with password mismatch → 422" "422" "422" "Validation error"
else
    print_result "Create user with password mismatch → 422" "422" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi

# Test updating non-existent user
RESPONSE=$(api_json PUT "/users/99999999" '{"name":"Test"}')
assert_api "Update non-existent user → 404" "404" "$RESPONSE"

# Test accessing users without authentication
OLD_TOKEN="$TOKEN"
TOKEN=""
RESPONSE=$(api_get "/users")
if assert_unauthorized "$RESPONSE"; then
    print_result "Access users without auth → 401" "401" "401" "Unauthorized"
else
    print_result "Access users without auth → 401" "401" "$(status_from_response "$RESPONSE")" "$(body_from_response "$RESPONSE")"
fi
TOKEN="$OLD_TOKEN"

# Phase 2.4: Business Logic Tests
echo ""
echo "--- Phase 2.4: Business Logic Tests ---"

# Create user and verify password is hashed
UNIQUE_EMAIL=$(generate_unique_email)
RESPONSE=$(api_json POST "/users" "{\"name\":\"PasswordTest\",\"email\":\"$UNIQUE_EMAIL\",\"password\":\"PlainPassword123!\",\"password_confirmation\":\"PlainPassword123!\"}")
PASSWORD_TEST_USER_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$PASSWORD_TEST_USER_ID" ] && PASSWORD_TEST_USER_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")

if [ -n "$PASSWORD_TEST_USER_ID" ]; then
    # Verify password is not stored in plain text (should be hashed)
    STORED_PASSWORD=$(cd "$PROJECT_ROOT" && $PHP_BIN artisan tinker --execute="echo DB::table('users')->where('id', '$PASSWORD_TEST_USER_ID')->value('password');" 2>/dev/null || echo "")
    if [ -n "$STORED_PASSWORD" ] && [ "$STORED_PASSWORD" != "PlainPassword123!" ]; then
        print_result "Password is hashed (not plain text)" "200" "200" "Password hashed"
    else
        print_result "Password is hashed" "200" "FAIL" "Password not hashed"
    fi
    
    api_delete "/users/$PASSWORD_TEST_USER_ID" > /dev/null 2>&1 || true
fi

# Phase 2.5: Skills Tests with Enhanced Validation
echo ""
echo "--- Phase 2.5: Enhanced Skills Tests ---"

# Create skill and validate response structure
UNIQUE_SKILL="Skill-$(date +%s)-$RANDOM"
RESPONSE=$(api_json POST "/skills" "{\"name\":\"$UNIQUE_SKILL\",\"category\":\"Testing\",\"description\":\"Test skill\"}")
SKILL_TEST_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
[ -z "$SKILL_TEST_ID" ] && SKILL_TEST_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")

if [ -n "$SKILL_TEST_ID" ]; then
    # Verify skill exists in database
    if assert_db_has "skills" "id = '$SKILL_TEST_ID'"; then
        print_result "Skill exists in database after creation" "201" "201" "DB verification passed"
    else
        print_result "Skill in database" "201" "FAIL" "DB verification failed"
    fi
    
    # Test skill search functionality
    RESPONSE=$(api_get "/skills/search?q=$UNIQUE_SKILL")
    BODY=$(body_from_response "$RESPONSE")
    if echo "$BODY" | grep -q "$UNIQUE_SKILL"; then
        print_result "Skill search returns correct results" "200" "200" "Search successful"
    else
        print_result "Skill search functionality" "200" "FAIL" "Search failed"
    fi
    
    # Test assigning skill to user
    TEST_USER_EMAIL=$(generate_unique_email)
    RESPONSE=$(api_json POST "/users" "{\"name\":\"SkillTestUser\",\"email\":\"$TEST_USER_EMAIL\",\"password\":\"Password123!\",\"password_confirmation\":\"Password123!\"}")
    SKILL_TEST_USER_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
    [ -z "$SKILL_TEST_USER_ID" ] && SKILL_TEST_USER_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")
    
    if [ -n "$SKILL_TEST_USER_ID" ]; then
        RESPONSE=$(api_json POST "/users/$SKILL_TEST_USER_ID/skills" "{\"skill_id\":\"$SKILL_TEST_ID\",\"proficiency_level\":\"intermediate\",\"years_of_experience\":2}")
        USER_SKILL_TEST_ID=$(json_value "$(body_from_response "$RESPONSE")" "data.id")
        [ -z "$USER_SKILL_TEST_ID" ] && USER_SKILL_TEST_ID=$(json_value "$(body_from_response "$RESPONSE")" "id")
        
        if [ -n "$USER_SKILL_TEST_ID" ]; then
            # Verify user_skills relationship created
            if assert_db_has "user_skills" "user_id = '$SKILL_TEST_USER_ID' AND skill_id = '$SKILL_TEST_ID'"; then
                print_result "User-skill relationship created in database" "201" "201" "DB verification passed"
            else
                print_result "User-skill relationship in database" "201" "FAIL" "DB verification failed"
            fi
            
            # Test removing skill from user
            RESPONSE=$(api_delete "/user-skills/$USER_SKILL_TEST_ID")
            if assert_db_missing "user_skills" "id = '$USER_SKILL_TEST_ID'"; then
                print_result "User-skill relationship deleted from database" "200" "200" "DB verification passed"
            else
                print_result "User-skill deletion from database" "200" "FAIL" "DB verification failed"
            fi
        fi
        
        api_delete "/users/$SKILL_TEST_USER_ID" > /dev/null 2>&1 || true
    fi
    
    api_delete "/skills/$SKILL_TEST_ID" > /dev/null 2>&1 || true
fi

# Phase 2.6: Query Parameters & Filters
echo ""
echo "--- Phase 2.6: Query Parameters & Filters ---"

# Test pagination
RESPONSE=$(api_get "/users?page=1&per_page=5")
assert_api "User list with pagination parameters" "200" "$RESPONSE"

# Test sorting
RESPONSE=$(api_get "/users?sort=name")
assert_api "User list sorted by name" "200" "$RESPONSE"

# Test search functionality
RESPONSE=$(api_get "/users?search=admin")
assert_api "User list with search parameter" "200" "$RESPONSE"

# Test skill search with query
RESPONSE=$(api_get "/skills/search?q=PHP")
assert_api "Skill search with query parameter" "200" "$RESPONSE"

# Test skills by category
RESPONSE=$(api_get "/skills/category/Programming")
assert_api "Skills filtered by category" "200" "$RESPONSE"

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
