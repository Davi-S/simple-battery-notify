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
