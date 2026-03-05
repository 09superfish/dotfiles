#!/usr/bin/env bash

# Get first available player
player=$(playerctl -l 2>/dev/null | head -n 1)
[ -z "$player" ] && echo '{"text":""}' && exit 0

# Get playback status
status=$(playerctl status 2>/dev/null)
[ "$status" = "Stopped" ] && echo '{"text":""}' && exit 0

# Metadata
artist=$(playerctl metadata artist 2>/dev/null)
title=$(playerctl metadata title 2>/dev/null)
arturl=$(playerctl metadata mpris:artUrl 2>/dev/null)
position=$(playerctl position 2>/dev/null)          # in seconds (float)
length=$(playerctl metadata mpris:length 2>/dev/null)  # in microseconds

# Convert length to seconds (integer)
length_sec=$(( length / 1000000 ))
position_int=${position%.*}  # truncate decimal for arithmetic

# Format MM:SS
format_time() {
    local T=$1
    local M=$((T/60))
    local S=$((T%60))
    printf "%d:%02d" $M $S
}

elapsed=$(format_time "$position_int")
total=$(format_time "$length_sec")

# Icons
[ "$status" = "Playing" ] && icon="" || icon=""

# Progress bar (10 steps)
bar_len=10
progress=0
if [[ -n "$length_sec" && "$length_sec" -gt 0 ]]; then
    progress=$(( position_int * bar_len / length_sec ))
fi

bar=""
for ((i=0;i<bar_len;i++)); do
    if [ $i -lt $progress ]; then
        bar+="━"
    else
        bar+="─"
    fi
done

# Text displayed on the bar (icon + artist/title + elapsed/total)
text="$icon  $artist - $title  $elapsed / $total"
text=$(echo "$text" | cut -c1-45)  # truncate if too long

# Tooltip (album art + full info)
tooltip="<b>$title</b>
          $artist
          $elapsed / $total
          $bar"
if [[ "$arturl" == file://* ]]; then
    tooltip="<img src='${arturl#file://}' width='180'/>\n$tooltip"
fi

# Output JSON for Waybar
jq -nc --arg text "$text" --arg tooltip "$tooltip" '{text:$text, tooltip:$tooltip}'
