#!/usr/bin/env bash

WORKSPACES=(1 2 3 4 5 6 7 8 9)
ACTIVE=$(hyprctl activeworkspace | awk '{print $2}')

json="["

for ws in "${WORKSPACES[@]}"; do
    if [[ "$ws" == "$ACTIVE" ]]; then
        color="#89b4fa"
    else
        color="#a6adc8"
    fi
    json+="{\"text\":\"$ws\",\"class\":\"workspace\",\"color\":\"$color\"},"
done

# Remove trailing comma and close array
json="${json%,}]"

echo "$json"
