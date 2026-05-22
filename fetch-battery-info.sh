#!/usr/bin/env bash

# Fetch Battery Info
# ===================
# A utility script to fetch and return battery information.
# Output Format: <percentage> <Charging|Discharging> <hh:mm:ss|null>

fetch_battery_info() {
    local battery_info
    battery_info=$(acpi -b)

    local percentage status remaining_time

    percentage=$(echo "$battery_info" | grep -P -o '[0-9]+(?=%)')
    status=$(echo "$battery_info" | grep -o "Charging")
    remaining_time=$(echo "$battery_info" | grep -P -o '\d{2}:\d{2}:\d{2}')

    if [[ -z "$status" ]]; then
        status="Discharging"
    fi

    # Print values in a structured way
    echo "$percentage $status ${remaining_time:-null}"
}

# If the script is being run (not sourced), call the function
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    fetch_battery_info
fi