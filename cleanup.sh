#!/usr/bin/env bash
# ==============================================================================
# Docker Cleanup Script — Raspberry Pi 4
# Stops all Docker containers & services, removes containers/images/volumes
# to free disk space for Team 2 (local) deployment.
# ==============================================================================
# Usage:
#   ./cleanup.sh              Run full cleanup (interactive confirmation)
#   ./cleanup.sh --force      Run full cleanup without confirmation
#   ./cleanup.sh --status     Show Docker disk usage before cleaning
#   ./cleanup.sh --help       Show this help
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${GREEN}$(date '+%Y-%m-%d %H:%M:%S') [${SCRIPT_NAME}] [INFO]${NC}  $1"; }
warn() { echo -e "${YELLOW}$(date '+%Y-%m-%d %H:%M:%S') [${SCRIPT_NAME}] [WARN]${NC}  $1"; }
error() { echo -e "${RED}$(date '+%Y-%m-%d %H:%M:%S') [${SCRIPT_NAME}] [ERROR]${NC} $1" >&2; }
header() { echo -e "\n${BOLD}── $1 ──${NC}\n"; }

# ── Logging Setup ────────────────────────────────────────────────────────────
SCRIPT_NAME="cleanup"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/$(date +%Y%m%d_%H%M%S)_${SCRIPT_NAME}.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

SERVICE_NAME="ultralytics-docker.service"
CONTAINER_NAME="ultralytics-pi-cam"

# ── Show current Docker disk usage ─────────────────────────────────────────────
show_disk_usage() {
  header "Current Docker Disk Usage"
  if command -v docker &> /dev/null && docker info &> /dev/null 2>&1; then
    docker system df
    echo ""
    info "Containers:"
    docker ps -a --format "  {{.Names}}  {{.Status}}  {{.Size}}" 2> /dev/null || echo "  (none)"
    echo ""
    info "Images:"
    docker images --format "  {{.Repository}}:{{.Tag}}  {{.Size}}" 2> /dev/null | head -20 || echo "  (none)"
  else
    warn "Docker not running or not installed — nothing to clean"
  fi
}

# ── Cleanup Docker ─────────────────────────────────────────────────────────────
cleanup_docker() {
  header "Stopping Team 1 Service"

  if systemctl list-units --type=service --all 2> /dev/null | grep -q "${SERVICE_NAME}"; then
    info "Stopping and disabling ${SERVICE_NAME}..."
    sudo systemctl stop "${SERVICE_NAME}" 2> /dev/null || true
    sudo systemctl disable "${SERVICE_NAME}" 2> /dev/null || true
    sudo rm -f "/etc/systemd/system/${SERVICE_NAME}"
    sudo systemctl daemon-reload
    info "Service ${SERVICE_NAME} removed"
  else
    info "Service ${SERVICE_NAME} not found — skipping"
  fi

  header "Removing Docker Containers"

  # Remove Team 1 container if it exists
  if docker ps -a --format '{{.Names}}' 2> /dev/null | grep -q "${CONTAINER_NAME}"; then
    info "Removing container '${CONTAINER_NAME}'..."
    docker stop "${CONTAINER_NAME}" 2> /dev/null || true
    docker rm -f "${CONTAINER_NAME}" 2> /dev/null || true
    info "Container '${CONTAINER_NAME}' removed"
  else
    info "Container '${CONTAINER_NAME}' not found — skipping"
  fi

  # Remove ALL other containers (stopped/running)
  local running_containers=$(docker ps -q 2> /dev/null | wc -l)
  local all_containers=$(docker ps -aq 2> /dev/null | wc -l)
  if [ "$all_containers" -gt 0 ]; then
    info "Removing all Docker containers (${all_containers} total, ${running_containers} running)..."
    docker stop $(docker ps -q) 2> /dev/null || true
    docker rm $(docker ps -aq) 2> /dev/null || true
    info "All containers removed"
  else
    info "No containers to remove"
  fi

  header "Removing Team 1 Data"

  local data_dir="/home/${USER:-pi}/ultralytics/data"
  if [ -d "$data_dir" ]; then
    info "Removing Team 1 data directory: ${data_dir}"
    rm -rf "${data_dir}"
    info "Data directory removed"
  else
    info "No Team 1 data directory found — skipping"
  fi

  header "Docker System Prune"

  info "Removing unused Docker resources..."
  docker system prune -a -f --volumes 2> /dev/null || true
  info "Docker system pruned"

  # Remove specific Team 1 image
  local team1_image="ultralytics/ultralytics:latest-arm64"
  if docker image inspect "${team1_image}" &> /dev/null 2>&1; then
    info "Removing Team 1 image: ${team1_image}..."
    docker rmi -f "${team1_image}" 2> /dev/null || true
    info "Image removed"
  fi

  header "Cleanup Complete"
  show_disk_usage

  local freed
  freed=$(docker system df 2> /dev/null | awk 'NR==2 {print $4}' || echo "?")
  echo ""
  info "Disk space reclaimed. Current Docker disk usage: ${freed}"
  echo ""
  echo "  Your Pi is now ready for Team 2 (local) deployment."
  echo "  Run ./team2 to set up the local environment."
  echo ""
}

# ── Main ───────────────────────────────────────────────────────────────────────
usage() {
  echo "Usage: $0 [option]"
  echo ""
  echo "Options:"
  echo "  (none)       Show Docker disk usage, then prompt for cleanup"
  echo "  --force      Skip confirmation prompt, clean everything"
  echo "  --status     Show Docker disk usage only (no cleanup)"
  echo "  --help       Show this help"
  echo ""
  echo "What this script does:"
  echo "  1. Stops and removes ultralytics-docker.service"
  echo "  2. Removes the ultralytics-pi-cam container"
  echo "  3. Removes ALL Docker containers"
  echo "  4. Removes ~/ultralytics/data (Team 1 results)"
  echo "  5. Prunes unused Docker images, volumes, and cache"
  echo "  6. Removes the ultralytics/ultralytics:latest-arm64 image"
  echo ""
}

case "${1:-interactive}" in
  --status | -s)
    show_disk_usage
    ;;
  --force | -f)
    cleanup_docker
    ;;
  interactive)
    show_disk_usage
    echo ""
    echo "${BOLD}WARNING:${NC} This will:"
    echo "  • Remove Team 1 systemd service"
    echo "  • Delete ALL Docker containers (running and stopped)"
    echo "  • Delete ~/ultralytics/data (Team 1 detection results)"
    echo "  • Remove all Docker images, volumes, and build cache"
    echo "  • Remove the ultralytics/ultralytics:latest-arm64 image"
    echo ""
    read -r -p "Are you sure? [y/N] " response
    case "$response" in
      [yY][eE][sS] | [yY])
        cleanup_docker
        ;;
      *)
        echo "Cancelled."
        exit 0
        ;;
    esac
    ;;
  --help | -h)
    usage
    ;;
  *)
    echo "Unknown option: $1"
    usage
    exit 1
    ;;
esac
