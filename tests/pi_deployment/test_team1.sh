#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/test_harness.sh"

section "Team 1 — Configuration Values"

T1_RESULTS=$(grep -oP '^RESULTS_DIR="\K[^"]+' "${REPO_DIR}/team1" | head -1)
T1_MODEL=$(grep -oP '^MODEL_NAME="\K[^"]+' "${REPO_DIR}/team1")
T1_CONTAINER=$(grep -oP '^CONTAINER_NAME="\K[^"]+' "${REPO_DIR}/team1")
T1_SERVICE=$(grep -oP '^SERVICE_NAME="\K[^"]+' "${REPO_DIR}/team1")
T1_IMAGE=$(grep -oP '^IMAGE="\K[^"]+' "${REPO_DIR}/team1")

assert_ok "RESULTS_DIR is defined" "test -n '${T1_RESULTS}'"
assert_ok "MODEL_NAME is yolo26n" "test '${T1_MODEL}' = 'yolo26n'"
assert_ok "CONTAINER_NAME is ultralytics-pi-cam" "test '${T1_CONTAINER}' = 'ultralytics-pi-cam'"
assert_ok "SERVICE_NAME is ultralytics-docker.service" "test '${T1_SERVICE}' = 'ultralytics-docker.service'"
assert_ok "IMAGE is ultralytics/ultralytics:latest-arm64" "test '${T1_IMAGE}' = 'ultralytics/ultralytics:latest-arm64'"

section "Team 1 — DATA_DRIVE Override"

assert_ok "DATA_DRIVE redirects to /mnt/wildlife-data/team1" \
  "grep -q 'DATA_DRIVE_MOUNT}/team1' '${REPO_DIR}/team1'"

assert_ok "setup_data_drive has fallback to HOME_DIR" \
  "grep -q 'RESULTS_DIR.*HOME_DIR.*ultralytics/data' '${REPO_DIR}/team1'"

section "Team 1 — Inference Script Structure"

assert_ok "run_yolo.py contains Python imports" \
  "grep -q 'import cv2\|import time\|import os' '${REPO_DIR}/team1'"

assert_ok "run_yolo.py uses picamera2 fallback" \
  "grep -q 'picamera2' '${REPO_DIR}/team1'"
assert_ok "run_yolo.py uses YOLO" \
  "grep -q 'from ultralytics import YOLO' '${REPO_DIR}/team1'"
assert_ok "run_yolo.py saves detect_*.jpg" \
  "grep -q 'detect_' '${REPO_DIR}/team1'"
assert_ok "run_yolo.py writes detections.jsonl" \
  "grep -q 'detections.jsonl' '${REPO_DIR}/team1'"

section "Team 1 — Web Gallery Script"

assert_ok "web_gallery.py uses Python stdlib only" \
  "grep -q 'http.server' '${REPO_DIR}/team1'"
assert_ok "web_gallery.py serves on port 5000" \
  "grep -q 'PORT = 5000' '${REPO_DIR}/team1'"

section "Team 1 — Systemd Service"

assert_ok "service file has After=docker.service" \
  "grep -q 'After=docker.service' '${REPO_DIR}/team1'"
assert_ok "service file has Restart=always" \
  "grep -q 'Restart=always' '${REPO_DIR}/team1'"
assert_ok "service file runs run_yolo.py" \
  "grep -q 'run_yolo.py' '${REPO_DIR}/team1'"

section "Team 1 — Container Creation"

assert_ok "container uses --device /dev/video*" \
  "grep -q 'VIDEO_DEVICES' '${REPO_DIR}/team1'"
assert_ok "container uses --ipc=host" \
  "grep -q -- '--ipc=host' '${REPO_DIR}/team1'"
assert_ok "container uses --net=host" \
  "grep -q -- '--net=host' '${REPO_DIR}/team1'"

section "Team 1 — Output Commands"

T1_STATUS_OUTPUT=$(bash "${REPO_DIR}/team1" --help 2> /dev/null || true)
assert_ok "usage output contains status" "echo '${T1_STATUS_OUTPUT}' | grep -q 'status'"
assert_ok "usage output contains logs" "echo '${T1_STATUS_OUTPUT}' | grep -q 'logs'"
assert_ok "usage output contains DATA_DRIVE" "echo '${T1_STATUS_OUTPUT}' | grep -q 'DATA_DRIVE'"
assert_ok "usage output contains gallery" "echo '${T1_STATUS_OUTPUT}' | grep -q 'gallery'"
assert_ok "usage output contains snapshot" "echo '${T1_STATUS_OUTPUT}' | grep -q 'snapshot'"

summary
