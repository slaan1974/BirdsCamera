#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/test_harness.sh"

section "Team 2 — Configuration Values"

T2_RESULTS=$(grep -oP '^RESULTS_DIR="\K[^"]+' "${REPO_DIR}/team2" | head -1)
T2_MODEL=$(grep -oP '^MODEL_NAME="\K[^"]+' "${REPO_DIR}/team2")
T2_SERVICE=$(grep -oP '^SERVICE_NAME="\K[^"]+' "${REPO_DIR}/team2")
T2_VENV=$(grep -oP '^VENV_DIR="\K[^"]+' "${REPO_DIR}/team2")
T2_BASE=$(grep -oP '^BASE_DIR="\K[^"]+' "${REPO_DIR}/team2")

assert_ok "RESULTS_DIR is defined" "test -n '${T2_RESULTS}'"
assert_ok "MODEL_NAME is yolo26n" "test '${T2_MODEL}' = 'yolo26n'"
assert_ok "SERVICE_NAME is ultralytics-wildlife.service" "echo '${T2_SERVICE}' | grep -q 'wildlife'"
assert_ok "VENV_DIR is defined" "test -n '${T2_VENV}'"
assert_ok "BASE_DIR is ultralytics-local" "echo '${T2_BASE}' | grep -q 'ultralytics-local'"

section "Team 2 — DATA_DRIVE Override"

assert_ok "DATA_DRIVE redirects to /mnt/wildlife-data/team2" \
    "grep -q 'DATA_DRIVE_MOUNT}/team2' '${REPO_DIR}/team2'"

assert_ok "setup_data_drive has fallback to BASE_DIR/results" \
    "grep -q 'RESULTS_DIR.*BASE_DIR.*/results' '${REPO_DIR}/team2'"

section "Team 2 — UTF-8 Encoding Safeguards"

assert_ok "script exports PYTHONIOENCODING=utf-8" \
    "grep -q 'PYTHONIOENCODING=utf-8' '${REPO_DIR}/team2'"
assert_ok "script exports LC_ALL=C.UTF-8" \
    "grep -q 'LC_ALL=C.UTF-8' '${REPO_DIR}/team2'"

section "Team 2 — Inference Script (wildlife detection)"

assert_ok "inference script uses picamera2" \
    "grep -q 'from picamera2 import Picamera2' '${REPO_DIR}/team2'"
assert_ok "inference script uses YOLO" \
    "grep -q 'from ultralytics import YOLO' '${REPO_DIR}/team2'"
assert_ok "inference script has target_classes filter" \
    "grep -q 'target_classes' '${REPO_DIR}/team2'"
assert_ok "inference script saves latest.jpg" \
    "grep -q 'latest.jpg' '${REPO_DIR}/team2'"
assert_ok "inference script has FIFO cleanup" \
    "grep -q 'fifo_cleanup' '${REPO_DIR}/team2'"
assert_ok "inference script writes detections.jsonl" \
    "grep -q 'detections.jsonl' '${REPO_DIR}/team2'"
assert_ok "inference script reads config.json" \
    "grep -q 'config.json' '${REPO_DIR}/team2'"

section "Team 2 — Web Gallery Script"

assert_ok "gallery has live view endpoint" \
    "grep -q 'send_latest' '${REPO_DIR}/team2'"
assert_ok "gallery has class filter" \
    "grep -q 'class_filter' '${REPO_DIR}/team2'"
assert_ok "gallery has settings modal" \
    "grep -q 'settingsModal' '${REPO_DIR}/team2'"
assert_ok "gallery serves on port 5000" \
    "grep -q 'PORT = 5000' '${REPO_DIR}/team2'"

section "Team 2 — Systemd Services"

assert_ok "inference service has Restart=always" \
    "grep -q 'Restart=always' '${REPO_DIR}/team2'"
assert_ok "gallery service has Restart=always" \
    "grep -q 'Restart=always' '${REPO_DIR}/team2'"

section "Team 2 — Sentinel / Idempotency"

assert_ok "script uses SENTINEL_APT for idempotency" \
    "grep -q 'SENTINEL_APT' '${REPO_DIR}/team2'"
assert_ok "script has --force flag to redo steps" \
    "grep -qF -- '--force' '${REPO_DIR}/team2'"

section "Team 2 — Output Commands"

T2_USAGE=$(bash "${REPO_DIR}/team2" --help 2>/dev/null || true)
assert_ok "usage output contains status" "echo '${T2_USAGE}' | grep -q 'status'"
assert_ok "usage output contains wildlife" "echo '${T2_USAGE}' | grep -q 'wildlife'"
assert_ok "usage output contains DATA_DRIVE" "echo '${T2_USAGE}' | grep -q 'DATA_DRIVE'"
assert_ok "usage output contains camera-test" "echo '${T2_USAGE}' | grep -q 'camera-test'"
assert_ok "usage output contains update" "echo '${T2_USAGE}' | grep -q 'update'"

summary
