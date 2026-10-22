#!/bin/sh
# Sleep hook: unbind problematic devices before hibernate, rebind after.
# Universal: auto-detects TPM and WiFi devices.
LOG=/tmp/hibernate-hook.log

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

unbind_devices() {
    # TPM
    for d in /sys/bus/platform/drivers/tpm_tis/*; do
        [ -e "$d/unbind" ] 2>/dev/null && continue
        dev=$(basename "$d")
        case "$dev" in
            module|bind|unbind|uevent) continue ;;
        esac
        echo "$dev" > /sys/bus/platform/drivers/tpm_tis/unbind 2>/dev/null && log "unbound TPM $dev" || true
    done
    # Also try tpm_crb
    for d in /sys/bus/platform/drivers/tpm_crb/*; do
        dev=$(basename "$d")
        case "$dev" in
            module|bind|unbind|uevent) continue ;;
        esac
        echo "$dev" > /sys/bus/platform/drivers/tpm_crb/unbind 2>/dev/null && log "unbound TPM(CRB) $dev" || true
    done
    # WiFi (mt7921e, iwlwifi, etc.)
    for drv in /sys/bus/pci/drivers/mt7921e /sys/bus/pci/drivers/iwlwifi /sys/bus/pci/drivers/rtw89*; do
        [ -d "$drv" ] || continue
        for d in "$drv"/[0-9]*; do
            [ -e "$d" ] || continue
            dev=$(basename "$d")
            echo "$dev" > "$drv/unbind" 2>/dev/null && log "unbound $dev from $drv" || true
        done
    done
}

bind_devices() {
    for drv in /sys/bus/pci/drivers/mt7921e /sys/bus/pci/drivers/iwlwifi; do
        [ -d "$drv" ] || continue
        for d in /sys/bus/pci/devices/*; do
            drvname=$(basename "$drv")
            if grep -q "$drvname" "$d/uevent" 2>/dev/null; then
                dev=$(basename "$d")
                echo "$dev" > "$drv/bind" 2>/dev/null && log "rebound $dev to $drv" || true
            fi
        done
    done
    for dev in /sys/bus/platform/drivers/tpm_tis/bind; do
        : # TPM rebind often fails; leave unbound is acceptable
    done
}

case "$1" in
    pre)  unbind_devices ;;
    post) bind_devices ;;
esac