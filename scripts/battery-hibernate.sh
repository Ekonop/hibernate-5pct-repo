#!/bin/bash
# Hibernate when battery <= 5% and not charging.
# Universal: auto-detects battery device.
THRESHOLD="${HIBERNATE_THRESHOLD:-5}"
COOLDOWN=300

BATTERY=""
for b in /sys/class/power_supply/BAT*; do
    [ -r "$b/capacity" ] && BATTERY="$b" && break
done

if [ -z "$BATTERY" ]; then
    echo "No battery found; exiting." >&2
    exit 1
fi

while true; do
    if [ -r "$BATTERY/capacity" ] && [ -r "$BATTERY/status" ]; then
        cap=$(cat "$BATTERY/capacity")
        status=$(cat "$BATTERY/status")
        if [ "$status" != "Charging" ] && [ "$status" != "Full" ] && [ "$cap" -le "$THRESHOLD" ] 2>/dev/null; then
            logger -t battery-hibernate "Battery at ${cap}% (${status}); hibernating"
            systemctl hibernate
            sleep "$COOLDOWN"
        fi
    fi
    sleep 60
done