#!/usr/bin/env bash

# Auto Battery Notify
# ======================
# Daemon script to monitor battery levels and trigger notifications
# based on user-defined configurations.

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Load configuration
USER_CONFIG="$HOME/.config/battery-notify/battery-notify.conf"
SYSTEM_CONFIG="/etc/battery-notify.conf"

if [[ -f "$USER_CONFIG" ]]; then
    source "$USER_CONFIG"
elif [[ -f "$SYSTEM_CONFIG" ]]; then
    source "$SYSTEM_CONFIG"
fi

# Source the fetch-battery-info script
source "/usr/bin/fetch-battery-info"
read LEVEL CHARGING REMAINING_TIME < <(fetch_battery_info)

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/battery-notify"
STATE_FILE="$STATE_DIR/auto-battery-notify-state.txt"
mkdir -p "$STATE_DIR"

LAST_NOTIFIED_PERCENT=-1
if [[ -f "$STATE_FILE" ]]; then
    LAST_NOTIFIED_PERCENT=$(cat "$STATE_FILE")
fi

# Check if current level is in the configuration array
MATCHED=false
for level_config in "${BATTERY_LEVELS[@]}"; do
    # Extract just the first field (PERCENTAGE)
    IFS='|' read -r cfg_percent _ _ _ _ <<< "$level_config"
    
    if [[ "$LEVEL" -eq "$cfg_percent" ]]; then
        MATCHED=true
        break
    fi
done

# If a rule exists for this percentage and we haven't notified yet
if [[ "$MATCHED" == true && "$LEVEL" -ne "$LAST_NOTIFIED_PERCENT" ]]; then
    /usr/bin/battery-notify
    echo "$LEVEL" > "$STATE_FILE"
fi