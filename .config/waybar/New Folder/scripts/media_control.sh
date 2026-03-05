#!/usr/bin/env bash
# Path: /etc/xdg/waybar/scripts/media_control.sh

# Store last action timestamp in temp file
TMPFILE="/tmp/waybar_media_last"
COOLDOWN=1  # 0.5 seconds

LAST=$(cat "$TMPFILE" 2>/dev/null || echo 0)
NOW=$(date +%s.%N)

DIFF=$(echo "$NOW - $LAST" | bc)

if (( $(echo "$DIFF < $COOLDOWN" | bc -l) )); then
    exit 0
fi

# Update last timestamp
echo "$NOW" > "$TMPFILE"

# Execute playerctl command passed as argument
playerctl "$1"
