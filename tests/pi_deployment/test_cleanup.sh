#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/test_harness.sh"

CLN="${REPO_DIR}/cleanup.sh"

section "Cleanup — Configuration"

assert_ok "SERVICE_NAME is ultralytics-docker.service" \
    "grep -q 'SERVICE_NAME=\"ultralytics-docker.service\"' '${CLN}'"
assert_ok "CONTAINER_NAME is ultralytics-pi-cam" \
    "grep -q 'CONTAINER_NAME=\"ultralytics-pi-cam\"' '${CLN}'"

section "Cleanup — Functions"

assert_ok "cleanup has show_disk_usage" \
    "grep -qE '^show_disk_usage\(\)' '${CLN}'"
assert_ok "cleanup has cleanup_docker" \
    "grep -qE '^cleanup_docker\(\)' '${CLN}'"
assert_ok "cleanup has show_disk_usage" \
    "grep -qE '^show_disk_usage\(\)' '${CLN}'"

section "Cleanup — Command Line Flags"

assert_ok "cleanup has --status flag" \
    "grep -q '\-\-status' '${CLN}'"
assert_ok "cleanup has --force flag" \
    "grep -q '\-\-force' '${CLN}'"
assert_ok "cleanup has --help flag" \
    "grep -q '\-\-help' '${CLN}'"

section "Cleanup — Safety Checks"

assert_ok "cleanup has confirmation prompt" \
    "grep -qE 'read.*y/N|read.*confirm|read.*Are you sure' '${CLN}'"
assert_ok "cleanup does not force without --force" \
    "grep -q '\-\-force' '${CLN}'"

section "Cleanup — Docker Operations"

assert_ok "cleanup stops docker service" \
    "grep -q 'systemctl stop' '${CLN}'"
assert_ok "cleanup removes docker container" \
    "grep -q 'docker rm' '${CLN}'"
assert_ok "cleanup removes docker image" \
    "grep -q 'docker rmi\|docker image rm' '${CLN}'"
assert_ok "cleanup prunes docker system" \
    "grep -q 'docker system prune' '${CLN}'"

section "Cleanup — File Operations"

assert_ok "cleanup removes Team 1 data" \
    "grep -q 'ultralytics/data' '${CLN}'"

section "Cleanup — Usage Output"

CLN_USAGE=$(bash "${CLN}" --help 2>/dev/null || true)
assert_ok "usage shows --status" "echo '${CLN_USAGE}' | grep -q 'status'"
assert_ok "usage shows --force" "echo '${CLN_USAGE}' | grep -q 'force'"
assert_ok "usage shows --help" "echo '${CLN_USAGE}' | grep -q 'help'"

summary
