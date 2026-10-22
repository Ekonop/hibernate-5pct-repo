#!/bin/bash
# Universal installer: hibernate at 5% battery
# Supports: Arch/CachyOS (pacman), btrfs (swap file), refind/grub/systemd-boot
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_PART="$(findmnt -no SOURCE /)"
ROOT_UUID="$(findmnt -no UUID /)"
ROOT_FSTYPE="$(findmnt -no FSTYPE /)"

echo "=== Detected: root=$ROOT_PART uuid=$ROOT_UUID fstype=$ROOT_FSTYPE ==="

# --- Swap size ---
RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
SWAP_SIZE_GB=$(( (RAM_KB / 1024 / 1024) + 2 ))
echo "RAM: $((RAM_KB/1024)) MB -> swap file: ${SWAP_SIZE_GB} GB"

# --- Create swap subvolume (btrfs) or directory ---
SWAP_MOUNT="/swap"
SWAP_FILE="$SWAP_MOUNT/swapfile"

if [ "$ROOT_FSTYPE" = "btrfs" ]; then
    echo "=== Creating btrfs subvolume @swap ==="
    mkdir -p /mnt/btrfs-top
    mount -o subvolid=5 "$ROOT_PART" /mnt/btrfs-top 2>/dev/null || true
    if [ ! -d /mnt/btrfs-top/@swap ]; then
        btrfs subvolume create /mnt/btrfs-top/@swap
    fi
    umount /mnt/btrfs-top 2>/dev/null || true
    mkdir -p "$SWAP_MOUNT"
    if ! mountpoint -q "$SWAP_MOUNT"; then
        mount -o subvol=@swap "$ROOT_PART" "$SWAP_MOUNT"
    fi
    grep -q "subvol=@swap" /etc/fstab || \
        echo "UUID=$ROOT_UUID $SWAP_MOUNT btrfs subvol=@swap,defaults,noatime 0 0" >> /etc/fstab
else
    echo "=== Non-btrfs root: using /swap directory ==="
    mkdir -p "$SWAP_MOUNT"
fi

# --- Create swap file ---
if [ ! -f "$SWAP_FILE" ]; then
    echo "=== Creating ${SWAP_SIZE_GB}GB swap file ==="
    if [ "$ROOT_FSTYPE" = "btrfs" ]; then
        truncate -s 0 "$SWAP_FILE"
        chattr +C "$SWAP_FILE"
        btrfs property set "$SWAP_FILE" compression none 2>/dev/null || true
    fi
    dd if=/dev/zero of="$SWAP_FILE" bs=1M count=$((SWAP_SIZE_GB*1024)) status=progress
    chmod 600 "$SWAP_FILE"
    mkswap "$SWAP_FILE"
fi

swapon "$SWAP_FILE" 2>/dev/null || true
swapon -p 200 "$SWAP_FILE" 2>/dev/null || true
grep -q "$SWAP_FILE" /etc/fstab || \
    echo "$SWAP_FILE none swap pri=200 0 0" >> /etc/fstab

# --- Resume offset ---
if [ "$ROOT_FSTYPE" = "btrfs" ]; then
    RESUME_OFFSET=$(btrfs inspect-internal map-swapfile -r "$SWAP_FILE")
else
    # ext4/xfs: use filefrag
    RESUME_OFFSET=$(filefrag -v "$SWAP_FILE" | awk 'NR==4{print $4}' | tr -d '.')
fi
echo "Resume offset: $RESUME_OFFSET"

# --- Update bootloader ---
# refind
if [ -f /boot/refind_linux.conf ]; then
    echo "=== Updating refind_linux.conf ==="
    cat > /boot/refind_linux.conf <<EOF
"Boot with minimal options"   "ro root=$ROOT_PART resume=UUID=$ROOT_UUID resume_offset=$RESUME_OFFSET"
EOF
fi
# grub
if [ -f /etc/default/grub ]; then
    echo "=== Updating grub ==="
    if ! grep -q "resume=UUID=$ROOT_UUID" /etc/default/grub; then
        sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=\"|GRUB_CMDLINE_LINUX_DEFAULT=\"resume=UUID=$ROOT_UUID resume_offset=$RESUME_OFFSET |" /etc/default/grub
        grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
    fi
fi
# systemd-boot
if [ -d /boot/loader/entries ]; then
    echo "=== Updating systemd-boot entries ==="
    for f in /boot/loader/entries/*.conf; do
        [ -f "$f" ] || continue
        if ! grep -q "resume=UUID=$ROOT_UUID" "$f"; then
            sed -i "s|options |options resume=UUID=$ROOT_UUID resume_offset=$RESUME_OFFSET |" "$f"
        fi
    done
fi

# --- Initramfs ---
if command -v mkinitcpio &>/dev/null; then
    echo "=== Regenerating initramfs (mkinitcpio) ==="
    mkinitcpio -P
elif command -v dracut &>/dev/null; then
    echo "=== Regenerating initramfs (dracut) ==="
    dracut --force
fi

# --- UPower ---
if [ -f /etc/UPower/UPower.conf ]; then
    sed -i 's/^CriticalPowerAction=.*/CriticalPowerAction=Hibernate/' /etc/UPower/UPower.conf
    systemctl restart upower 2>/dev/null || true
fi

# --- sleep.conf ---
cat > /etc/systemd/sleep.conf <<EOF
[Sleep]
HibernateMode=shutdown
EOF

# --- Sleep hook ---
mkdir -p /etc/systemd/system-sleep /usr/lib/systemd/system-sleep
install -m755 "$SCRIPT_DIR/hibernate-sleep-hook.sh" /etc/systemd/system-sleep/hibernate-sleep-hook.sh
install -m755 "$SCRIPT_DIR/hibernate-sleep-hook.sh" /usr/lib/systemd/system-sleep/hibernate-sleep-hook.sh

# --- Battery monitor ---
install -m755 "$SCRIPT_DIR/battery-hibernate.sh" /usr/local/bin/battery-hibernate.sh
if [ -f "$SCRIPT_DIR/../systemd/battery-hibernate.service" ]; then
    install -m644 "$SCRIPT_DIR/../systemd/battery-hibernate.service" /etc/systemd/system/battery-hibernate.service
elif [ -f "/usr/share/hibernate-5pct/battery-hibernate.service" ]; then
    install -m644 /usr/share/hibernate-5pct/battery-hibernate.service /etc/systemd/system/battery-hibernate.service
fi
systemctl daemon-reload
systemctl enable --now battery-hibernate.service 2>/dev/null || true

echo ""
echo "=== DONE ==="
echo "Reboot to apply. Test with: systemctl hibernate"