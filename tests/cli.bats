#!/usr/bin/env bats
#
# The command line, run as a real process with every external command faked.

setup() {
    load helpers
    common_setup
}

usage_hint="Try 'battery-notify --help' for more information."

@test "--help prints usage to stdout and succeeds" {
    run --separate-stderr "$BATTERY_NOTIFY" --help
    assert_status 0
    assert_stderr ""
    [[ "${lines[0]}" == "Usage: battery-notify show" ]] ||
        fail "unexpected first line: ${lines[0]}"
}

@test "--version prints the version" {
    run --separate-stderr "$BATTERY_NOTIFY" --version
    assert_status 0
    [[ "$output" =~ ^battery-notify\ [0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        fail "unexpected output: $output"
}

@test "no command is a usage error" {
    run --separate-stderr "$BATTERY_NOTIFY"
    assert_status 2
    assert_output ""
    assert_stderr "battery-notify: missing command"$'\n'"$usage_hint"
}

@test "an unknown command is a usage error" {
    local cmd
    for cmd in --daemon -d start notify; do
        run --separate-stderr "$BATTERY_NOTIFY" "$cmd"
        assert_status 2
        assert_stderr "battery-notify: unknown command '$cmd'"$'\n'"$usage_hint"
    done
}

@test "an unknown command with arguments is still an unknown command" {
    run --separate-stderr "$BATTERY_NOTIFY" start 60
    assert_status 2
    assert_stderr "battery-notify: unknown command 'start'"$'\n'"$usage_hint"
}

@test "usage errors never touch the system" {
    run "$BATTERY_NOTIFY" show extra
    assert_status 2
    assert_equal "$(calls)" ""
}

# --- helpers for UPower and the config ---------------------------------------

readonly READ_ARGV=(--system get-property org.freedesktop.UPower /org/freedesktop/UPower/devices/DisplayDevice
    org.freedesktop.UPower.Device IsPresent Type State Percentage TimeToEmpty TimeToFull)
readonly READ_ARGS="${READ_ARGV[*]}"

# fake_battery STATE PERCENTAGE TIME_TO_EMPTY TIME_TO_FULL [PRESENT [TYPE]]
# UPower's answer, as busctl prints it. STATE is UPower's number (2 discharging).
fake_battery() {
    fake busctl --args "$READ_ARGS" \
        --stdout "b ${5:-true}"$'\n'"u ${6:-2}"$'\n'"u $1"$'\n'"d $2"$'\n'"x $3"$'\n'"x $4"
}

# user_config TEXT: write TEXT as the user's config, in the default location.
user_config() {
    mkdir -p "$HOME/.config/battery-notify"
    printf '%s\n' "$1" >"$HOME/.config/battery-notify/config"
}

assert_notified() { # URGENCY EXPIRE_MS TITLE BODY
    assert_called notify-send --app-name=battery-notify "--urgency=$1" "--expire-time=$2" "$3" "$4"
}

# --- status ------------------------------------------------------------------

@test "status: on battery" {
    fake_battery 2 58 12960 0
    run --separate-stderr "$BATTERY_NOTIFY" status
    assert_status 0
    assert_stderr ""
    assert_output "$(printf '%s\n' state=discharging percentage=58 time_to_empty=12960 time_to_full=0)"
    assert_called busctl "${READ_ARGV[@]}"
}

@test "status: charging, and full" {
    fake_battery 1 58 0 4200
    run "$BATTERY_NOTIFY" status
    assert_output "$(printf '%s\n' state=charging percentage=58 time_to_empty=0 time_to_full=4200)"
    fake_battery 4 100 0 0
    run "$BATTERY_NOTIFY" status
    assert_output "$(printf '%s\n' state=full percentage=100 time_to_empty=0 time_to_full=0)"
}

@test "status: a fractional percentage is rounded down" {
    fake_battery 2 57.93 12960 0
    run "$BATTERY_NOTIFY" status
    assert_equal "${lines[1]}" "percentage=57"
}

@test "status: UPower unreachable is a system error" {
    fake busctl --args "$READ_ARGS" --exit 1
    run --separate-stderr "$BATTERY_NOTIFY" status
    assert_status 4
    assert_output ""
    assert_stderr "battery-notify: could not read the battery from UPower"
}

@test "status: an unexpected answer from UPower is a system error" {
    local answer
    for answer in "abc" $'b true\nu 2\nu 2\nd 58\nx 1' $'b true\nu 2\nu 9\nd 58\nx 1\nx 0' \
        $'b true\nu 2\nu 2\nd 101\nx 1\nx 0' $'b true\nu 2\nu 2\nd 58\nx -1\nx 0' \
        $'b true\nu 2\nu 2\nd 5e1\nx 1\nx 0'; do
        fake busctl --args "$READ_ARGS" --stdout "$answer"
        run --separate-stderr "$BATTERY_NOTIFY" status
        assert_status 4
        assert_stderr "battery-notify: unexpected answer from UPower"
    done
}

@test "status: no battery has its own exit code" {
    fake_battery 0 0 0 0 false 0
    run --separate-stderr "$BATTERY_NOTIFY" status
    assert_status 5
    assert_stderr "battery-notify: no battery found"
    fake_battery 2 58 0 0 true 1 # a line power device, not a battery
    run "$BATTERY_NOTIFY" status
    assert_status 5
}

@test "status: a config error fails before reading the battery" {
    user_config $'[plugged]\ntitel = a'
    run --separate-stderr "$BATTERY_NOTIFY" status
    assert_status 3
    assert_stderr "battery-notify: $HOME/.config/battery-notify/config:2: unknown key 'titel'"
    refute_called busctl
}

# --- show --------------------------------------------------------------------

@test "show: on battery, with the default config" {
    fake_battery 2 58 12960 0
    run --separate-stderr "$BATTERY_NOTIFY" show
    assert_status 0
    assert_output ""
    assert_stderr ""
    assert_notified normal 2000 "Battery 58%" "3h 36m remaining"
}

@test "show: charging, and full" {
    fake_battery 1 58 0 4200
    run "$BATTERY_NOTIFY" show
    assert_notified normal 2000 "Battery 58%" "1h 10m to full"
    fake_battery 4 100 0 0
    run "$BATTERY_NOTIFY" show
    assert_notified normal 2000 "Battery Full" "Battery 100%"
}

@test "show: a time UPower does not know yet" {
    fake_battery 2 58 0 0
    run "$BATTERY_NOTIFY" show
    assert_notified normal 2000 "Battery 58%" "estimating... remaining"
}

@test "show: the user's config replaces the defaults" {
    user_config $'[show discharging]\nurgency = low\ntimeout = 500\ntitle = {level}!\nmessage = {time}'
    fake_battery 2 58 12960 0
    run "$BATTERY_NOTIFY" show
    assert_status 0
    assert_notified low 500 "58!" "3h 36m"
}

@test "show: XDG_CONFIG_HOME is used when set and absolute" {
    mkdir -p "$BATS_TEST_TMPDIR/xdg/battery-notify"
    printf '[show discharging]\ntitle = from xdg\n' >"$BATS_TEST_TMPDIR/xdg/battery-notify/config"
    user_config $'[show discharging]\ntitle = from home'
    fake_battery 2 58 12960 0
    XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/xdg" run "$BATTERY_NOTIFY" show
    assert_notified normal 2000 "from xdg" ""
    # A relative XDG_CONFIG_HOME is ignored, as the XDG specification says.
    XDG_CONFIG_HOME="relative/dir" run "$BATTERY_NOTIFY" show
    assert_notified normal 2000 "from home" ""
}

@test "show: a config error fails before anything else" {
    user_config $'[plugged]\ntitle = a\nurgency = high'
    run --separate-stderr "$BATTERY_NOTIFY" show
    assert_status 3
    assert_stderr "battery-notify: $HOME/.config/battery-notify/config:3: invalid urgency 'high': expected low, normal or critical"
    refute_called busctl
    refute_called notify-send
}

@test "show: no section for the current state is a config error" {
    user_config $'[show discharging]\ntitle = a'
    fake_battery 1 58 0 4200
    run --separate-stderr "$BATTERY_NOTIFY" show
    assert_status 3
    assert_stderr "battery-notify: $HOME/.config/battery-notify/config: no [show charging] section"
    refute_called notify-send
}

@test "show: an unreadable config is a system error" {
    mkdir -p "$HOME/.config/battery-notify/config" # a directory, not a file
    run --separate-stderr "$BATTERY_NOTIFY" show
    assert_status 4
    assert_stderr "battery-notify: cannot read $HOME/.config/battery-notify/config"
}

@test "show: a failed notification is a system error" {
    fake_battery 2 58 12960 0
    fake notify-send --exit 1
    run --separate-stderr "$BATTERY_NOTIFY" show
    assert_status 4
    assert_stderr "battery-notify: could not send a notification"
}

# --- daemon ------------------------------------------------------------------

readonly MONITOR_ARGS=(monitor --system --dest org.freedesktop.UPower
    --object-path /org/freedesktop/UPower/devices/DisplayDevice)
readonly CHANGED="/org/freedesktop/UPower/devices/DisplayDevice: org.freedesktop.DBus.Properties.PropertiesChanged ('org.freedesktop.UPower.Device', {'Percentage': <14.0>}, @as [])"

# readings "STATE PERCENT TTE TTF" ...: successive UPower answers; the last repeats.
readings() {
    local -r all=("$@")
    local i fields
    read -ra fields <<<"${all[-1]}"
    fake_battery "${fields[@]}"
    for ((i = ${#all[@]} - 2; i >= 0; i--)); do
        read -ra fields <<<"${all[i]}"
        fake busctl --args "$READ_ARGS" --once \
            --stdout "b true"$'\n'"u 2"$'\n'"u ${fields[0]}"$'\n'"d ${fields[1]}"$'\n'"x ${fields[2]}"$'\n'"x ${fields[3]}"
    done
}

# monitor_lines N: the fake monitor prints N change lines, then ends (as if
# UPower's bus connection was lost), which ends the daemon.
monitor_lines() {
    local out="" i
    for ((i = 0; i < $1; i++)); do
        out+="${out:+$'\n'}$CHANGED"
    done
    fake gdbus --stdout "$out"
}

@test "daemon: notifies a level crossed while discharging" {
    readings "2 50 18000 0" "2 14 5000 0"
    monitor_lines 1
    run --separate-stderr "$BATTERY_NOTIFY" daemon
    assert_status 4
    assert_stderr "battery-notify: lost the connection to UPower"
    assert_called gdbus "${MONITOR_ARGS[@]}"
    assert_notified critical 0 "Battery low" "Connect the charger: 14% left"
    assert_equal "$(calls notify-send | wc -l)" 1
}

@test "daemon: issue #1: charging from a low level warns about nothing low" {
    readings "1 8 0 6000" "1 12 0 5000" "1 16 0 4000" "1 21 0 3000"
    monitor_lines 3
    run "$BATTERY_NOTIFY" daemon
    assert_status 4
    assert_called gdbus "${MONITOR_ARGS[@]}"
    assert_equal "$(calls busctl | wc -l)" 4 # every reading was seen
    # Only the charging levels, as normal time-to-full notifications; no
    # low-battery warning (those are critical and say "Connect the charger").
    assert_notified normal 2000 "Battery 12%" "1h 23m to full"
    assert_notified normal 2000 "Battery 16%" "1h 06m to full"
    assert_notified normal 2000 "Battery 21%" "0h 50m to full"
    assert_equal "$(calls notify-send | wc -l)" 3
    [[ "$(calls notify-send)" != *critical* && "$(calls notify-send)" != *"Connect the charger"* ]] ||
        fail "a low-battery warning while charging: $(calls notify-send)"
}

@test "daemon: plugged and unplugged" {
    # 31%: above the 30% level, so the start-up rule stays quiet.
    readings "2 31 9000 0" "1 31 0 5000" "2 31 9000 0"
    monitor_lines 2
    run "$BATTERY_NOTIFY" daemon
    assert_notified normal 2000 "Charger connected" "Battery 31% · 1h 23m to full"
    assert_notified normal 2000 "Charger disconnected" "Battery 31% · 2h 30m remaining"
    assert_equal "$(calls notify-send | wc -l)" 2
}

@test "daemon: at start-up on battery at a low level, the nearest level fires" {
    readings "2 8 2400 0"
    monitor_lines 0
    run "$BATTERY_NOTIFY" daemon
    assert_notified critical 0 "Battery low" "Connect the charger: 8% left"
    assert_equal "$(calls notify-send | wc -l)" 1
}

@test "daemon: at start-up on battery at an ordinary level, nothing fires" {
    readings "2 58 12960 0"
    monitor_lines 0
    run "$BATTERY_NOTIFY" daemon
    assert_called busctl "${READ_ARGV[@]}"
    refute_called notify-send
}

@test "daemon: at start-up on AC, nothing fires" {
    readings "1 8 0 6000"
    monitor_lines 0
    run "$BATTERY_NOTIFY" daemon
    assert_called gdbus "${MONITOR_ARGS[@]}"
    assert_called busctl "${READ_ARGV[@]}"
    refute_called notify-send
}

@test "daemon: a change line with nothing new notifies nothing" {
    readings "1 50 0 3000"
    monitor_lines 3
    run "$BATTERY_NOTIFY" daemon
    refute_called notify-send
    assert_equal "$(calls busctl | wc -l)" 4 # start-up, then one per line
}

@test "daemon: a config error is notified once, and nothing else runs" {
    user_config $'[discharging 15]
titel = a'
    run --separate-stderr "$BATTERY_NOTIFY" daemon
    assert_status 3
    assert_stderr "battery-notify: $HOME/.config/battery-notify/config:2: unknown key 'titel'"
    assert_notified critical 0 "battery-notify: config error" "$HOME/.config/battery-notify/config:2: unknown key 'titel'"
    refute_called gdbus
    refute_called busctl
}

@test "daemon: no battery has its own exit code, and stops the monitor" {
    fake_battery 0 0 0 0 false 0
    fake gdbus --hang
    run --separate-stderr "$BATTERY_NOTIFY" daemon
    assert_status 5
    assert_stderr "battery-notify: no battery found"
    refute_hanging gdbus
}

@test "daemon: UPower failing mid-way is a system error, and stops the monitor" {
    fake busctl --args "$READ_ARGS" --exit 1
    fake busctl --args "$READ_ARGS" --once --stdout $'b true\nu 2\nu 2\nd 50\nx 18000\nx 0'
    fake gdbus --stdout "$CHANGED" --hang
    run --separate-stderr "$BATTERY_NOTIFY" daemon
    assert_status 4
    assert_stderr "battery-notify: could not read the battery from UPower"
    refute_hanging gdbus
}

@test "daemon: a failed notification does not stop the daemon" {
    readings "2 50 18000 0" "2 14 5000 0" "2 9 3000 0"
    fake notify-send --exit 1
    monitor_lines 2
    run --separate-stderr "$BATTERY_NOTIFY" daemon
    assert_status 4
    assert_equal "$(calls notify-send | wc -l)" 2
    assert_stderr $'battery-notify: could not send a notification\nbattery-notify: could not send a notification\nbattery-notify: lost the connection to UPower'
}

@test "daemon: stopping it (SIGTERM) also stops its monitor" {
    readings "1 50 0 3000"
    fake gdbus --hang
    # 3>&-: a background process must not keep bats' own output open.
    "$BATTERY_NOTIFY" daemon 3>&- &
    local -r pid=$!
    local i
    for ((i = 0; i < 50; i++)); do
        [[ -s "$FAKE_DIR/gdbus.hanging" ]] && break
        sleep 0.1
    done
    [[ -s "$FAKE_DIR/gdbus.hanging" ]] || fail "the monitor never started"
    sleep 0.2
    kill -TERM "$pid"
    local -i status=0
    wait "$pid" || status=$?
    assert_equal "$status" 143
    refute_hanging gdbus
}
