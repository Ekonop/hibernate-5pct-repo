# Hibernate at 5% Battery

Configure Linux to **hibernate (suspend-to-disk)** when battery reaches 5%,
saving all work state and applications, instead of discharging to 0%.

## Features

- **Auto-detects** root device, UUID, filesystem, battery, TPM/WiFi devices
- Supports **Arch/CachyOS** (pacman, mkinitcpio, refind/grub/systemd-boot)
- **btrfs** swap file (dedicated non-snapshotted subvolume) or any filesystem
- Sleep hook unbinds TPM + WiFi to avoid suspend errors
- Battery monitor service triggers hibernate at configurable threshold (default 5%)
- UPower `CriticalPowerAction=Hibernate` as a backup (triggers at 2%)

## Quick Start

```bash
git clone <repo-url>
cd hibernate-5pct
sudo bash scripts/install.sh
# reboot, then test:
systemctl hibernate
```

## Requirements

- Linux with systemd
- Root/sudo access
- Enough disk space for swap file (RAM size + 2 GB)
- `mkinitcpio` or `dracut`
- `upower`

## Configuration

| Env var | Default | Description |
|---------|---------|-------------|
| `HIBERNATE_THRESHOLD` | 5 | Battery percentage to trigger hibernate |

## How It Works

1. **Swap file** — A dedicated swap file (≥ RAM size) is created on a separate
   btrfs subvolume (or directory) so hibernation has somewhere to save RAM state.
2. **Resume params** — Kernel cmdline gets `resume=UUID=... resume_offset=...`
   so the bootloader can find and restore the hibernation image.
3. **Sleep hook** — Unbinds TPM and WiFi drivers before hibernate (they cause
   suspend failures on many laptops), rebinds them after resume.
4. **Battery monitor** — A systemd service polls the battery every 60s and
   calls `systemctl hibernate` when battery ≤ threshold and not charging.
5. **UPower backup** — `CriticalPowerAction=Hibernate` triggers at 2% as a
   last resort.

## Troubleshooting

- **"Unable to resume"** — Recompute `resume_offset`:
  `btrfs inspect-internal map-swapfile -r /swap/swapfile`
- **Hibernation aborts** — Check `journalctl -b | grep -i hibernat` for
  device errors. Add the offending device to the sleep hook.
- **TPM/WiFi won't rebind** — Reboot; the hook rebinds on `post`.

## Uninstall

```bash
sudo systemctl disable --now battery-hibernate.service
sudo rm /etc/systemd/system/battery-hibernate.service
sudo rm /usr/local/bin/battery-hibernate.sh
sudo rm /etc/systemd/system-sleep/hibernate-sleep-hook.sh
# Remove swap file, fstab entries, and revert bootloader params manually.
```

## License

MIT