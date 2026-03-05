#!/usr/bin/env bash

# Get current sink (default audio output)
sink=$(pactl info | grep "Default Sink" | awk '{print $3}')

# Get volume and mute status
volume=$(pactl get-sink-volume "$sink" | awk '{print $5}' | head -n1)
mute=$(pactl get-sink-mute "$sink" | awk '{print $2}')

# Icon based on volume / mute
if [ "$mute" = "yes" ]; then
    icon=""   # Muted
elif [ "${volume%?}" -le 30 ]; then
    icon=""   # Low volume
elif [ "${volume%?}" -le 70 ]; then
    icon=""   # Medium volume
else
    icon=""   # High volume
fi

echo "{\"text\":\"$icon  $volume\"}"
