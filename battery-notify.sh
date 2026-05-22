#!/usr/bin/env bash

# Battery Notify
# ==============
# Parses configuration and sends customized desktop notifications.

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Load configuration
USER_CONFIG="$HOME/.config/battery-notify/battery-notify.conf"
SYSTEM_CONFIG="/etc/battery-notify.conf"

if [[ -f "$USER_CONFIG" ]]; then
    source "$USER_CONFIG"
elif [[ -f "$SYSTEM_CONFIG" ]]; then
    source "$SYSTEM_CONFIG"
fi

# Fallback default timeout
TIMEOUT=${TIMEOUT:-2000}

# Source battery info
source "/usr/bin/fetch-battery-info"
read LEVEL CHARGING REMAINING_TIME < <(fetch_battery_info)

MATCHED=false

for level_config in "${BATTERY_LEVELS[@]}"; do
    IFS='|' read -r cfg_percent urgency title message command <<< "$level_config"
    
    if [[ "$LEVEL" -eq "$cfg_percent" ]]; then
        MATCHED=true
        
        # Replace placeholders with actual values
        message="${message//%LEVEL%/$LEVEL}"
        message="${message//%TIME%/$REMAINING_TIME}"
        
        # Extend timeout for critical notifications
        if [[ "$urgency" == "critical" ]]; then
            notify_timeout=$((TIMEOUT * 1000000))
        else
            notify_timeout=$TIMEOUT
        fi
        
        # Send notification
        notify-send -u "$urgency" -t "$notify_timeout" "$title" "$message"
        
        # Execute optional command
        if [[ -n "$command" ]]; then
            bash -c "$command"
        fi
        
        break
    fi
done

# Fallback behavior if script is run manually and no specific rule matches
if [[ "$MATCHED" == false ]]; then
    if [[ "$CHARGING" == "Charging" ]]; then
        notify-send -t "$TIMEOUT" "Battery Status" "Battery is at $LEVEL% (Charging)."
    else
        notify-send -t "$TIMEOUT" "Battery Status" "Battery is at $LEVEL% ($REMAINING_TIME remaining)."
    fi
fi