#!/usr/bin/env bats
#
# Tests for the test infrastructure itself: the fakes and the helpers.

setup() {
    load helpers
    common_setup
}

readonly DEVICE=/org/freedesktop/UPower/devices/DisplayDevice

@test "every faked command resolves to the fake" {
    local cmd
    for cmd in "${FAKED_COMMANDS[@]}"; do
        assert_equal "$(command -v "$cmd")" "$FAKE_DIR/bin/$cmd"
    done
}

@test "a call without rules prints nothing and succeeds" {
    run --separate-stderr busctl --system get-property org.freedesktop.UPower "$DEVICE"
    assert_status 0
    assert_output ""
    assert_stderr ""
}

@test "calls are logged with their arguments" {
    busctl --system get-property org.freedesktop.UPower "$DEVICE" org.freedesktop.UPower.Device State
    notify-send --app-name=battery-notify Title Body
    assert_called busctl --system get-property org.freedesktop.UPower "$DEVICE" org.freedesktop.UPower.Device State
    assert_called notify-send --app-name=battery-notify Title Body
    assert_equal "$(calls | wc -l)" 2
}

@test "arguments with spaces are logged exactly" {
    notify-send "Battery 58%" "3:36 remaining"
    assert_called notify-send "Battery 58%" "3:36 remaining"
    run assert_called notify-send Battery 58% 3:36 remaining
    assert_status 1
}

@test "a rule sets stdout and exit code" {
    fake busctl --stdout "u 2" --exit 3
    run busctl --system get-property org.freedesktop.UPower "$DEVICE" org.freedesktop.UPower.Device State
    assert_status 3
    assert_output "u 2"
}

@test "multi-line stdout is printed as given" {
    fake busctl --stdout $'d 58\nu 2'
    run busctl anything
    assert_output $'d 58\nu 2'
}

@test "rules only apply to calls matching their pattern" {
    fake busctl --args "* State" --stdout "u 2"
    run busctl --system get-property org.freedesktop.UPower "$DEVICE" org.freedesktop.UPower.Device State
    assert_output "u 2"
    run busctl --system get-property org.freedesktop.UPower "$DEVICE" org.freedesktop.UPower.Device Percentage
    assert_output ""
}

@test "the last registered matching rule wins" {
    fake busctl --stdout "fallback"
    fake busctl --args "* State" --stdout "u 2"
    run busctl get-property State
    assert_output "u 2"
    run busctl get-property Percentage
    assert_output "fallback"
}

@test "calls CMD filters the log by command" {
    busctl a
    notify-send b
    busctl c
    assert_equal "$(calls busctl)" $'busctl a\nbusctl c'
}

@test "refute_called passes and fails correctly" {
    refute_called notify-send
    notify-send hello
    run refute_called notify-send
    assert_status 1
}

@test "assertions fail with a message" {
    run --separate-stderr assert_equal "a" "b"
    assert_status 1
    assert_stderr $'expected:\nb\nactual:\na'
}

@test "a --once rule answers one call, then the next rule applies" {
    fake busctl --stdout "d 50"
    fake busctl --stdout "d 58" --once
    assert_equal "$(busctl get-property Percentage)" "d 58"
    assert_equal "$(busctl get-property Percentage)" "d 50"
    assert_equal "$(busctl get-property Percentage)" "d 50"
}

@test "a --hang rule prints, then runs until killed" {
    fake gdbus --stdout "signal" --hang
    local line fd
    exec {fd}< <(gdbus monitor)
    local -r pid=$!
    read -r -t 5 -u "$fd" line || fail "no line printed"
    assert_equal "$line" "signal"
    kill -0 "$pid" || fail "exited instead of hanging"
    run refute_hanging gdbus
    assert_status 1
    refute_hanging gdbus # the failed check above killed it
    exec {fd}<&-
}

@test "concurrent calls are logged as whole lines" {
    # The daemon runs gdbus in the background while calling busctl; the fakes
    # must not interleave their log lines.
    local i
    for ((i = 0; i < 40; i++)); do
        busctl --system get-property org.freedesktop.UPower "$DEVICE" org.freedesktop.UPower.Device State &
        gdbus monitor --system --dest org.freedesktop.UPower &
    done
    wait
    assert_equal "$(calls | wc -l)" 80
    assert_equal "$(grep -cvxE '(busctl --system get-property org\.freedesktop\.UPower /org/freedesktop/UPower/devices/DisplayDevice org\.freedesktop\.UPower\.Device State|gdbus monitor --system --dest org\.freedesktop\.UPower)' "$FAKE_DIR/calls.log")" 0
}
