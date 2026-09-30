#!/usr/bin/env bats
#
# Bash completion, tested by calling the completion function the way bash does.

setup() {
    load helpers
    # shellcheck source=completions/battery-notify.bash
    source "$PROJECT_ROOT/completions/battery-notify.bash"
}

# complete_words WORD...: complete the last WORD of "battery-notify WORD...",
# then print the candidates on one line.
complete_words() {
    COMP_WORDS=(battery-notify "$@")
    COMP_CWORD=$#
    COMPREPLY=()
    _battery_notify
    printf '%s\n' "${COMPREPLY[*]}"
}

@test "the first word completes to the commands" {
    assert_equal "$(complete_words "")" "show status daemon --help --version"
}

@test "a partial command completes" {
    assert_equal "$(complete_words "s")" "show status"
    assert_equal "$(complete_words "d")" "daemon"
    assert_equal "$(complete_words "--")" "--help --version"
}

@test "nothing to suggest after a command" {
    local cmd
    for cmd in show status daemon --help --version; do
        assert_equal "$(complete_words "$cmd" "")" ""
    done
}
