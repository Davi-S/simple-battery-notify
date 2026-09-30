# Shared test setup and assertions. In a .bats file:
#
#   setup() {
#       load helpers
#       common_setup
#   }

# SC2034: variables defined here are used by the .bats files.
# SC2154: $status, $output and $stderr are set by bats' `run`.
# shellcheck disable=SC2034,SC2154

bats_require_minimum_version 1.5.0

PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
BATTERY_NOTIFY="$PROJECT_ROOT/src/battery-notify"

# Every external command battery-notify may call. Each is replaced by the fake
# in tests/fakes/fake, so a test can never touch the real system. When
# battery-notify starts using a new external command, add it here.
FAKED_COMMANDS=(busctl gdbus notify-send)

common_setup() {
    # Times in notifications are formatted in UTC, so expectations are fixed.
    export TZ=UTC
    # Never read the user's real configuration.
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    unset XDG_CONFIG_HOME
    export FAKE_DIR="$BATS_TEST_TMPDIR/fake"
    mkdir -p "$FAKE_DIR/bin" "$FAKE_DIR/rules"
    : >"$FAKE_DIR/calls.log"

    local cmd
    for cmd in "${FAKED_COMMANDS[@]}"; do
        ln -s "$PROJECT_ROOT/tests/fakes/fake" "$FAKE_DIR/bin/$cmd"
    done
    PATH="$FAKE_DIR/bin:$PATH"
}

# --- Fakes -------------------------------------------------------------------

# fake CMD [--args PATTERN] [--stdout TEXT] [--exit CODE] [--once] [--hang]
#
# Register how the fake CMD answers. PATTERN is a glob matched against all its
# arguments joined by spaces (default: '*', any call). When several rules
# match, the one registered last wins, so a test can override a default set in
# setup(). TEXT is printed followed by a newline.
#   --once  the rule answers a single call, then is removed. Register the
#           later answer first: `fake busctl --stdout 2`, `fake busctl --stdout 1 --once`.
#   --hang  after printing, keep running until killed (like `gdbus monitor`).
fake() {
    local -r cmd="$1"
    shift
    local pattern='*' stdout='' has_stdout=false code=0 once=false hang=false
    while (($# > 0)); do
        case "$1" in
        --args) pattern="$2" && shift ;;
        --stdout) stdout="$2" has_stdout=true && shift ;;
        --exit) code="$2" && shift ;;
        --once) once=true ;;
        --hang) hang=true ;;
        *)
            echo "fake: unknown option '$1'" >&2
            return 1
            ;;
        esac
        shift
    done

    local -r dir="$FAKE_DIR/rules/$cmd"
    mkdir -p "$dir"
    local -r count="$(find "$dir" -mindepth 1 -maxdepth 1 -type d | wc -l)"
    local -r rule="$dir/$(printf '%03d' "$count")"
    mkdir "$rule"
    printf '%s' "$pattern" >"$rule/pattern"
    printf '%s' "$code" >"$rule/exit"
    [[ "$once" == false ]] || : >"$rule/once"
    [[ "$hang" == false ]] || : >"$rule/hang"
    if [[ "$has_stdout" == true ]]; then
        printf '%s\n' "$stdout" >"$rule/stdout"
    else
        : >"$rule/stdout"
    fi
}

# calls [CMD]: print the logged calls, all or only CMD's, one per line.
calls() {
    if (($# == 0)); then
        cat "$FAKE_DIR/calls.log"
    else
        grep -E "^$1( |\$)" "$FAKE_DIR/calls.log" || true
    fi
}

# refute_hanging CMD: no fake CMD started with --hang is still running.
refute_hanging() {
    local -r file="$FAKE_DIR/$1.hanging"
    [[ -e "$file" ]] || fail "no hanging $1 was ever started"
    local pid
    while read -r pid; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            fail "$1 (PID $pid) was left running"
        fi
    done <"$file"
}

# --- Assertions --------------------------------------------------------------
# Each prints what went wrong to stderr and returns 1, which fails the test.

fail() {
    printf '%s\n' "$@" >&2
    return 1
}

# assert_equal ACTUAL EXPECTED
assert_equal() {
    [[ "$1" == "$2" ]] ||
        fail "expected:" "$2" "actual:" "$1"
}

# assert_status CODE: the exit code of the last `run`.
assert_status() {
    [[ "$status" -eq "$1" ]] ||
        fail "expected exit code $1, got $status" "stdout:" "$output" "stderr:" "${stderr-}"
}

# assert_output TEXT: the whole stdout of the last `run`.
assert_output() {
    assert_equal "$output" "$1"
}

# assert_stderr TEXT: the whole stderr of the last `run --separate-stderr`.
assert_stderr() {
    assert_equal "$stderr" "$1"
}

# assert_called CMD ARG...: CMD was called with exactly these arguments.
# Write the arguments naturally; they are quoted the same way the log is.
assert_called() {
    local expected
    expected="$(printf '%q' "$1")"
    (($# == 1)) || expected+="$(printf ' %q' "${@:2}")"
    grep -qFx -- "$expected" "$FAKE_DIR/calls.log" ||
        fail "expected call:" "  $expected" "actual calls:" "$(calls | sed 's/^/  /')"
}

# refute_called CMD: CMD was not called at all.
refute_called() {
    [[ -z "$(calls "$1")" ]] ||
        fail "expected no calls to $1, got:" "$(calls "$1" | sed 's/^/  /')"
}
