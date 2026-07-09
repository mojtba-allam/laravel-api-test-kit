#!/bin/bash

# Master API Test Runner — runs all curl-based API suites with reporting.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_TESTS=0
FAILED_SCRIPTS=()
PASSED_SCRIPTS=()
TEMP_LOG=$(mktemp)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config/bootstrap.sh
source "$SCRIPT_DIR/../config/bootstrap.sh"

echo "=========================================="
echo "Complete API Test Suite"
echo "Project: $PROJECT_ROOT"
echo "API:     $BASE_URL"
echo "=========================================="
echo ""

# Array of test scripts
TEST_SCRIPTS=(
    "test-user-api.sh"
    "test-task-required-skills-api.sh"
    "test-workspace-api.sh"
    "test-project-api.sh"
    "test-project-teams-api.sh"
    "test-task-api.sh"
    "test-task-checklist-api.sh"
    "test-task-dependencies-api.sh"
    "test-task-hierarchy-api.sh"
    "test-task-relationships-api.sh"
    "test-task-recurring-api.sh"
    "test-task-custom-fields-api.sh"
    "test-task-templates-api.sh"
    "test-integration-api.sh"
    "test-simple-modules-api.sh"
    "test-column-api.sh"
    "test-import-export-api.sh"
    "test-timelog-api.sh"
    "test-notification-api.sh"
    "test-attachment-api.sh"
    "test-project-docs-api.sh"
    "test-activity-api.sh"
    "test-analytics-api.sh"
    "test-search-api.sh"
    "test-webhook-api.sh"
    "test-automation-api.sh"
    "test-archive-api.sh"
    "test-comment-attachment-policy-api.sh"
    "test-policy-authorization-api.sh"
    "test-project-roles-permissions-api.sh"
)

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run each test script
for script in "${TEST_SCRIPTS[@]}"; do
    if [ -f "$SCRIPT_DIR/$script" ]; then
        echo -ne "${CYAN}Running $script...${NC} "
        
        # Run test and capture output
        if "$SCRIPT_DIR/$script" > "$TEMP_LOG" 2>&1; then
            echo -e "${GREEN}✓ PASSED${NC}"
            PASSED_SCRIPTS+=("$script")
            TOTAL_PASSED=$((TOTAL_PASSED + 1))
        else
            echo -e "${RED}✗ FAILED${NC}"
            FAILED_SCRIPTS+=("$script")
            TOTAL_FAILED=$((TOTAL_FAILED + 1))
            
            # Show failure details
            echo ""
            echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${RED}FAILURE DETAILS: $script${NC}"
            echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            cat "$TEMP_LOG"
            echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            
            # Continue to next test (don't stop on failure)
        fi
    else
        echo -e "${YELLOW}⚠ $script not found - SKIPPED${NC}"
    fi
done

# Cleanup temp log
rm -f "$TEMP_LOG"

echo ""
echo "=========================================="
echo "TEST SUMMARY"
echo "=========================================="
echo -e "Total Scripts:  ${CYAN}${#TEST_SCRIPTS[@]}${NC}"
echo -e "Passed:         ${GREEN}$TOTAL_PASSED${NC}"
echo -e "Failed:         ${RED}$TOTAL_FAILED${NC}"
echo ""

if [ $TOTAL_FAILED -gt 0 ]; then
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}FAILED SCRIPTS:${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    for failed in "${FAILED_SCRIPTS[@]}"; do
        echo -e "${RED}  ✗ $failed${NC}"
    done
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${RED}Some test scripts failed!${NC}"
    exit 1
else
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ ALL TESTS PASSED!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 0
fi
