#!/usr/bin/env bash
# ==============================================================================
# Ultralytics YOLO — Windows-Compatible Data Drive Setup
# Raspberry Pi 4 + Camera v2 — exFAT partition for cross-OS access
# ==============================================================================
# Usage:
#   ./setup-data-drive.sh              Show status / interactive
#   ./setup-data-drive.sh sd           Set up SD card exFAT data partition
#   ./setup-data-drive.sh status       Show data drive state
#   ./setup-data-drive.sh sync         Flush buffers, unmount for Windows
#   ./setup-data-drive.sh remove       Tear down data drive
# ==============================================================================
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
PI_USER="${USER:-pi}"
HOME_DIR="/home/${PI_USER}"
DATA_MOUNT="/mnt/wildlife-data"
SENTINEL_FILE=".wildlife_data_sentinel"
TARGET_SIZE_GB=6
LABEL="WILDLIFE_DATA"

# Paths for team integration
TEAM1_RESULTS="${HOME_DIR}/ultralytics/data"
TEAM2_RESULTS="${HOME_DIR}/ultralytics-local/results"
TEAM1_RESULTS_DRIVE="${DATA_MOUNT}/team1"
TEAM2_RESULTS_DRIVE="${DATA_MOUNT}/team2"

# Boot partition
BOOT_MOUNT="/boot/firmware"
[ ! -d "$BOOT_MOUNT" ] && BOOT_MOUNT="/boot"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}$(date '+%Y-%m-%d %H:%M:%S') [${SCRIPT_NAME}] [INFO]${NC}  $1"; }
warn()  { echo -e "${YELLOW}$(date '+%Y-%m-%d %H:%M:%S') [${SCRIPT_NAME}] [WARN]${NC}  $1"; }
error() { echo -e "${RED}$(date '+%Y-%m-%d %H:%M:%S') [${SCRIPT_NAME}] [ERROR]${NC} $1" >&2; }
header(){ echo -e "\n${BOLD}── $1 ──${NC}\n"; }

SCRIPT_NAME="setup-data-drive"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/$(date +%Y%m%d_%H%M%S)_${SCRIPT_NAME}.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

# ── Detect the root and boot partition devices ─────────────────────────────────
detect_devices() {
    ROOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null | grep -oP '/dev/mmcblk[0-9]+p[0-9]+' || echo "")
    if [ -z "$ROOT_DEV" ]; then
        ROOT_DEV=$(blkid -L root 2>/dev/null || blkid | grep ' ext4 ' | head -1 | cut -d: -f1 || true)
    fi
    if [ -z "$ROOT_DEV" ]; then
        # Fallback: find ext4 partition that isn't boot
        for dev in /dev/mmcblk0p*; do
            fstype=$(blkid -s TYPE -o value "$dev" 2>/dev/null || true)
            label=$(blkid -s LABEL -o value "$dev" 2>/dev/null || true)
            if [ "$fstype" = "ext4" ] && [ "$label" != "boot" ]; then
                ROOT_DEV=$dev
                break
            fi
        done
    fi

    SD_DEV="${ROOT_DEV%p[0-9]*}"
    SD_DEV="${SD_DEV%[0-9]}"
    BOOT_DEV="/dev/mmcblk0p1"
    DATA_DEV="/dev/mmcblk0p3"

    # Find boot partition
    for dev in /dev/mmcblk0p*; do
        fstype=$(blkid -s TYPE -o value "$dev" 2>/dev/null || true)
        if [ "$fstype" = "vfat" ]; then
            BOOT_DEV=$dev
            break
        fi
    done
}

# ── Check if data drive exists and mount it ────────────────────────────────────
data_drive_status() {
    detect_devices
    echo ""
    echo "═══════════════════════ Data Drive Status ═══════════════════════"
    echo ""

    # Check if data partition exists
    if [ -b "$DATA_DEV" ]; then
        local fstype label
        fstype=$(blkid -s TYPE -o value "$DATA_DEV" 2>/dev/null || echo "unknown")
        label=$(blkid -s LABEL -o value "$DATA_DEV" 2>/dev/null || echo "")
        echo "  Partition: $DATA_DEV (${fstype}, LABEL=${label:-none})"
    else
        echo "  Partition: $DATA_DEV — does not exist"
    fi

    # Check if mounted
    if mountpoint -q "$DATA_MOUNT" 2>/dev/null; then
        echo "  Mounted at: $DATA_MOUNT ✓"
        local free total used
        free=$(df -h "$DATA_MOUNT" | awk 'NR==2 {print $4}')
        total=$(df -h "$DATA_MOUNT" | awk 'NR==2 {print $2}')
        used=$(df -h "$DATA_MOUNT" | awk 'NR==2 {print $3}')
        echo "  Size: ${total}  |  Used: ${used}  |  Free: ${free}"
    else
        echo "  Mounted at: $DATA_MOUNT ✗ (not mounted)"
    fi

    # Check sentinel file
    local sentinel_path=""
    if mountpoint -q "$DATA_MOUNT" 2>/dev/null; then
        sentinel_path="${DATA_MOUNT}/${SENTINEL_FILE}"
    elif [ -b "$DATA_DEV" ]; then
        # Try mounting temporarily
        local tmp_mount=$(mktemp -d)
        if mount -t exfat "$DATA_DEV" "$tmp_mount" 2>/dev/null; then
            [ -f "${tmp_mount}/${SENTINEL_FILE}" ] && sentinel_path="${tmp_mount}/${SENTINEL_FILE}"
            umount "$tmp_mount"
        fi
        rmdir "$tmp_mount" 2>/dev/null || true
    fi

    if [ -n "$sentinel_path" ]; then
        echo "  Sentinel: present ✓ (drive was set up by this script)"
    else
        echo "  Sentinel: not found"
    fi

    # Count detections
    local n_frames=0
    local tmp_mount=""
    if mountpoint -q "$DATA_MOUNT" 2>/dev/null; then
        n_frames=$(find "$DATA_MOUNT" -name "detect_*.jpg" 2>/dev/null | wc -l)
    elif [ -b "$DATA_DEV" ]; then
        tmp_mount=$(mktemp -d)
        if mount -t exfat "$DATA_DEV" "$tmp_mount" 2>/dev/null; then
            n_frames=$(find "$tmp_mount" -name "detect_*.jpg" 2>/dev/null | wc -l)
            umount "$tmp_mount"
        fi
        rmdir "$tmp_mount" 2>/dev/null || true
    fi

    if [ "$n_frames" -gt 0 ]; then
        echo "  Detection images: ${n_frames}"
    fi

    # Check symlinks
    echo ""
    echo "  ── Symlinks ──"
    if [ -L "$TEAM1_RESULTS" ]; then
        local target1
        target1=$(readlink -f "$TEAM1_RESULTS" 2>/dev/null || echo "broken")
        echo "  Team1: $TEAM1_RESULTS → ${target1}"
    else
        echo "  Team1: ${TEAM1_RESULTS} (no symlink — using local storage)"
    fi

    if [ -L "$TEAM2_RESULTS" ]; then
        local target2
        target2=$(readlink -f "$TEAM2_RESULTS" 2>/dev/null || echo "broken")
        echo "  Team2: $TEAM2_RESULTS → ${target2}"
    else
        echo "  Team2: ${TEAM2_RESULTS} (no symlink — using local storage)"
    fi

    echo ""
    echo "════════════════════════════════════════════════════════════════"
}

# ── Build initramfs for boot-time resize ───────────────────────────────────────
build_initramfs() {
    header "Building Initramfs for Partition Resize"

    local tmpdir
    tmpdir=$(mktemp -d)

    # Create initramfs directory structure
    mkdir -p "${tmpdir}/bin" "${tmpdir}/sbin" "${tmpdir}/usr/sbin" \
             "${tmpdir}/usr/bin" "${tmpdir}/lib/aarch64-linux-gnu" \
             "${tmpdir}/dev" "${tmpdir}/proc" "${tmpdir}/sys" \
             "${tmpdir}/mnt" "${tmpdir}/etc"

    # Copy busybox (provides sh, mount, umount, sleep, echo, cat, ls, cp,
    # mv, rm, mkdir, sync, reboot, dmesg, grep, cut, etc.)
    if [ -f /bin/busybox ]; then
        cp -a /bin/busybox "${tmpdir}/bin/"
    elif [ -f /usr/bin/busybox ]; then
        cp -a /usr/bin/busybox "${tmpdir}/bin/"
    fi

    # Create busybox applet symlinks
    for applet in sh mount umount sleep echo cat ls cp mv rm mkdir rmdir \
                  chmod chown df sync reboot dmesg grep cut tr awk sed \
                  basename dirname readlink find wc head tail xargs \
                  pidof kill killall printf which; do
        ln -sf /bin/busybox "${tmpdir}/bin/${applet}" 2>/dev/null || true
    done
    for applet in pivot_root switch_root; do
        ln -sf /bin/busybox "${tmpdir}/sbin/${applet}" 2>/dev/null || true
    done

    # Copy essential tools and their libraries
    local tools=(
        /sbin/e2fsck /sbin/resize2fs /sbin/dumpe2fs /sbin/tune2fs
        /sbin/fdisk /sbin/blkid /sbin/parted /sbin/partprobe
        /usr/sbin/mkfs.exfat /usr/sbin/fsck.exfat
        /sbin/ldconfig /sbin/badblocks
    )

    for tool in "${tools[@]}"; do
        if [ -f "$tool" ]; then
            local dest="${tmpdir}${tool}"
            mkdir -p "$(dirname "$dest")"
            cp -a "$tool" "$dest"
        fi
    done

    # Copy dynamic linker
    cp -a /lib/ld-linux-aarch64.so* "${tmpdir}/lib/" 2>/dev/null || true

    # Copy libraries using ldd
    local all_tools=""
    for tool in "${tools[@]}"; do
        [ -f "$tool" ] && all_tools="$all_tools $tool"
    done

    # Get all library dependencies
    local libs
    libs=$(ldd $all_tools 2>/dev/null | grep -oP '/\S+\.so[^ ]*' | sort -u || true)

    for lib in $libs; do
        local dest="${tmpdir}${lib}"
        mkdir -p "$(dirname "$dest")"
        cp -a "$lib" "$dest" 2>/dev/null || true
    done

    # Also copy /etc/ld.so.cache if it exists
    [ -f /etc/ld.so.cache ] && cp -a /etc/ld.so.cache "${tmpdir}/etc/"

    # Run ldconfig in the chroot
    chroot "${tmpdir}" /sbin/ldconfig 2>/dev/null || true

    # ── Create the /init script for the initramfs ──
    cat > "${tmpdir}/init" << 'INITEOF'
#!/bin/sh
# ============================================================================
# Initramfs /init script — Resize root partition and create exFAT data partition
# Runs once during boot, then hands off to the real init via switch_root
# ============================================================================

# Mount essential filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# Boot partition will be mounted shortly
mkdir -p /boot /newroot

# Log everything
exec > /dev/kmsg 2>&1
echo "[wildlife-resize] Starting initramfs resize script"

# Find and mount the boot partition
BOOT_DEV=""
for dev in /dev/mmcblk0p*; do
    fstype=$(/sbin/blkid -s TYPE -o value "$dev" 2>/dev/null || echo "")
    if [ "$fstype" = "vfat" ]; then
        BOOT_DEV=$dev
        break
    fi
done

if [ -z "$BOOT_DEV" ]; then
    echo "[wildlife-resize] ERROR: Cannot find boot partition"
    echo "[wildlife-resize] Rebooting without changes..."
    sync; reboot -f
    sleep 30
fi

mount -t vfat "$BOOT_DEV" /boot
echo "[wildlife-resize] Boot partition mounted: $BOOT_DEV"

# Restore original cmdline.txt (remove temporary root= change)
if [ -f /boot/wildlife-cmdline.txt.bak ]; then
    cp /boot/wildlife-cmdline.txt.bak /boot/cmdline.txt
    echo "[wildlife-resize] Restored original cmdline.txt"
fi

# Remove initramfs from config.txt
if [ -f /boot/config.txt ]; then
    sed -i '/^initramfs /d' /boot/config.txt
    echo "[wildlife-resize] Removed initramfs from config.txt"
elif [ -f /boot/firmware/config.txt ]; then
    sed -i '/^initramfs /d' /boot/firmware/config.txt
    echo "[wildlife-resize] Removed initramfs from config.txt"
fi

# Identify the root device
ROOT_DEV=""
for dev in /dev/mmcblk0p*; do
    fstype=$(/sbin/blkid -s TYPE -o value "$dev" 2>/dev/null || echo "")
    label=$(/sbin/blkid -s LABEL -o value "$dev" 2>/dev/null || echo "")
    if [ "$fstype" = "ext4" ] && [ "$label" != "boot" ]; then
        ROOT_DEV=$dev
        break
    fi
done

# Try reading from backup file
if [ -z "$ROOT_DEV" ] && [ -f /boot/wildlife-root-dev.txt ]; then
    ROOT_DEV=$(cat /boot/wildlife-root-dev.txt)
fi

if [ -z "$ROOT_DEV" ]; then
    echo "[wildlife-resize] ERROR: Cannot find root partition"
    echo "[wildlife-resize] Rebooting without changes..."
    sync; reboot -f
    sleep 30
fi

echo "[wildlife-resize] Root device: $ROOT_DEV"
echo "[wildlife-resize] SD card device: ${ROOT_DEV%p[0-9]*}"

SD_DEV="${ROOT_DEV%p[0-9]*}"
DATA_DEV="${SD_DEV}p3"

# Check if p3 already exists
if [ -b "$DATA_DEV" ]; then
    echo "[wildlife-resize] Data partition $DATA_DEV already exists"
    echo "[wildlife-resize] Checking if formatted as exFAT..."

    fstype=$(/sbin/blkid -s TYPE -o value "$DATA_DEV" 2>/dev/null || echo "")
    if [ "$fstype" = "exfat" ]; then
        echo "[wildlife-resize] Already exFAT — nothing to do"
        # Clean up and boot normally
        umount /boot
        mount "$ROOT_DEV" /newroot
        exec switch_root /newroot /sbin/init 2>/dev/null || exec switch_root /newroot /lib/systemd/systemd
    else
        echo "[wildlife-resize] p3 exists but is $fstype — formatting as exFAT"
        /usr/sbin/mkfs.exfat -L WILDLIFE_DATA "$DATA_DEV"
    fi

    # Mount data partition and write sentinel
    mount -t exfat "$DATA_DEV" /mnt 2>/dev/null || {
        /usr/sbin/mkfs.exfat -L WILDLIFE_DATA "$DATA_DEV"
        mount -t exfat "$DATA_DEV" /mnt
    }
    echo "1" > /mnt/.wildlife_data_sentinel
    umount /mnt
    echo "[wildlife-resize] Sentinel written to $DATA_DEV"

    umount /boot
    mount "$ROOT_DEV" /newroot
    exec switch_root /newroot /sbin/init 2>/dev/null || exec switch_root /newroot /lib/systemd/systemd
fi

# ── Phase 2: Resize root and create p3 ──

echo "[wildlife-resize] Checking filesystem..."
/sbin/e2fsck -f -p "$ROOT_DEV" || true

echo "[wildlife-resize] Shrinking filesystem to minimum..."
/sbin/resize2fs -M "$ROOT_DEV" 2>&1

# Get new block count
BLOCK_SIZE=$(/sbin/dumpe2fs -h "$ROOT_DEV" 2>/dev/null | grep "^Block size:" | awk '{print $NF}')
NEW_BLOCKS=$(/sbin/dumpe2fs -h "$ROOT_DEV" 2>/dev/null | grep "^Block count:" | awk '{print $NF}')

echo "[wildlife-resize] Filesystem shrunk to $NEW_BLOCKS blocks (${BLOCK_SIZE}B blocks)"

# Target: minimum + 2GB margin
MARGIN_BLOCKS=$((2 * 1024 * 1024 * 1024 / BLOCK_SIZE))
TARGET_BLOCKS=$((NEW_BLOCKS + MARGIN_BLOCKS))
echo "[wildlife-resize] Expanding to $TARGET_BLOCKS blocks (2GB margin)"

/sbin/resize2fs "$ROOT_DEV" $TARGET_BLOCKS

# Resize partition 2
echo "[wildlife-resize] Resizing partition 2..."

SECTOR_SIZE=$(/sbin/fdisk -l "$SD_DEV" 2>/dev/null | grep "^Sector size" | awk '{print $NF}')
P2_START=$(/sbin/fdisk -l "$SD_DEV" 2>/dev/null | grep "^${ROOT_DEV}" | awk '{print $2}')

if [ -z "$P2_START" ] || [ "$P2_START" = "*" ]; then
    # Handle case where mmcblk0p2 has boot flag
    P2_START=$(/sbin/fdisk -l "$SD_DEV" 2>/dev/null | grep "^${ROOT_DEV}" | awk '{print $3}')
fi

echo "[wildlife-resize] p2 start: $P2_START  sector size: $SECTOR_SIZE"

NEW_SECTORS=$((TARGET_BLOCKS * BLOCK_SIZE / SECTOR_SIZE))
P2_END=$((P2_START + NEW_SECTORS - 1))

echo "[wildlife-resize] p2 new end: $P2_END  (${TARGET_BLOCKS} blocks)"

# Detect if we should use parted or fdisk for the resize
if command -v /sbin/parted &>/dev/null; then
    echo "[wildlife-resize] Using parted to resize partition 2"
    /sbin/parted -s "$SD_DEV" unit s resizepart 2 ${P2_END} || {
        echo "[wildlife-resize] parted resizepart failed, trying sfdisk..."
        # Fallback to sfdisk
        /sbin/sfdisk -d "$SD_DEV" > /tmp/part-table.txt
        # Modify partition 2 size
        awk -v end="$P2_END" '/^\/dev\/mmcblk0p2/ {sub(/size=[^,]+/, "size=" end - '"$P2_START"' + 1)} 1' /tmp/part-table.txt > /tmp/part-table-new.txt
        /sbin/sfdisk "$SD_DEV" < /tmp/part-table-new.txt
    }

    # Create partition 3 in the freed space
    P3_START=$((P2_END + 1))
    echo "[wildlife-resize] Creating partition 3 at sector $P3_START"
    /sbin/parted -s "$SD_DEV" unit s mkpart primary ${P3_START} 100%
else
    # Use fdisk (non-interactive)
    echo "[wildlife-resize] Using fdisk to resize partition 2"
    {
        echo "d"     # Delete partition
        echo "2"     # Partition 2
        echo "n"     # New partition
        echo "p"     # Primary
        echo "2"     # Partition number 2
        echo "${P2_START}"
        echo "${P2_END}"
        echo "n"     # New partition 3
        echo "p"     # Primary
        echo "3"     # Partition 3
        echo ""
        echo ""      # Default start (next free)
        echo "w"     # Write
    } | /sbin/fdisk "$SD_DEV"
fi

# Wait for partition table to update
/sbin/partprobe "$SD_DEV" 2>/dev/null || true
sleep 3

# Verify data partition exists
if [ ! -b "$DATA_DEV" ]; then
    echo "[wildlife-resize] ERROR: $DATA_DEV not found after partition creation"
    echo "[wildlife-resize] Rebooting with original partition table..."
    sync; reboot -f
    sleep 30
fi

# Format as exFAT
echo "[wildlife-resize] Formatting $DATA_DEV as exFAT..."
/usr/sbin/mkfs.exfat -L WILDLIFE_DATA "$DATA_DEV" 2>&1

# Write sentinel file
mount -t exfat "$DATA_DEV" /mnt
echo "1" > /mnt/.wildlife_data_sentinel
umount /mnt

echo "[wildlife-resize] Sentinel written"

# Clean up and boot normally
umount /boot
echo "[wildlife-resize] Resize complete! Booting normally..."
mount "$ROOT_DEV" /newroot
exec switch_root /newroot /sbin/init 2>/dev/null || exec switch_root /newroot /lib/systemd/systemd
INITEOF

    chmod +x "${tmpdir}/init"
    chmod +x "${tmpdir}/bin/busybox" 2>/dev/null || true

    # Create the initramfs (gzipped cpio archive)
    local initramfs_path="${BOOT_MOUNT}/wildlife-initrd.img"
    (
        cd "$tmpdir"
        find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip > "$initramfs_path"
    )

    local size
    size=$(du -h "$initramfs_path" | cut -f1)
    info "Initramfs created: ${initramfs_path} (${size})"

    # Clean up
    rm -rf "$tmpdir"
}

# ── Prepare for boot-time resize ───────────────────────────────────────────────
cmd_sd_prepare() {
    detect_devices

    # Check if data partition already exists
    if [ -b "$DATA_DEV" ]; then
        info "Data partition $DATA_DEV already exists"
        # Check if it has data or sentinel
        local tmp_mount
        tmp_mount=$(mktemp -d)
        local has_data=0
        if mount -t exfat "$DATA_DEV" "$tmp_mount" 2>/dev/null; then
            if [ -f "${tmp_mount}/${SENTINEL_FILE}" ] || \
               ls "${tmp_mount}/detect_"*.jpg 2>/dev/null | head -1 | grep -q .; then
                has_data=1
            fi
            umount "$tmp_mount"
        fi
        rmdir "$tmp_mount" 2>/dev/null || true

        if [ "$has_data" = "1" ]; then
            info "Data drive already set up with pictures — nothing to resize"
            cmd_sd_mount
            return 0
        else
            info "Data partition exists but is empty — formatting and mounting"
            mkfs.exfat -L "$LABEL" "$DATA_DEV"
            cmd_sd_mount
            return 0
        fi
    fi

    # Show current partition layout and planned changes
    header "Current SD Card Layout"
    fdisk -l "$SD_DEV" 2>/dev/null | head -20 || true
    echo ""

    # Check free space
    local free_bytes
    free_bytes=$(df -B1 / | awk 'NR==2 {print $4}')
    local free_gb=$((free_bytes / 1024 / 1024 / 1024))
    local needed_gb=$((TARGET_SIZE_GB + 2))  # 6GB for data + 2GB margin

    if [ "$free_gb" -lt "$needed_gb" ]; then
        error "Not enough free space: ${free_gb}GB free, need ${needed_gb}GB minimum"
        error "Free up space or use a larger SD card"
        exit 1
    fi

    info "Free space on root: ${free_gb}GB — sufficient for ${TARGET_SIZE_GB}GB data partition"

    echo ""
    echo "${BOLD}WARNING: This will resize the root partition and reboot the Pi!${NC}"
    echo ""
    echo "  Changes planned:"
    echo "    1. Shrink root filesystem (${free_gb}GB free → 2GB margin)"
    echo "    2. Shrink partition 2"
    echo "    3. Create new partition 3 (~${TARGET_SIZE_GB}GB)"
    echo "    4. Format partition 3 as exFAT (label: ${LABEL})"
    echo "    5. Reboot automatically"
    echo ""
    echo "${YELLOW}  IMPORTANT: Backup your data first!${NC}"
    echo "${YELLOW}  Power loss during resize can corrupt the SD card!${NC}"
    echo ""

    read -r -p "Continue? [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) ;;
        *) echo "Cancelled."; exit 0 ;;
    esac

    # Backup cmdline.txt
    info "Backing up boot configuration..."
    if [ -f "${BOOT_MOUNT}/cmdline.txt" ]; then
        cp "${BOOT_MOUNT}/cmdline.txt" "${BOOT_MOUNT}/wildlife-cmdline.txt.bak"
        info "Backed up cmdline.txt → wildlife-cmdline.txt.bak"
    fi

    # Store root device info
    echo "$ROOT_DEV" > "${BOOT_MOUNT}/wildlife-root-dev.txt"
    info "Stored root device info"

    # Create a minimal config.txt with initramfs added
    local config_path=""
    if [ -f "${BOOT_MOUNT}/config.txt" ]; then
        config_path="${BOOT_MOUNT}/config.txt"
    fi

    if [ -n "$config_path" ]; then
        # Add initramfs line if not present
        if ! grep -q "^initramfs " "$config_path"; then
            echo "initramfs wildlife-initrd.img" >> "$config_path"
            info "Added initramfs to config.txt"
        fi
    fi

    # Build the initramfs
    build_initramfs

    # Replace root= in cmdline.txt with temporary value to prevent kernel
    # from mounting the root early (initramfs will handle it)
    local cmdline
    cmdline=$(cat "${BOOT_MOUNT}/cmdline.txt")
    # Keep the root= as-is — the initramfs will ignore it until switch_root
    # Actually, with initramfs, the kernel doesn't mount root — it runs /init
    # from the initramfs. So root= can stay as is.

    info "Initramfs resize prepared!"
    echo ""
    echo "${BOLD}Ready to reboot for partition resize.${NC}"
    echo ""
    echo "  After reboot, the Pi will:"
    echo "    1. Boot into the resize initramfs"
    echo "    2. Shrink the root partition"
    echo "    3. Create a 6GB exFAT data partition"
    echo "    4. Reboot into the normal OS"
    echo "    5. Run: ./setup-data-drive.sh sd  (to mount and set up symlinks)"
    echo ""
    read -r -p "Reboot now? [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY])
            info "Rebooting..."
            sync
            sudo reboot
            ;;
        *)
            info "Reboot cancelled. When ready, run: sudo reboot"
            ;;
    esac
}

# ── Mount data drive and set up symlinks (run after reboot) ────────────────────
cmd_sd_mount() {
    detect_devices

    if [ ! -b "$DATA_DEV" ]; then
        error "Data partition $DATA_DEV not found"
        error "Run './setup-data-drive.sh sd' to set it up"
        exit 1
    fi

    # Check if already mounted correctly
    if mountpoint -q "$DATA_MOUNT" 2>/dev/null; then
        local mounted_dev
        mounted_dev=$(findmnt -n -o SOURCE "$DATA_MOUNT")
        if [ "$mounted_dev" = "$DATA_DEV" ]; then
            info "Data drive already mounted at ${DATA_MOUNT}"
        else
            warn "Something else mounted at ${DATA_MOUNT} (${mounted_dev})"
        fi
    else
        # Mount the data partition
        info "Mounting ${DATA_DEV} at ${DATA_MOUNT}..."
        sudo mkdir -p "$DATA_MOUNT"
        if mount -t exfat "$DATA_DEV" "$DATA_MOUNT" 2>/dev/null; then
            info "Mounted successfully"
        else
            # Try to format if not exFAT
            warn "Mount failed — formatting ${DATA_DEV} as exFAT..."
            sudo mkfs.exfat -L "$LABEL" "$DATA_DEV"
            sudo mount -t exfat "$DATA_DEV" "$DATA_MOUNT"
            info "Formatted and mounted"
        fi
    fi

    # Write sentinel (if not present)
    if [ ! -f "${DATA_MOUNT}/${SENTINEL_FILE}" ]; then
        echo "1" | sudo tee "${DATA_MOUNT}/${SENTINEL_FILE}" > /dev/null
        info "Wrote sentinel file"
    fi

    # Create team subdirectories
    sudo mkdir -p "${DATA_MOUNT}/team1" "${DATA_MOUNT}/team2"
    # Fix permissions so the pi user can write
    sudo chown -R "${PI_USER}:${PI_USER}" "${DATA_MOUNT}" 2>/dev/null || true

    info "Created data directories:"
    info "  team1 → ${DATA_MOUNT}/team1"
    info "  team2 → ${DATA_MOUNT}/team2"

    # Add to fstab for auto-mount on future boots
    local fstab_entry="${DATA_DEV}  ${DATA_MOUNT}  exfat  defaults,uid=$(id -u "${PI_USER}"),gid=$(id -g "${PI_USER}"),umask=007,noexec,nodev,nosuid  0  0"
    if ! grep -q "${DATA_MOUNT}" /etc/fstab 2>/dev/null; then
        echo "$fstab_entry" | sudo tee -a /etc/fstab > /dev/null
        info "Added fstab entry for auto-mount on boot"
    else
        info "fstab entry already exists"
    fi

    # ── Set up symlinks ──
    # Team 1
    if [ -d "$TEAM1_RESULTS" ] && [ ! -L "$TEAM1_RESULTS" ]; then
        # Migrate existing data
        if ls "${TEAM1_RESULTS}/detect_"*.jpg 2>/dev/null | head -1 | grep -q .; then
            info "Migrating existing Team 1 data..."
            cp -a "${TEAM1_RESULTS}/detect_"*.jpg "${DATA_MOUNT}/team1/" 2>/dev/null || true
            [ -f "${TEAM1_RESULTS}/detections.jsonl" ] && \
                cp -a "${TEAM1_RESULTS}/detections.jsonl" "${DATA_MOUNT}/team1/" 2>/dev/null || true
            [ -f "${TEAM1_RESULTS}/latest.jpg" ] && \
                cp -a "${TEAM1_RESULTS}/latest.jpg" "${DATA_MOUNT}/team1/" 2>/dev/null || true
        fi
        # Backup original directory, then symlink
        local backup="${TEAM1_RESULTS}.local"
        sudo mv "$TEAM1_RESULTS" "$backup"
        sudo ln -sf "${DATA_MOUNT}/team1" "$TEAM1_RESULTS"
        sudo chown -h "${PI_USER}:${PI_USER}" "$TEAM1_RESULTS"
        info "Team 1: ${TEAM1_RESULTS} → ${DATA_MOUNT}/team1  (original backed up to ${backup})"
    elif [ -L "$TEAM1_RESULTS" ]; then
        # Update symlink if needed
        local current
        current=$(readlink -f "$TEAM1_RESULTS" 2>/dev/null || echo "")
        if [ "$current" != "${DATA_MOUNT}/team1" ]; then
            sudo ln -sf "${DATA_MOUNT}/team1" "$TEAM1_RESULTS"
            info "Team 1: Updated symlink to ${DATA_MOUNT}/team1"
        else
            info "Team 1: Symlink already correct"
        fi
    else
        # Results dir doesn't exist yet — create symlink
        sudo ln -sf "${DATA_MOUNT}/team1" "$TEAM1_RESULTS"
        sudo chown -h "${PI_USER}:${PI_USER}" "$TEAM1_RESULTS" 2>/dev/null || true
        info "Team 1: Created symlink ${TEAM1_RESULTS} → ${DATA_MOUNT}/team1"
    fi

    # Team 2
    mkdir -p "$(dirname "$TEAM2_RESULTS")"
    if [ -d "$TEAM2_RESULTS" ] && [ ! -L "$TEAM2_RESULTS" ]; then
        # Migrate existing data
        if ls "${TEAM2_RESULTS}/detect_"*.jpg 2>/dev/null | head -1 | grep -q .; then
            info "Migrating existing Team 2 data..."
            cp -a "${TEAM2_RESULTS}/detect_"*.jpg "${DATA_MOUNT}/team2/" 2>/dev/null || true
            [ -f "${TEAM2_RESULTS}/detections.jsonl" ] && \
                cp -a "${TEAM2_RESULTS}/detections.jsonl" "${DATA_MOUNT}/team2/" 2>/dev/null || true
            [ -f "${TEAM2_RESULTS}/latest.jpg" ] && \
                cp -a "${TEAM2_RESULTS}/latest.jpg" "${DATA_MOUNT}/team2/" 2>/dev/null || true
            [ -f "${TEAM2_RESULTS}/config.json" ] && \
                cp -a "${TEAM2_RESULTS}/config.json" "${DATA_MOUNT}/team2/" 2>/dev/null || true
        fi
        local backup="${TEAM2_RESULTS}.local"
        mv "$TEAM2_RESULTS" "$backup"
        ln -sf "${DATA_MOUNT}/team2" "$TEAM2_RESULTS"
        info "Team 2: ${TEAM2_RESULTS} → ${DATA_MOUNT}/team2  (original backed up to ${backup})"
    elif [ -L "$TEAM2_RESULTS" ]; then
        local current
        current=$(readlink -f "$TEAM2_RESULTS" 2>/dev/null || echo "")
        if [ "$current" != "${DATA_MOUNT}/team2" ]; then
            ln -sf "${DATA_MOUNT}/team2" "$TEAM2_RESULTS"
            info "Team 2: Updated symlink to ${DATA_MOUNT}/team2"
        else
            info "Team 2: Symlink already correct"
        fi
    else
        mkdir -p "$(dirname "$TEAM2_RESULTS")"
        ln -sf "${DATA_MOUNT}/team2" "$TEAM2_RESULTS"
        info "Team 2: Created symlink"
    fi

    echo ""
    info "Data drive setup complete!"
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  Data partition: ${DATA_DEV} → ${DATA_MOUNT}"
    echo "  Filesystem:     exFAT (Windows/macOS/Linux compatible)"
    echo "  Label:          ${LABEL}"
    echo ""
    echo "  To access on Windows:"
    echo "    1. Run:  ./setup-data-drive.sh sync"
    echo "    2. Remove the SD card"
    echo "    3. Insert into Windows PC"
    echo "    4. Open '${LABEL}' drive in File Explorer"
    echo "════════════════════════════════════════════════════════════════"

    # Show current data drive status
    data_drive_status
}

# ── Sync and unmount for Windows access ────────────────────────────────────────
cmd_sync() {
    detect_devices
    header "Preparing Data Drive for Windows Access"

    # Flush filesystem buffers
    info "Syncing filesystems..."
    sync

    # Stop both inference services if running
    for svc in ultralytics-docker.service ultralytics-local.service \
               ultralytics-wildlife.service ultralytics-gallery.service; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            info "Stopping $svc..."
            sudo systemctl stop "$svc"
        fi
    done

    # Give time for writes to complete
    sleep 2
    sync

    if mountpoint -q "$DATA_MOUNT" 2>/dev/null; then
        # Check if anything is still using it
        local users
        users=$(fuser -m "$DATA_MOUNT" 2>/dev/null || true)
        if [ -n "$users" ]; then
            warn "Processes still using ${DATA_MOUNT}: ${users}"
        fi
        sudo umount "$DATA_MOUNT" && info "Unmounted ${DATA_MOUNT}" || {
            warn "Unmount failed — forcing..."
            sudo umount -l "$DATA_MOUNT"
            sleep 1
        }
    fi

    # Final sync
    sync

    echo ""
    echo "${GREEN}✓ Safe to remove the SD card or USB drive${NC}"
    echo ""
    echo "  After inserting into Windows:"
    echo "    1. Open File Explorer"
    echo "    2. Find the '${LABEL}' drive"
    echo "    3. Browse to team1/ or team2/ for detection images"
    echo ""
    echo "  To re-mount on the Pi:"
    echo "    sudo mount ${DATA_MOUNT}"
    echo "    (or reboot — fstab will mount it automatically)"
    echo ""

    data_drive_status
}

# ── Tear down data drive ───────────────────────────────────────────────────────
cmd_remove() {
    detect_devices
    header "Removing Data Drive Configuration"

    echo "${BOLD}WARNING: This will:${NC}"
    echo "  • Remove symlinks from Team 1 and Team 2 results directories"
    echo "  • Remove fstab entry for ${DATA_MOUNT}"
    echo "  • Data on ${DATA_DEV} will NOT be deleted"
    echo ""

    read -r -p "Continue? [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) ;;
        *) echo "Cancelled."; exit 0 ;;
    esac

    # Remove symlinks
    if [ -L "$TEAM1_RESULTS" ]; then
        rm -f "$TEAM1_RESULTS"
        # If backup dir exists, restore
        if [ -d "${TEAM1_RESULTS}.local" ]; then
            mv "${TEAM1_RESULTS}.local" "$TEAM1_RESULTS"
            info "Restored Team 1 results from backup"
        fi
        info "Removed Team 1 symlink"
    fi

    if [ -L "$TEAM2_RESULTS" ]; then
        rm -f "$TEAM2_RESULTS"
        if [ -d "${TEAM2_RESULTS}.local" ]; then
            mv "${TEAM2_RESULTS}.local" "$TEAM2_RESULTS"
            info "Restored Team 2 results from backup"
        fi
        info "Removed Team 2 symlink"
    fi

    # Remove fstab entry
    if grep -q "${DATA_MOUNT}" /etc/fstab 2>/dev/null; then
        sudo sed -i "\|${DATA_MOUNT}|d" /etc/fstab
        info "Removed fstab entry"
    fi

    # Unmount
    if mountpoint -q "$DATA_MOUNT" 2>/dev/null; then
        sudo umount "$DATA_MOUNT" && info "Unmounted ${DATA_MOUNT}"
    fi

    # Remove boot-time files
    for f in wildlife-initrd.img wildlife-cmdline.txt.bak wildlife-root-dev.txt; do
        if [ -f "${BOOT_MOUNT}/${f}" ]; then
            sudo rm -f "${BOOT_MOUNT}/${f}"
            info "Removed ${BOOT_MOUNT}/${f}"
        fi
    done

    # Remove initramfs from config.txt
    if [ -f "${BOOT_MOUNT}/config.txt" ]; then
        sudo sed -i '/^initramfs wildlife-initrd.img/d' "${BOOT_MOUNT}/config.txt"
    fi

    info "Data drive configuration removed"
    echo ""
    echo "  Note: The exFAT partition (${DATA_DEV}) still exists."
    echo "  To reclaim space: sudo fdisk ${SD_DEV} and delete partition 3"
    echo "  Then: sudo resize2fs ${ROOT_DEV} (to use the freed space)"
}

# ── Full setup (prepare + mount) — idempotent ─────────────────────────────────
# ── Docs — copy PLAN.md and TEST.md to data drive ────────────────────────────
cmd_docs() {
    detect_devices

    if ! mountpoint -q "$DATA_MOUNT" 2>/dev/null; then
        if [ -b "$DATA_DEV" ]; then
            info "Mounting ${DATA_DEV} to copy docs..."
            sudo mkdir -p "$DATA_MOUNT"
            sudo mount -t exfat "$DATA_DEV" "$DATA_MOUNT" 2>/dev/null || {
                error "Cannot mount ${DATA_DEV} at ${DATA_MOUNT}"
                exit 1
            }
            local mounted=1
        else
            error "Data partition ${DATA_DEV} not found."
            error "Run './setup-data-drive.sh sd' first to create the data partition."
            exit 1
        fi
    else
        local mounted=0
    fi

    local repo_docs_dir="${SCRIPT_DIR}"
    local copied=0

    for doc in PLAN.md TEST.md; do
        local src="${repo_docs_dir}/${doc}"
        if [ -f "$src" ]; then
            cp "$src" "${DATA_MOUNT}/${doc}"
            info "Copied ${doc} → ${DATA_MOUNT}/${doc}"
            copied=$((copied + 1))
        else
            warn "Source file ${src} not found"
        fi
    done

    if [ "$copied" -gt 0 ]; then
        info "Documentation copied to data drive."
        info "On Windows, open WILDLIFE_DATA:\\ drive to read PLAN.md and TEST.md."
    fi

    # Unmount if we mounted temporarily
    if [ "${mounted:-0}" -eq 1 ]; then
        sudo umount "$DATA_MOUNT"
        info "Unmounted ${DATA_MOUNT}"
    fi
}

# ── Full setup (prepare + mount) — idempotent ─────────────────────────────────
cmd_sd() {
    detect_devices

    # Check if p3 already exists and is set up
    if [ -b "$DATA_DEV" ]; then
        local fstype
        fstype=$(blkid -s TYPE -o value "$DATA_DEV" 2>/dev/null || echo "")

        if [ "$fstype" = "exfat" ]; then
            # Mount temporarily to check sentinel/data
            local tmp_mount
            tmp_mount=$(mktemp -d)
            local already_setup=0
            if mount -t exfat "$DATA_DEV" "$tmp_mount" 2>/dev/null; then
                if [ -f "${tmp_mount}/${SENTINEL_FILE}" ] || \
                   ls "${tmp_mount}/detect_"*.jpg 2>/dev/null | head -1 | grep -q .; then
                    already_setup=1
                fi
                umount "$tmp_mount"
            fi
            rmdir "$tmp_mount" 2>/dev/null || true

            if [ "$already_setup" = "1" ]; then
                info "Data drive already set up — ensuring mount and symlinks"
                cmd_sd_mount
                return 0
            fi
        fi

        # p3 exists but not properly set up
        if [ "$fstype" != "exfat" ]; then
            warn "Partition 3 exists but is ${fstype:-unknown} — formatting..."
            sudo mkfs.exfat -L "$LABEL" "$DATA_DEV"
        fi
        cmd_sd_mount
        return 0
    fi

    # No p3 — run the full prepare (build initramfs + reboot)
    cmd_sd_prepare
}

# ── Main ───────────────────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  (none)    Show data drive status"
    echo "  sd        Set up SD card data partition (resize + mount)"
    echo "  status    Show data drive status"
    echo "  sync      Flush buffers and unmount for Windows access"
    echo "  docs      Copy PLAN.md and TEST.md to the data drive"
    echo "  remove    Tear down data drive configuration"
    echo "  --help    Show this help"
    echo ""
    echo "Guides:"
    echo "  First time:   ./setup-data-drive.sh sd"
    echo "  After reboot: ./setup-data-drive.sh sd  (mounts + symlinks)"
    echo "  Before eject: ./setup-data-drive.sh sync"
    echo "  Check state:  ./setup-data-drive.sh status"
    echo "  Copy docs:    ./setup-data-drive.sh docs"
}

case "${1:-status}" in
    sd)
        cmd_sd
        ;;
    status)
        data_drive_status
        ;;
    sync)
        cmd_sync
        ;;
    docs)
        cmd_docs
        ;;
    remove)
        cmd_remove
        ;;
    --help|-h)
        usage
        ;;
    *)
        echo "Unknown command: $1"
        usage
        exit 1
        ;;
esac
