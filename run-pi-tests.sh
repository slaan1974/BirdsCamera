#!/usr/bin/env bash
# ==============================================================================
# Ultralytics YOLO Pi Deployment — Test Runner
# Run all Pi deployment tests with level selection.
#
# Usage:
#   ./run-pi-tests.sh                  Static + unit tests (default)
#   ./run-pi-tests.sh --static         Syntax check + cross-script consistency
#   ./run-pi-tests.sh --unit           Unit tests (no Pi required)
#   ./run-pi-tests.sh --integration    Full Pi deployment test (requires Pi/VM)
#   ./run-pi-tests.sh --all            Everything
#   ./run-pi-tests.sh --list           List available test suites
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="${SCRIPT_DIR}/tests/pi_deployment"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

OVERALL_PASSED=0
OVERALL_FAILED=0
OVERALL_SKIPPED=0

run_suite() {
  local label="$1"
  local script="$2"
  echo ""
  echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}  Suite: ${label}${NC}"
  echo -e "${BOLD}  File:  ${script}${NC}"
  echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"

  local rc=0
  bash "$script" || rc=$?

  # Parse result from summary line
  local result_line
  result_line=$(tail -5 "$script" 2> /dev/null | grep -oP '\d+ passed.*\d+ failed.*\d+ skipped' || echo "")
  local n_passed n_failed n_skipped
  n_passed=$(echo "$result_line" | grep -oP '\d+(?= passed)' || echo "0")
  n_failed=$(echo "$result_line" | grep -oP '\d+(?= failed)' || echo "0")
  n_skipped=$(echo "$result_line" | grep -oP '\d+(?= skipped)' || echo "0")

  OVERALL_PASSED=$((OVERALL_PASSED + n_passed))
  OVERALL_FAILED=$((OVERALL_FAILED + n_failed))
  OVERALL_SKIPPED=$((OVERALL_SKIPPED + n_skipped))

  if [ "$rc" -eq 0 ]; then
    echo -e "  ${GREEN}✓ Suite passed${NC}"
  else
    echo -e "  ${RED}✗ Suite FAILED${NC}"
  fi
  return $rc
}

# ── Determine which tests to run ───────────────────────────────────────────────
MODE="${1:---static}"

case "$MODE" in
  --list)
    echo ""
    echo -e "${BOLD}Available test suites:${NC}"
    echo ""
    echo "  Static tests:"
    echo "    test_static.sh              Syntax, permissions, cross-script consistency"
    echo ""
    echo "  Unit tests (no Pi required):"
    echo "    test_team1.sh               Team 1 (Docker) script tests"
    echo "    test_team2.sh               Team 2 (local) script tests"
    echo "    test_support.sh             Support + Support2 diagnostics tests"
    echo "    test_setup_data_drive.sh    Data drive setup script tests"
    echo "    test_cleanup.sh             Cleanup script tests"
    echo ""
    echo "  Integration tests (Pi/VM required):"
    echo "    test_integration.sh         Full Pi deployment end-to-end tests"
    echo ""
    echo "Usage:"
    echo "  $0                  Static + unit tests"
    echo "  $0 --static         Static analysis only"
    echo "  $0 --unit           Unit tests only"
    echo "  $0 --integration    Full Pi integration tests"
    echo "  $0 --all            Everything"
    echo "  $0 --list           Show this list"
    echo ""
    exit 0
    ;;
  --static)
    SUITES=("Static" "${TEST_DIR}/test_static.sh")
    ;;
  --unit)
    SUITES=(
      "Team 1" "${TEST_DIR}/test_team1.sh"
      "Team 2" "${TEST_DIR}/test_team2.sh"
      "Support" "${TEST_DIR}/test_support.sh"
      "Data Drive" "${TEST_DIR}/test_setup_data_drive.sh"
      "Cleanup" "${TEST_DIR}/test_cleanup.sh"
    )
    ;;
  --integration)
    SUITES=("Integration" "${TEST_DIR}/test_integration.sh")
    if [ ! -f "${TEST_DIR}/test_integration.sh" ]; then
      echo ""
      echo -e "${YELLOW}Integration test script not found.${NC}"
      echo "Create ${TEST_DIR}/test_integration.sh for full Pi deployment testing."
      echo "See TEST.md for the integration test plan."
      exit 0
    fi
    ;;
  --all)
    SUITES=(
      "Static" "${TEST_DIR}/test_static.sh"
      "Team 1" "${TEST_DIR}/test_team1.sh"
      "Team 2" "${TEST_DIR}/test_team2.sh"
      "Support" "${TEST_DIR}/test_support.sh"
      "Data Drive" "${TEST_DIR}/test_setup_data_drive.sh"
      "Cleanup" "${TEST_DIR}/test_cleanup.sh"
    )
    if [ -f "${TEST_DIR}/test_integration.sh" ]; then
      SUITES+=("Integration" "${TEST_DIR}/test_integration.sh")
    fi
    ;;
  *)
    echo "Unknown option: $1"
    echo "Usage: $0 [--static|--unit|--integration|--all|--list]"
    exit 1
    ;;
esac

# ── Run suites ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  ╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}  ║  Ultralytics YOLO  —  Pi Deployment Tests      ║${NC}"
echo -e "${BOLD}  ╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Mode: ${MODE}"
echo "  Repo: ${SCRIPT_DIR}"
echo "  Date: $(date)"
echo ""

ANY_FAILURE=0
for ((i = 0; i < ${#SUITES[@]}; i += 2)); do
  label="${SUITES[i]}"
  script="${SUITES[i + 1]}"
  run_suite "$label" "$script" || ANY_FAILURE=1
done

# ── Overall summary ────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Overall Results${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${GREEN}${OVERALL_PASSED} passed${NC}  |  ${RED}${OVERALL_FAILED} failed${NC}  |  ${YELLOW}${OVERALL_SKIPPED} skipped${NC}"
echo ""

if [ "$ANY_FAILURE" -ne 0 ]; then
  echo -e "  ${RED}Some test suites FAILED.${NC}"
  exit 1
fi
echo -e "  ${GREEN}All test suites passed.${NC}"
exit 0
