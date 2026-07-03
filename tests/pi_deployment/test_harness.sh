#!/usr/bin/env bash
# ==============================================================================
# Ultralytics YOLO Pi Deployment — Test Harness
# Shared assertion functions, counters, and helpers for all pi_deployment tests.
# Source this file from individual test scripts.
# ==============================================================================
set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Counters ────────────────────────────────────────────────────────────────────
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

# ── Assertion Functions ─────────────────────────────────────────────────────────

assert_ok() {
    TOTAL=$((TOTAL + 1))
    local label="$1"
    shift
    if eval "$@"; then
        PASSED=$((PASSED + 1))
        echo -e "  ${GREEN}✓${NC} ${label}"
    else
        FAILED=$((FAILED + 1))
        echo -e "  ${RED}✗${NC} ${label}"
    fi
}

assert_nok() {
    TOTAL=$((TOTAL + 1))
    local label="$1"
    shift
    if ! eval "$@"; then
        PASSED=$((PASSED + 1))
        echo -e "  ${GREEN}✓${NC} ${label}"
    else
        FAILED=$((FAILED + 1))
        echo -e "  ${RED}✗${NC} ${label}"
    fi
}

assert_eq() {
    TOTAL=$((TOTAL + 1))
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [ "$actual" = "$expected" ]; then
        PASSED=$((PASSED + 1))
        echo -e "  ${GREEN}✓${NC} ${label}"
    else
        FAILED=$((FAILED + 1))
        echo -e "  ${RED}✗${NC} ${label}"
        echo -e "      Expected: ${expected}"
        echo -e "      Actual:   ${actual}"
    fi
}

assert_contains() {
    TOTAL=$((TOTAL + 1))
    local label="$1"
    local haystack="$2"
    local needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        PASSED=$((PASSED + 1))
        echo -e "  ${GREEN}✓${NC} ${label}"
    else
        FAILED=$((FAILED + 1))
        echo -e "  ${RED}✗${NC} ${label}"
        echo -e "      Expected to contain: ${needle}"
    fi
}

assert_not_contains() {
    TOTAL=$((TOTAL + 1))
    local label="$1"
    local haystack="$2"
    local needle="$3"
    if ! echo "$haystack" | grep -qF "$needle"; then
        PASSED=$((PASSED + 1))
        echo -e "  ${GREEN}✓${NC} ${label}"
    else
        FAILED=$((FAILED + 1))
        echo -e "  ${RED}✗${NC} ${label}"
        echo -e "      Expected NOT to contain: ${needle}"
    fi
}

assert_file_exists() {
    TOTAL=$((TOTAL + 1))
    local label="$1"
    local path="$2"
    if [ -f "$path" ]; then
        PASSED=$((PASSED + 1))
        echo -e "  ${GREEN}✓${NC} ${label}"
    else
        FAILED=$((FAILED + 1))
        echo -e "  ${RED}✗${NC} ${label} (not found: ${path})"
    fi
}

skip_test() {
    TOTAL=$((TOTAL + 1))
    SKIPPED=$((SKIPPED + 1))
    local label="$1"
    local reason="${2:-no reason given}"
    echo -e "  ${YELLOW}⊘${NC} ${label} (skipped: ${reason})"
}

# ── Test Suite Functions ────────────────────────────────────────────────────────

section() {
    echo ""
    echo -e "${BOLD}── $1 ──${NC}"
}

summary() {
    local total=$((PASSED + FAILED))
    echo ""
    echo -e "${BOLD}═══════════════════════ Results ═══════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}${PASSED} passed${NC}  |  ${RED}${FAILED} failed${NC}  |  ${YELLOW}${SKIPPED} skipped${NC}  |  ${total} total"
    echo ""
    if [ "$FAILED" -gt 0 ]; then
        return 1
    fi
    return 0
}

# ── Mock Helpers ────────────────────────────────────────────────────────────────

# Create a temporary directory for test isolation
make_temp() {
    mktemp -d "/tmp/pi_test_XXXXXX"
}

# Clean up a temp directory
clean_temp() {
    local d="$1"
    [ -d "$d" ] && rm -rf "$d"
}

# Run a command in a sub-shell with mocked PATH
mock_cmd() {
    local mock_dir
    mock_dir=$(mktemp -d "/tmp/pi_mock_XXXXXX")
    local name="$1"
    local exit_code="${2:-0}"
    local output="${3:-}"
    cat > "${mock_dir}/${name}" << 'MOCKEOF'
#!/usr/bin/env bash
MOCKEOF
    echo "exit ${exit_code}" >> "${mock_dir}/${name}"
    [ -n "$output" ] && sed -i "2i echo '${output}'" "${mock_dir}/${name}"
    chmod +x "${mock_dir}/${name}"
    echo "$mock_dir"
}
