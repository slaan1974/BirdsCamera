#!/usr/bin/env bash
# ==============================================================================
# Ultralytics YOLO Pi Deployment — Support Script Tests
# Tests for both support (Team 1) and support2 (Team 2) diagnostics.
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/test_harness.sh"

section "Support — Configuration Values"

assert_ok "support has CONTAINER_NAME" \
    "grep -q 'CONTAINER_NAME=' '${REPO_DIR}/support'"
assert_ok "support has SERVICE_NAME" \
    "grep -q 'SERVICE_NAME=' '${REPO_DIR}/support'"
assert_ok "support has RESULTS_DIR" \
    "grep -q 'RESULTS_DIR=' '${REPO_DIR}/support'"

section "Support — Check Functions"

assert_ok "support has check_system function" \
    "grep -qE '^check_system\(\)' '${REPO_DIR}/support'"
assert_ok "support has check_camera function" \
    "grep -qE '^check_camera\(\)' '${REPO_DIR}/support'"
assert_ok "support has check_docker function" \
    "grep -qE '^check_docker\(\)' '${REPO_DIR}/support'"
assert_ok "support has check_service function" \
    "grep -qE '^check_service\(\)' '${REPO_DIR}/support'"
assert_ok "support has check_model function" \
    "grep -qE '^check_model\(\)' '${REPO_DIR}/support'"
assert_ok "support has check_results function" \
    "grep -qE '^check_results\(\)' '${REPO_DIR}/support'"
assert_ok "support has check_network function" \
    "grep -qE '^check_network\(\)' '${REPO_DIR}/support'"
assert_ok "support has check_data_drive function" \
    "grep -qE '^check_data_drive\(\)' '${REPO_DIR}/support'"

section "Support — Diagnostic Logic"

# Check pass/fail/warn patterns
assert_ok "support uses log_passed" "grep -q 'log_passed' '${REPO_DIR}/support'"
assert_ok "support uses log_failed" "grep -q 'log_failed' '${REPO_DIR}/support'"
assert_ok "support uses log_warn" "grep -q 'log_warn' '${REPO_DIR}/support'"
assert_ok "support uses log_info" "grep -q 'log_info' '${REPO_DIR}/support'"

# Check data drive checking logic
assert_ok "support check_data_drive checks mountpoint" \
    "grep -q 'mountpoint -q' '${REPO_DIR}/support'"
assert_ok "support check_data_drive checks sentinel" \
    "grep -q 'SENTINEL' '${REPO_DIR}/support'"
assert_ok "support check_data_drive checks fstab" \
    "grep -q 'fstab' '${REPO_DIR}/support'"
assert_ok "support check_data_drive checks symlinks" \
    "grep -q 'Symlink' '${REPO_DIR}/support'"

section "Support — Output Commands"

SUPPORT_USAGE=$(bash "${REPO_DIR}/support" --help 2>/dev/null || true)
assert_ok "support usage contains quick" "echo '${SUPPORT_USAGE}' | grep -q 'quick'"
assert_ok "support usage contains camera" "echo '${SUPPORT_USAGE}' | grep -q 'camera'"
assert_ok "support usage contains docker" "echo '${SUPPORT_USAGE}' | grep -q 'docker'"
assert_ok "support usage contains datadrive" "echo '${SUPPORT_USAGE}' | grep -q 'datadrive'"
assert_ok "support usage contains fix" "echo '${SUPPORT_USAGE}' | grep -q 'fix'"
assert_ok "support usage contains logs" "echo '${SUPPORT_USAGE}' | grep -q 'logs'"

section "Support2 — Configuration Values"

assert_ok "support2 has SERVICE_NAME" \
    "grep -q 'SERVICE_NAME=' '${REPO_DIR}/support2'"
assert_ok "support2 has RESULTS_DIR" \
    "grep -q 'RESULTS_DIR=' '${REPO_DIR}/support2'"
assert_ok "support2 has GALLERY_SERVICE_NAME" \
    "grep -q 'GALLERY_SERVICE_NAME=' '${REPO_DIR}/support2'"

section "Support2 — Check Functions"

assert_ok "support2 has check_system function" \
    "grep -qE '^check_system\(\)' '${REPO_DIR}/support2'"
assert_ok "support2 has check_camera function" \
    "grep -qE '^check_camera\(\)' '${REPO_DIR}/support2'"
assert_ok "support2 has check_service function" \
    "grep -qE '^check_service\(\)' '${REPO_DIR}/support2'"
assert_ok "support2 has check_model function" \
    "grep -qE '^check_model\(\)' '${REPO_DIR}/support2'"
assert_ok "support2 has check_results function" \
    "grep -qE '^check_results\(\)' '${REPO_DIR}/support2'"
assert_ok "support2 has check_network function" \
    "grep -qE '^check_network\(\)' '${REPO_DIR}/support2'"
assert_ok "support2 has check_data_drive function" \
    "grep -qE '^check_data_drive\(\)' '${REPO_DIR}/support2'"

section "Support2 — Data Drive Check Logic"

assert_ok "support2 check_data_drive checks mountpoint" \
    "grep -q 'mountpoint -q' '${REPO_DIR}/support2'"
assert_ok "support2 check_data_drive checks sentinel" \
    "grep -q 'SENTINEL' '${REPO_DIR}/support2'"
assert_ok "support2 check_data_drive checks fstab" \
    "grep -q 'fstab' '${REPO_DIR}/support2'"
assert_ok "support2 check_data_drive checks symlinks" \
    "grep -q 'Symlink' '${REPO_DIR}/support2'"

section "Support2 — Output Commands"

S2_USAGE=$(bash "${REPO_DIR}/support2" --help 2>/dev/null || true)
assert_ok "support2 usage contains quick" "echo '${S2_USAGE}' | grep -q 'quick'"
assert_ok "support2 usage contains camera" "echo '${S2_USAGE}' | grep -q 'camera'"
assert_ok "support2 usage contains datadrive" "echo '${S2_USAGE}' | grep -q 'datadrive'"
assert_ok "support2 usage contains fix" "echo '${S2_USAGE}' | grep -q 'fix'"
assert_ok "support2 usage contains logs" "echo '${S2_USAGE}' | grep -q 'logs'"

summary
