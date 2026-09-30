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

@test "status: no battery is a system error" {
    fake_battery 0 0 0 0 false 0
    run --separate-stderr "$BATTERY_NOTIFY" status
    assert_status 4
    assert_stderr "battery-notify: no battery found"
    fake_battery 2 58 0 0 true 1 # a line power device, not a battery
    run "$BATTERY_NOTIFY" status
    assert_status 4
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
    assert_notified normal 2000 "Battery 58%" "3:36 remaining"
}

@test "show: charging, and full" {
    fake_battery 1 58 0 4200
    run "$BATTERY_NOTIFY" show
    assert_notified normal 2000 "Battery 58% · charging" "1:10 to full"
    fake_battery 4 100 0 0
    run "$BATTERY_NOTIFY" show
    assert_notified normal 2000 "Battery full" ""
}

@test "show: a time UPower does not know yet" {
    fake_battery 2 58 0 0
    run "$BATTERY_NOTIFY" show
    assert_notified normal 2000 "Battery 58%" "unknown remaining"
}

@test "show: the user's config replaces the defaults" {
    user_config $'[show discharging]\nurgency = low\ntimeout = 500\ntitle = {level}!\nmessage = {time}'
    fake_battery 2 58 12960 0
    run "$BATTERY_NOTIFY" show
    assert_status 0
    assert_notified low 500 "58!" "3:36"
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
