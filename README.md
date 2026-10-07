<div align="center">

# 🐦 BirdsCamera

**YOLO wildlife camera for Raspberry Pi 4 — local inference, live web gallery, zero cloud.**

[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-245%20%2F%206%20suites-brightgreen.svg)](TEST.md)
[![Raspberry Pi](https://img.shields.io/badge/hardware-Raspberry%20Pi%204-c51a4a.svg)](PLAN.md)

</div>

---

## Overview

BirdsCamera turns a **Raspberry Pi 4 + Camera Module v2** into an autonomous wildlife camera. It captures frames on a timer, runs **Ultralytics YOLO** inference locally, and only writes an image to disk when a target (person, cat, bird) is detected. Saved detections and a continuously updated live view are served by a built-in **web gallery** on port 5000 — viewable from any browser on your network.

Everything runs **natively on the Pi** (Python venv + systemd). No containers, no cloud, no account.

### Features

- **Local YOLO inference** — NCNN/OpenVINO export for best Pi 4 performance, runs from systemd on every boot
- **Event-driven storage** — frames without detections are discarded; only matches are saved (timestamped JPEG + JSONL log)
- **Live web gallery** — live view, detection grid, class filter, lightbox, configurable capture/refresh intervals and camera resolution
- **Windows-friendly data drive** — optional exFAT partition so you can pull the SD card and copy images from Windows
- **Diagnostics** — `support`/`support2` scripts check system, camera, services, model, results, network and data drive
- **245 tests** — 6 bash suites (static + unit) runnable on any machine, no Pi required

## Hardware

| Item | Requirement |
|------|-------------|
| Board | Raspberry Pi 4 (2GB+, 4GB/8GB recommended) |
| Camera | Pi Camera Module v2 (IMX219, CSI connector) |
| OS | Raspberry Pi OS Bookworm **64-bit** (Lite recommended) |
| Storage | 32GB+ SD card (SSD boot recommended for 24/7 operation) |
| Network | Wi-Fi or Ethernet (SSH access) |

## Repository Layout

| Path | Purpose |
|------|---------|
| `team2` | **Supported path** — native (non-Docker) deployment: setup, update, status, services |
| `support2` | Diagnostics for the native deployment |
| `setup-data-drive.sh` | Creates an exFAT data partition on the SD card (boot-time resize + mount/symlinks) |
| `run-pi-tests.sh` | Test runner — `--static`, `--unit`, `--integration`, `--all`, `--list` |
| `tests/pi_deployment/` | 6 test suites (static, team1, team2, support, data drive, cleanup) |
| `PLAN.md` | Full Pi 4 deployment guide, architecture, changelog, investigation findings |
| `TEST.md` | Test plan and current test status |
| `team1`, `support`, `cleanup.sh` | Legacy Docker-based tooling (see [Docker deployment removed](#docker-deployment-removed)) |
| `ultralytics/`, `docs/` | Ultralytics YOLO library and documentation (AGPL-3.0 fork) |

## Quick Start (Native Path)

```bash
git clone https://github.com/slaan1974/BirdsCamera.git
cd BirdsCamera
./team2 setup          # ~30 min: system deps, venv, NCNN model export, systemd services
```

After a reboot the inference service and web gallery start automatically.

```bash
./team2 status         # deployment health (services, model, results, camera)
./team2 snapshot       # capture a test frame
./team2 camera-test    # validate camera hardware
./team2 logs           # follow live inference output
./team2 gallery        # web viewer on port 5000 (also runs as a service)
./team2 stop|start|restart
./team2 update         # fast re-write of embedded scripts + service restart (~2 s)
./team2 --help         # all commands
```

Open `http://<pi-ip>:5000` from any browser for the live view and detection gallery.

## Wildlife Detection

Frames are captured every **N seconds** (default 5 s, configurable) and run through YOLO:

```
[camera] → every Ns → YOLO → save latest.jpg → target match?
                                       ├─ YES → detect_YYYYMMDD_HHMMSS.jpg + detections.jsonl
                                       └─ NO  → discard silently
```

- Targets are COCO class IDs configured via `target_classes` — default `0` (person); add `15` (cat) and `16` (bird)
- Each saved image gets an on-image timestamp overlay, a timestamped filename, and a JSONL entry (classes, confidences, time)
- Settings live in `~/ultralytics-local/results/config.json`, editable from the gallery settings panel:

| Setting | Default | Description |
|---------|---------|-------------|
| `capture_interval` | `5` | Seconds between captures |
| `auto_refresh` | `10` | Web page auto-refresh interval (seconds) |
| `camera_resolution` | `1920x1080` | Camera mode (e.g. `3280x2464` for full 8MP) |
| `target_classes` | `[0]` | COCO class IDs that trigger a save |
| `max_fifo` | `1000` | Max saved detection images (oldest pruned) |
| `min_free_space_gb` | `1` | Stop saving below this free space |

## Data Drive (Optional)

`./setup-data-drive.sh sd` shrinks the root partition at boot and creates a Windows-readable **exFAT** partition labelled `WILDLIFE_DATA`. Detection images then live on a partition you can open directly in Windows File Explorer after pulling the SD card.

```bash
./setup-data-drive.sh sd        # one-time setup (reboots)
./setup-data-drive.sh status    # mount, sentinel, symlinks, fstab
./setup-data-drive.sh sync      # flush buffers before shutdown (Windows-safe)
./setup-data-drive.sh docs      # copy PLAN.md + TEST.md to the drive
./setup-data-drive.sh remove    # teardown

DATA_DRIVE=true ./team2 setup   # redirect results to /mnt/wildlife-data/team2
```

## Diagnostics

```bash
./support2            # full check: system, camera, services, model, results, network, data drive
./support2 quick      # fast overview
./support2 camera     # detailed camera test
./support2 logs       # recent service + detection logs
./support2 fix        # suggested fixes for anything detected
```

## Testing

```bash
./run-pi-tests.sh --static    # syntax + cross-script consistency (any machine)
./run-pi-tests.sh --unit      # unit suites (any machine)
./run-pi-tests.sh --all       # everything incl. Pi integration tests
./run-pi-tests.sh --list      # list suites
```

Static and unit suites (245 tests across 6 suites) run on any Linux/macOS/WSL machine — no Pi needed. See [TEST.md](TEST.md) for the full test plan, current status, and known limitations.

## Docker Deployment Removed

The original Docker-based deployment (`team1`, `docker/`, `.github/workflows/docker.yml`) **did not work reliably on the Pi** and has been removed from this repository. The **native `team2` path is the supported route** and is what all new work targets.

Docker-related logic still embedded in the legacy `team1`, `support`, and `cleanup.sh` scripts is retained untouched for reference; don't rely on it for new deployments.

## Documentation

| Document | Contents |
|----------|----------|
| [PLAN.md](PLAN.md) | Complete Pi 4 deployment guide — install, camera, performance, data drive, troubleshooting, changelog, investigation findings |
| [TEST.md](TEST.md) | Test plan, browser test matrices, current test status, known pitfalls |
| [docs/](docs/) | Ultralytics YOLO documentation (upstream) |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution guidelines |

> **Note:** Don't keep this git repository inside a synced folder (e.g. OneDrive) — sync tools can corrupt `.git`. See the investigation findings in [PLAN.md](PLAN.md) for details.

## License

This repository is a fork of [ultralytics/ultralytics](https://github.com/ultralytics/ultralytics) and is distributed under the [AGPL-3.0 License](LICENSE). Ultralytics YOLO models and code are © [Ultralytics](https://www.ultralytics.com/). See [CITATION.cff](CITATION.cff) for citation metadata.
