#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/test_harness.sh"

SDD="${REPO_DIR}/setup-data-drive.sh"

section "Data Drive — Configuration Constants"

assert_ok "DATA_MOUNT is /mnt/wildlife-data" \
    "grep -q 'DATA_MOUNT=\"/mnt/wildlife-data\"' '${SDD}'"
assert_ok "SENTINEL_FILE is .wildlife_data_sentinel" \
    "grep -q 'SENTINEL_FILE=\"\.wildlife_data_sentinel\"' '${SDD}'"
assert_ok "TARGET_SIZE_GB is 6" \
    "grep -q 'TARGET_SIZE_GB=6' '${SDD}'"
assert_ok "LABEL is WILDLIFE_DATA" \
    "grep -q 'LABEL=\"WILDLIFE_DATA\"' '${SDD}'"

section "Data Drive — Team Paths"

assert_ok "TEAM1_RESULTS defined" "grep -q 'TEAM1_RESULTS=' '${SDD}'"
assert_ok "TEAM2_RESULTS defined" "grep -q 'TEAM2_RESULTS=' '${SDD}'"
assert_ok "TEAM1_RESULTS_DRIVE defined" "grep -q 'TEAM1_RESULTS_DRIVE=' '${SDD}'"
assert_ok "TEAM2_RESULTS_DRIVE defined" "grep -q 'TEAM2_RESULTS_DRIVE=' '${SDD}'"

section "Data Drive — Function Definitions"

assert_ok "has detect_devices function" "grep -qE '^detect_devices\(\)' '${SDD}'"
assert_ok "has data_drive_status function" "grep -qE '^data_drive_status\(\)' '${SDD}'"
assert_ok "has build_initramfs function" "grep -qE '^build_initramfs\(\)' '${SDD}'"
assert_ok "has cmd_sd_prepare function" "grep -qE '^cmd_sd_prepare\(\)' '${SDD}'"
assert_ok "has cmd_sd_mount function" "grep -qE '^cmd_sd_mount\(\)' '${SDD}'"
assert_ok "has cmd_sync function" "grep -qE '^cmd_sync\(\)' '${SDD}'"
assert_ok "has cmd_remove function" "grep -qE '^cmd_remove\(\)' '${SDD}'"
assert_ok "has cmd_sd function" "grep -qE '^cmd_sd\(\)' '${SDD}'"
assert_ok "has cmd_docs function" "grep -qE '^cmd_docs\(\)' '${SDD}'"

section "Data Drive — Idempotency"

assert_ok "checks for existing partition before resize" \
    "grep -q 'mmcblk0p3' '${SDD}'"
assert_ok "checks sentinel before formatting" \
    "grep -q 'SENTINEL_FILE' '${SDD}'"

section "Data Drive — Initramfs"

assert_ok "build_initramfs copies e2fsck" \
    "grep -q 'e2fsck' '${SDD}'"
assert_ok "build_initramfs copies resize2fs" \
    "grep -q 'resize2fs' '${SDD}'"
assert_ok "build_initramfs copies fdisk" \
    "grep -q 'fdisk' '${SDD}'"
assert_ok "build_initramfs copies mkfs.exfat" \
    "grep -q 'mkfs.exfat' '${SDD}'"
assert_ok "build_initramfs copies busybox" \
    "grep -q 'busybox' '${SDD}'"

assert_ok "initramfs /init uses switch_root" \
    "grep -q 'switch_root' '${SDD}'"
assert_ok "initramfs /init uses resize2fs -M" \
    "grep -q 'resize2fs -M' '${SDD}'"
assert_ok "initramfs /init uses parted resizepart" \
    "grep -q 'resizepart' '${SDD}'"

section "Data Drive — Mount + Symlinks"

assert_ok "cmd_sd_mount writes sentinel if missing" \
    "grep -q 'SENTINEL_FILE' '${SDD}'"
assert_ok "cmd_sd_mount creates team subdirectories" \
    "grep -q 'mkdir -p.*team1\|TEAM1_RESULTS_DRIVE.*TEAM2_RESULTS_DRIVE' '${SDD}'"
assert_ok "cmd_sd_mount adds fstab entry" \
    "grep -q 'fstab' '${SDD}'"
assert_ok "cmd_sd_mount creates symlinks" \
    "grep -q 'ln -sf' '${SDD}'"

section "Data Drive — Sync Command"

assert_ok "cmd_sync runs sync" \
    "grep -q 'sync' '${SDD}'"
assert_ok "cmd_sync shows Windows instructions" \
    "grep -qi 'Windows' '${SDD}'"
assert_ok "cmd_sync offers to unmount" \
    "grep -q 'umount' '${SDD}'"

section "Data Drive — Remove Command"

assert_ok "cmd_remove removes symlinks" \
    "grep -q 'Symlink' '${SDD}'"
assert_ok "cmd_remove removes fstab entry" \
    "grep -q 'fstab' '${SDD}'"
assert_ok "cmd_remove removes initramfs files" \
    "grep -q 'initrd.img' '${SDD}'"
assert_ok "cmd_remove cleans config.txt" \
    "grep -q 'config.txt' '${SDD}'"

section "Data Drive — Docs Subcommand"

if grep -qE '^\s+docs\)' "${SDD}"; then
    assert_ok "setup-data-drive.sh has docs subcommand" "true"
    assert_ok "docs subcommand copies PLAN.md" \
        "grep -q 'PLAN.md' '${SDD}'"
    assert_ok "docs subcommand copies TEST.md" \
        "grep -q 'TEST.md' '${SDD}'"
    assert_ok "docs subcommand copies to data mount" \
        "grep -q 'DATA_MOUNT' '${SDD}'"
else
    skip_test "docs subcommand" "not yet added"
fi

section "Data Drive — Usage Output"

SDD_USAGE=$(bash "${SDD}" --help 2>/dev/null || true)
assert_ok "usage contains sd command" "echo '${SDD_USAGE}' | grep -q 'sd'"
assert_ok "usage contains status command" "echo '${SDD_USAGE}' | grep -q 'status'"
assert_ok "usage contains sync command" "echo '${SDD_USAGE}' | grep -q 'sync'"
assert_ok "usage contains remove command" "echo '${SDD_USAGE}' | grep -q 'remove'"
assert_ok "usage contains docs command" "echo '${SDD_USAGE}' | grep -q 'docs'"

summary
