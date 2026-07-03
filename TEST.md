# Ultralytics YOLO — Raspberry Pi 4 Deployment Test Plan

## Overview

This document defines the test plan for the Pi 4 deployment scripts. Tests are organized into three levels:

| Level | Flag | Environment | Purpose |
|-------|------|:-----------:|---------|
| **Static** | `--static` | Any machine | Syntax checks, cross-script consistency, no hardware needed |
| **Unit** | `--unit` | Any machine | Script logic validation via sourcing + mock data |
| **Integration** | `--integration` | Pi 4 / VM | Full end-to-end deployment, camera, inference, data drive |

---

## Running Tests

```bash
# Static + unit (always run these first, no Pi needed):
./run-pi-tests.sh

# Static analysis only:
./run-pi-tests.sh --static

# Unit tests only:
./run-pi-tests.sh --unit

# Full Pi deployment (requires actual Pi 4 hardware):
./run-pi-tests.sh --integration

# Everything:
./run-pi-tests.sh --all

# List suites:
./run-pi-tests.sh --list
```

---

## 1. Static Tests (`test_static.sh`)

These run on any machine with bash. No Pi required.

| # | Test | What it checks |
|---|------|----------------|
| 1.1 | Syntax check | `bash -n` passes for all 6 scripts |
| 1.2 | Executable permissions | All scripts have `+x` |
| 1.3 | Shebang line | All scripts use `#!/usr/bin/env bash` |
| 1.4 | Cross-script path consistency | `DATA_DRIVE_MOUNT`, `SENTINEL_FILE`, `RESULTS_DIR` match across team1, team2, setup-data-drive.sh |
| 1.5 | Function definitions | Every `cmd_*` function has a corresponding `case` branch |
| 1.6 | DATA_DRIVE integration | `setup_data_drive()` exists in both team1 and team2 |
| 1.7 | Support data drive checks | `check_data_drive()` exists in both support and support2 |
| 1.8 | PLAN.md section 28 | Data Drive section exists in PLAN.md |
| 1.9 | docs subcommand | setup-data-drive.sh has `docs` subcommand |

---

## 2. Unit Tests

### 2.1 Team 1 (`test_team1.sh`)

| # | Test | What it checks |
|---|------|----------------|
| 2.1.1 | Configuration | RESULTS_DIR, MODEL_NAME, CONTAINER_NAME, SERVICE_NAME, IMAGE are defined |
| 2.1.2 | DATA_DRIVE override | Setting `DATA_DRIVE=true` changes RESULTS_DIR to `/mnt/wildlife-data/team1` |
| 2.1.3 | DATA_DRIVE fallback | setup_data_drive reverts to HOME_DIR if mount missing |
| 2.1.4 | Inference script | Uses picamera2 fallback, imports YOLO, saves detect_*.jpg, writes detections.jsonl |
| 2.1.5 | Web gallery | Uses Python stdlib (http.server), serves on port 5000 |
| 2.1.6 | Systemd service | After=docker.service, Restart=always, runs run_yolo.py |
| 2.1.7 | Container creation | Maps /dev/video* devices, uses --ipc=host, --net=host |
| 2.1.8 | Usage output | --help shows all commands + DATA_DRIVE env var |

### 2.2 Team 2 (`test_team2.sh`)

| # | Test | What it checks |
|---|------|----------------|
| 2.2.1 | Configuration | RESULTS_DIR, MODEL_NAME, SERVICE_NAME, VENV_DIR, BASE_DIR are defined |
| 2.2.2 | DATA_DRIVE override | Setting `DATA_DRIVE=true` changes RESULTS_DIR to `/mnt/wildlife-data/team2` |
| 2.2.3 | DATA_DRIVE fallback | setup_data_drive reverts to BASE_DIR/results if mount missing |
| 2.2.4 | UTF-8 encoding | PYTHONIOENCODING=utf-8 and LC_ALL=C.UTF-8 exported |
| 2.2.5 | Wildlife script | Uses picamera2, YOLO, target_classes filter, latest.jpg, FIFO cleanup, config.json, camera_resolution setting |
| 2.2.6 | Web gallery | live view, class filter, settings modal (incl. camera resolution), port 5000 |
| 2.2.7 | Systemd services | Both inference and gallery have Restart=always |
| 2.2.8 | Idempotency | SENTINEL_APT, --force flag |
| 2.2.9 | Usage output | --help shows all commands + DATA_DRIVE env var |

### 2.3 Support Scripts (`test_support.sh`)

| # | Test | What it checks |
|---|------|----------------|
| 2.3.1 | Support functions | check_system, check_camera, check_docker, check_service, check_model, check_results, check_network, check_data_drive all exist |
| 2.3.2 | Data drive checks | Mountpoint, sentinel, fstab, symlinks all checked |
| 2.3.3 | Support2 functions | Same check_* functions for Team 2 context |
| 2.3.4 | Usage output | datadrive, quick, camera, fix, logs in both scripts |

### 2.4 Data Drive Setup (`test_setup_data_drive.sh`)

| # | Test | What it checks |
|---|------|----------------|
| 2.4.1 | Configuration constants | DATA_MOUNT, SENTINEL_FILE, TARGET_SIZE_GB, LABEL |
| 2.4.2 | Team paths | TEAM1_RESULTS, TEAM2_RESULTS, TEAM1_RESULTS_DRIVE, TEAM2_RESULTS_DRIVE |
| 2.4.3 | All functions | detect_devices, data_drive_status, build_initramfs, cmd_sd_prepare, cmd_sd_mount, cmd_sync, cmd_remove, cmd_sd |
| 2.4.4 | Idempotency | Checks for existing partition + sentinel before resize |
| 2.4.5 | Initramfs | Copies resize2fs, e2fsck, fdisk, mkfs.exfat, busybox |
| 2.4.6 | Resize logic | Uses switch_root, resize2fs -M, parted resizepart |
| 2.4.7 | Mount + symlinks | Creates team subdirs, fstab entry, symlinks |
| 2.4.8 | Sync command | Runs sync, shows Windows instructions |
| 2.4.9 | Remove command | Cleans symlinks, fstab, initramfs, config.txt |
| 2.4.10 | Docs subcommand | Copies PLAN.md and TEST.md to data mount |

### 2.5 Cleanup (`test_cleanup.sh`)

| # | Test | What it checks |
|---|------|----------------|
| 2.5.1 | Configuration | SERVICE_NAME, CONTAINER_NAME match team1 |
| 2.5.2 | Functions | show_disk_usage, cmd_clean, cmd_status exist |
| 2.5.3 | Flags | --status, --force, --help recognized |
| 2.5.4 | Safety | Confirmation prompt before cleanup |

---

## 3. Integration Tests (`test_integration.sh`)

Requires actual Pi 4 hardware or QEMU VM. Documented as manual test plan below.

### 3.1 Fresh Deployment

| Step | Action | Expected Result | Verification |
|------|--------|-----------------|--------------|
| 1 | Flash Raspberry Pi OS Bookworm 64-bit Lite to SD card | Boots successfully | `ssh pi@<ip>` works |
| 2 | `sudo apt update && sudo apt upgrade -y` | Packages updated | `uname -a` shows latest kernel |
| 3 | `./team1 setup` | Docker installed, image pulled, NCNN exported, service enabled | `./team1 status` shows container running |
| 4 | `./team2 setup` | Dependencies installed, venv created, model exported, services enabled | `./team2 status` shows services active |
| 5 | Reboot | All services auto-start | `./team1 status` and `./team2 status` show active |

### 3.2 Camera + Inference

| Step | Action | Expected Result | Verification |
|------|--------|-----------------|--------------|
| 1 | `./team1 snapshot` | Test frame saved | `ls -la ~/ultralytics/data/snapshot.jpg` |
| 2 | `./team2 snapshot` | Test frame saved | `ls -la ~/ultralytics-local/results/snapshot.jpg` |
| 3 | `./team1 status` | Shows detection count | Output includes "Saved frames" |
| 4 | `./team2 status` | Shows detection count | Output includes "Saved frames" |
| 5 | Point camera at a person | detect_*.jpg appears in results dir | `ls detect_*.jpg` > 0 count |

### 3.3 Data Drive

| Step | Action | Expected Result | Verification |
|------|--------|-----------------|--------------|
| 1 | `./setup-data-drive.sh sd` | Initramfs built, reboot scheduled | "Reboot required" message |
| 2 | After reboot, `./setup-data-drive.sh status` | exFAT partition mounted, sentinel present | Mount, sentinel, symlinks all ✓ |
| 3 | `DATA_DRIVE=true ./team1 setup` | Results go to exFAT | `ls /mnt/wildlife-data/team1/` |
| 4 | `DATA_DRIVE=true ./team2 update` | Results go to exFAT | `ls /mnt/wildlife-data/team2/` |
| 5 | `./setup-data-drive.sh docs` | PLAN.md + TEST.md copied to drive | `ls /mnt/wildlife-data/PLAN.md` |
| 6 | `./support datadrive` | All checks pass | Mount, FS type, sentinel, symlinks, fstab all ✓ |
| 7 | `./support2 datadrive` | Same checks for Team 2 | All ✓ |

### 3.4 Windows Access

| Step | Action | Expected Result | Verification |
|------|--------|-----------------|--------------|
| 1 | Shutdown Pi: `sudo shutdown -h now` | Pi powers off | Power LED off |
| 2 | Remove SD card, insert in Windows PC | exFAT drive appears | Drive letter assigned (e.g. F:) |
| 3 | Open WILDLIFE_DATA drive in File Explorer | Files visible | team1/, team2/, PLAN.md, TEST.md |
| 4 | Open PLAN.md in Notepad | Readable text | Markdown visible as plain text |
| 5 | Copy detect_*.jpg from team2/ to desktop | File copies successfully | JPEG opens in Photos |

### 3.5 Diagnostics

| Step | Action | Expected Result | Verification |
|------|--------|-----------------|--------------|
| 1 | `./support all` | All checks pass | Summary shows 0 failed |
| 2 | `./support2 all` | All checks pass | Summary shows 0 failed |
| 3 | `./support fix` | Fix suggestions shown | Relevant fix commands displayed |
| 4 | Simulate issue: stop container | `./support` warns about container | Shows "Container not running" |

### 3.6 Cleanup

| Step | Action | Expected Result | Verification |
|------|--------|-----------------|--------------|
| 1 | `./cleanup.sh --status` | Shows Docker disk usage | Docker image, container sizes listed |
| 2 | `./cleanup.sh --force` | Docker removed, Team 1 data removed | `docker ps` shows no containers |
| 3 | Reboot | Team 2 still works | `./team2 status` shows services active |

---

## 4. Browser Tests

### 4.1 Firefox

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 1 | Gallery loads | Navigate to `http://<pi-ip>:5000` | Page renders with Live View |
| 2 | Auto-refresh | Wait for the configured auto-refresh interval (default 10s) | Page refreshes automatically |
| 3 | Auto-refresh interval text | Look at "auto-refresh every Ns" text in Live View and Gallery | Text matches the configured `auto_refresh` value in config.json |
| 4 | Lightbox pauses auto-refresh | Click a thumbnail to open lightbox, wait 10 seconds | Page does **not** refresh; image stays visible |
| 5 | Lightbox resumes on close | Click **✖ Close** or press Esc, wait 10 seconds | Auto-refresh resumes; page reloads normally |
| 6 | Image full-size | Click a thumbnail | Lightbox opens with full-size image |
| 7 | Download | Click Download link | File download dialog appears |
| 8 | Back from full-size | On image view page (`/image/{name}`), click **← Live View** | Returns to main Live View page at `/` |
| 9 | Back to gallery | On image view page, click **← Gallery** | Returns to gallery at `/gallery` |
| 10 | Escape key | On image view page, press Esc | `history.back()` triggers, returns to previous page |
| 11 | Prev/Next on image view | On image view page, click **< Prev** or **Next >** | Previous/next detection image loads |
| 12 | Arrow keys on image view | On image view page, press **←** or **→** | Previous/next detection image loads |
| 13 | Position indicator | On image view page | Shows "Image N of M" in nav bar |
| 14 | Lightbox Prev/Next | Open lightbox, click **◀** or **▶** buttons | Adjacent image shown |
| 15 | Lightbox arrow keys | Open lightbox, press **←** or **→** | Adjacent image shown |
| 16 | Gallery 10-column grid | Open `/gallery` and inspect | Exactly 10 `.card` elements per row |
| 17 | Thumbnails render correctly | Load Live View and Gallery pages | All thumbnails show JPEG content (not broken-image icons); inspect `<img>` src points to `/thumb/{name}` |

### 4.2 Chromium / Edge

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 1 | Gallery loads | Navigate to `http://<pi-ip>:5000` | Page renders with Live View |
| 2 | Lightbox pauses auto-refresh | Click a thumbnail to open lightbox, wait 10 seconds | Page does **not** refresh; image stays visible |
| 3 | Lightbox resumes on close | Click **✖ Close** or press Esc, wait 10 seconds | Auto-refresh resumes; page reloads normally |
| 4 | Settings panel | Click gear icon | Modal opens with current config (capture_interval, max_fifo, camera_resolution, auto_refresh) |
| 5 | Change interval | Set 10s, save | Config updated |
| 6 | Change camera resolution | Set 3280×2464 (8MP Max), save | Camera re-initialises at new resolution within ~25s |
| 7 | Change auto-refresh interval | Set 30s in settings, save, wait | Page shows "auto-refresh every 30s"; page refreshes at 30s interval |
| 8 | Auto-refresh text alignment | Open Live View and Gallery, check auto-refresh text | Both pages show "auto-refresh every Ns" matching the configured value |
| 9 | Class filter | Select "Cat" from dropdown | Only cat images shown |
| 10 | Back from full-size | On image view page (`/image/{name}`), click **← Live View** | Returns to main Live View page at `/` |
| 11 | Back to gallery | On image view page, click **← Gallery** | Returns to gallery at `/gallery` |
| 12 | Escape key | On image view page, press Esc | `history.back()` triggers, returns to previous page |
| 13 | Gallery nav to Live View | Navigate to `/gallery`, click title or **← Live View** | Returns to main page at `/` |
| 14 | Prev/Next on image view | On image view page, click **< Prev** or **Next >** | Previous/next detection image loads |
| 15 | Arrow keys on image view | On image view page, press **←** or **→** | Previous/next detection image loads |
| 16 | Position indicator | On image view page | Shows "Image N of M" in nav bar |
| 17 | Lightbox Prev/Next | Open lightbox, click **◀** or **▶** buttons | Adjacent image shown |
| 18 | Lightbox arrow keys | Open lightbox, press **←** or **→** | Adjacent image shown |
| 19 | Gallery responsive grid | Open `/gallery` and inspect | Cards use `auto-fill` with `minmax(220px, 1fr)` — at least 220px wide, responsive to screen width |
| 20 | Thumbnails render correctly | Load Live View and Gallery pages | All thumbnails show JPEG content (not broken-image icons); inspect `<img>` src points to `/thumb/{name}` |

---

## 5. Data Drive Docs Subcommand

Verify that setup documentation is available on the exFAT partition:

```bash
# On the Pi (data drive must be mounted):
./setup-data-drive.sh docs
# Expected output:
#   Copied PLAN.md → /mnt/wildlife-data/PLAN.md
#   Copied TEST.md → /mnt/wildlife-data/TEST.md
#   Documentation copied to data drive.

# After ejecting SD and inserting in Windows:
#   Open WILDLIFE_DATA:\ drive
#   Both PLAN.md and TEST.md are visible
#   Open with Notepad to read plain-text markdown
```

---

## 6. Test Environment Setup

### Prerequisites for static + unit tests
- Bash 4.0+
- Git
- Any Linux, macOS, or WSL environment

### Prerequisites for integration tests
- Raspberry Pi 4 (2GB+ RAM)
- Raspberry Pi OS Bookworm 64-bit Lite
- Pi Camera Module v2 connected and enabled
- SD card (32GB+ recommended)
- Network connectivity (Wi-Fi or Ethernet)
- SSH access to the Pi

### VM option for integration tests
```bash
# Use QEMU with Pi 4 emulation (limited — no GPU, slow):
sudo apt install qemu-system-aarch64
# See https://github.com/rmarquis/pistorm for Pi 4 QEMU images
```

## 7. Known Pitfalls

### 7.1 Python `%` format strings in embedded templates

INDEX_HTML and GALLERY_HTML use Python `%`-style dictionary formatting (`%(name)s`). Any literal `%` inside the template (e.g. CSS `top:50%`, `transform:translateY(-50%)`, JavaScript `% n` modulo) will be interpreted as a format specifier and cause **503 "not enough arguments for format string"**.

**Fix:** Use `%%` for literal percent signs: `top:50%%`, `translateY(-50%%)`.
**Check:** Run `bash tests/pi_deployment/run-pi-tests.sh --unit` to verify.

### 7.2 Thumbnails not rendering (broken image icons)

Gallery grid thumbnails must point to an endpoint that returns **raw JPEG bytes**, not an HTML page. Using `src="/image/{name}"` fails because `/image/` returns a full HTML document.

**Fix:** The `_detection_cards()` method should use `src="/thumb/{name}"`. The `/thumb/{name}` endpoint (`send_thumbnail()`) returns raw JPEG bytes with `Content-Type: image/jpeg` and no `Content-Disposition` header.
**Lightbox JS:** The selector `.card img[src^="/thumb/"]` must match the thumbnail src prefix.

### 7.3 Gallery page has no grid (cards stack vertically)

The gallery page (`/gallery`) may show cards in a single column instead of a 10-column raster. The `_detection_cards()` method returns `<div class="detection-grid">`, but GALLERY_HTML only defined CSS for `.gallery`, not `.detection-grid`.

**Fix:** Add `.detection-grid { display: grid; grid-template-columns: repeat(10, 1fr); gap: 10px; }` to GALLERY_HTML's `<style>` block, matching the rule in INDEX_HTML.
**Check:** Load `/gallery` and verify cards render in rows of 10, or run the integration test.

### 7.4 Thumbnails cropped to a strip (object-fit)

`.card img` uses `object-fit: cover` in both templates, which scales the image to fill the box and clips the overflow — the user sees only a horizontal band of the picture.

**Fix:** Change to `object-fit: contain` — the full image is visible within the box dimensions with letterbox bars on the sides or top/bottom.
**Check:** Load the web page and verify that each thumbnail shows the complete picture without cropping.
