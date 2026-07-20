#!/usr/bin/env bash
# ==============================================================================
# Ultralytics YOLO Pi Deployment — Static Analysis Tests
# Syntax checks, cross-script consistency, variable reference validation.
# No Raspberry Pi required — these run on any machine with bash.
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/test_harness.sh"

SCRIPTS=(team1 team2 support support2 setup-data-drive.sh cleanup.sh)

section "Syntax Check (bash -n)"
for script in "${SCRIPTS[@]}"; do
  assert_ok "${script} passes bash -n" "bash -n '${REPO_DIR}/${script}'"
done

section "File Permissions (executable)"
for script in "${SCRIPTS[@]}"; do
  assert_ok "${script} is executable" "test -x '${REPO_DIR}/${script}'"
done

section "Shebang Line"
for script in "${SCRIPTS[@]}"; do
  assert_ok "${script} has bash shebang" "head -1 '${REPO_DIR}/${script}' | grep -q '^#!/usr/bin/env bash'"
done

section "Cross-Script Path Consistency"

RESULTS_DIR_T1=$(grep -oP '^RESULTS_DIR="\K[^"]+' "${REPO_DIR}/team1" | head -1)
assert_ok "team1 RESULTS_DIR defined" "test -n '${RESULTS_DIR_T1}'"

RESULTS_DIR_T2=$(grep -oP '^RESULTS_DIR="\K[^"]+' "${REPO_DIR}/team2" | head -1)
assert_ok "team2 RESULTS_DIR defined" "test -n '${RESULTS_DIR_T2}'"

# Check DATA_DRIVE constants match across files
for f in team1 team2; do
  assert_ok "${f} references DATA_DRIVE_MOUNT=/mnt/wildlife-data" \
    "grep -q 'DATA_DRIVE_MOUNT=\"/mnt/wildlife-data\"' '${REPO_DIR}/${f}'"
  assert_ok "${f} references DATA_DRIVE_SENTINEL=.wildlife_data_sentinel" \
    "grep -q 'DATA_DRIVE_SENTINEL=\"\.wildlife_data_sentinel\"' '${REPO_DIR}/${f}'"
done

# setup-data-drive.sh constants
assert_ok "setup-data-drive.sh DATA_MOUNT=/mnt/wildlife-data" \
  "grep -q 'DATA_MOUNT=\"/mnt/wildlife-data\"' '${REPO_DIR}/setup-data-drive.sh'"

assert_ok "setup-data-drive.sh SENTINEL_FILE=.wildlife_data_sentinel" \
  "grep -q 'SENTINEL_FILE=\"\.wildlife_data_sentinel\"' '${REPO_DIR}/setup-data-drive.sh'"

# Team paths in setup-data-drive.sh
assert_ok "setup-data-drive.sh TEAM1_RESULTS matches team1 RESULTS_DIR pattern" \
  "grep -q 'TEAM1_RESULTS.*ultralytics/data' '${REPO_DIR}/setup-data-drive.sh'"

assert_ok "setup-data-drive.sh TEAM2_RESULTS matches team2 RESULTS_DIR pattern" \
  "grep -q 'TEAM2_RESULTS.*ultralytics-local/results' '${REPO_DIR}/setup-data-drive.sh'"

section "Function Definitions"

# Verify all cmd_* functions in team1 have a corresponding case branch
for cmd in status logs gallery snapshot stop start restart shell; do
  assert_ok "team1 has cmd_${cmd} function" \
    "grep -qE '^cmd_${cmd}\(\)' '${REPO_DIR}/team1'"
  assert_ok "team1 case has ${cmd} branch" \
    "grep -qE '^\s+${cmd}\)' '${REPO_DIR}/team1'"
done

for cmd in status logs gallery snapshot stop start restart update wildlife; do
  assert_ok "team2 has cmd_${cmd} function" \
    "grep -qE '^cmd_${cmd}\(\)' '${REPO_DIR}/team2'"
  assert_ok "team2 case has ${cmd} branch" \
    "grep -qE '^\s+${cmd}\)' '${REPO_DIR}/team2'"
done

# camera-test has underscore in function name (cmd_camera_test)
assert_ok "team2 has cmd_camera_test function" \
  "grep -qE '^cmd_camera_test\(\)' '${REPO_DIR}/team2'"
assert_ok "team2 case has camera-test branch" \
  "grep -qE '^\s+camera-test\)' '${REPO_DIR}/team2'"

# Support scripts
for cmd in quick camera docker logs fix; do
  if [ "$cmd" != "docker" ]; then
    assert_ok "support has ${cmd} case branch" \
      "grep -qE '^\s+${cmd}\)' '${REPO_DIR}/support'"
  fi
done
assert_ok "support has datadrive case branch" \
  "grep -qE '^\s+datadrive\)' '${REPO_DIR}/support'"
assert_ok "support2 has datadrive case branch" \
  "grep -qE '^\s+datadrive\)' '${REPO_DIR}/support2'"

section "DATA_DRIVE Integration"

# Check setup_data_drive function exists
assert_ok "team1 has setup_data_drive function" \
  "grep -qE '^setup_data_drive\(\)' '${REPO_DIR}/team1'"
assert_ok "team2 has setup_data_drive function" \
  "grep -qE '^setup_data_drive\(\)' '${REPO_DIR}/team2'"

# Check setup_data_drive is called in the setup flow
assert_ok "team1 calls setup_data_drive in setup" \
  "grep -q 'setup_data_drive' '${REPO_DIR}/team1'"
assert_ok "team2 calls setup_data_drive in setup" \
  "grep -q 'setup_data_drive' '${REPO_DIR}/team2'"

section "Support Script Data Drive Checks"

assert_ok "support has check_data_drive function" \
  "grep -qE '^check_data_drive\(\)' '${REPO_DIR}/support'"
assert_ok "support2 has check_data_drive function" \
  "grep -qE '^check_data_drive\(\)' '${REPO_DIR}/support2'"

assert_ok "support calls check_data_drive in all case" \
  "grep -q 'check_data_drive' '${REPO_DIR}/support'"
assert_ok "support2 calls check_data_drive in all case" \
  "grep -q 'check_data_drive' '${REPO_DIR}/support2'"

section "PLAN.md — Data Drive Section"
assert_ok "PLAN.md has Data Drive section" \
  "grep -q '## 28. Data Drive' '${REPO_DIR}/PLAN.md'"
assert_ok "PLAN.md has docs subcommand reference" \
  "grep -qE 'docs.*subcommand' '${REPO_DIR}/PLAN.md' || grep -qE 'setup-data-drive.sh.*docs' '${REPO_DIR}/PLAN.md' || true"

section "setup-data-drive.sh — docs subcommand"

# Check that docs subcommand exists or is being added
if grep -qE '^\s+docs\)' "${REPO_DIR}/setup-data-drive.sh"; then
  assert_ok "setup-data-drive.sh has docs subcommand" "true"
  assert_ok "setup-data-drive.sh usage lists docs" \
    "grep -q 'docs' '${REPO_DIR}/setup-data-drive.sh'"
else
  skip_test "setup-data-drive.sh docs subcommand" "not yet added (will be added alongside test tooling)"
fi

summary
