#!/usr/bin/env bash
#
# Integration test against the real UPower. Run it on your desktop session
# before each release; CI can't, it has no UPower or battery.
#
# Usage: tests/integration.sh [--charger]
#   (or: make integration, make integration CHARGER=1)
#
#   Without options: automatic checks, about a minute (most of it watching the
#                    daemon across real UPower events).
#   --charger:       then asks you to unplug and replug the charger, and checks
#                    the daemon notified both.
#
# Tests src/battery-notify by default. To test an installed copy instead:
#   BATTERY_NOTIFY=/usr/bin/battery-notify tests/integration.sh
#
# The daemon under test uses a temporary config folder, so your own config
# never changes the results. It logs the busctl and notify-send calls it makes
# through wrappers put first on PATH (the real commands still run: you will see
# the notifications).

set -euo pipefail

BATTERY_NOTIFY="${BATTERY_NOTIFY:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/src/battery-notify}"
readonly BATTERY_NOTIFY

charger_checks=false
case "${1-}" in
"") ;;
--charger) charger_checks=true ;;
*)
    echo "usage: $0 [--charger]" >&2
    exit 2
    ;;
esac

failures=0

pass() {
    printf '  ok    %s\n' "$1"
}

fail() {
    printf '  FAIL  %s\n' "$1"
    failures=$((failures + 1))
}

# check DESCRIPTION EXPECTED ACTUAL
check() {
    if [[ "$3" == "$2" ]]; then
        pass "$1"
    else
        fail "$1: expected '$2', got '$3'"
    fi
}

section() {
    printf '\n%s\n' "$1"
}

# code ARG...: print battery-notify's exit code, discarding its output.
code() {
    local -i status=0
    "$BATTERY_NOTIFY" "$@" >/dev/null 2>&1 || status=$?
    printf '%s\n' "$status"
}

# field KEY: one value from `battery-notify status`.
field() {
    "$BATTERY_NOTIFY" status 2>/dev/null | sed -n "s/^$1=//p" || true
}

# now_ms: the wall clock in milliseconds.
now_ms() {
    local -r us="${EPOCHREALTIME/./}"
    printf '%s\n' "$((us / 1000))"
}

work="$(mktemp -d)"
daemon_pid=""
cleanup() {
    if [[ -n "$daemon_pid" ]]; then
        kill "$daemon_pid" 2>/dev/null || true
        wait "$daemon_pid" 2>/dev/null || true
    fi
    rm -rf "$work"
}
trap cleanup EXIT

# Wrappers that log each call, then run the real command.
mkdir -p "$work/bin" "$work/config/battery-notify"
for cmd in busctl notify-send; do
    real="$(command -v "$cmd")"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"%s/%s.log"\nexec "%s" "$@"\n' \
        "$work" "$cmd" "$real" >"$work/bin/$cmd"
    chmod +x "$work/bin/$cmd"
done

# run_isolated ARG...: battery-notify with the wrappers and the temporary config.
run_isolated() {
    PATH="$work/bin:$PATH" XDG_CONFIG_HOME="$work/config" "$BATTERY_NOTIFY" "$@"
}

log_count() { # CMD: how many calls the wrapper logged
    if [[ -f "$work/$1.log" ]]; then wc -l <"$work/$1.log"; else echo 0; fi
}

printf 'Testing %s (%s)\n' "$BATTERY_NOTIFY" "$("$BATTERY_NOTIFY" --version)"

# -----------------------------------------------------------------------------
section "status, against UPower's own report"

status_code="$(code status)"
if [[ "$status_code" == 5 ]]; then
    echo "  This machine has no battery; the remaining checks need one."
    exit 1
fi
check "status succeeds" 0 "$status_code"
check "status prints the four keys, in order" "state percentage time_to_empty time_to_full" \
    "$("$BATTERY_NOTIFY" status | cut -d= -f1 | paste -sd' ' -)"
upower_report="$(upower -i /org/freedesktop/UPower/devices/DisplayDevice)"
upower_state="$(sed -n 's/^ *state: *//p' <<<"$upower_report" | tr -d ' ')"
upower_state="${upower_state/fully-charged/full}"
check "state matches upower" "$upower_state" "$(field state)"
upower_percent="$(sed -n 's/^ *percentage: *\([0-9]*\).*/\1/p' <<<"$upower_report")"
check "percentage matches upower" "$upower_percent" "$(field percentage)"

# -----------------------------------------------------------------------------
section "show"

start="$(now_ms)"
check "show succeeds" 0 "$(code show)"
elapsed=$(($(now_ms) - start))
if ((elapsed <= 200)); then
    pass "show took ${elapsed} ms (limit 200; 1.x took ~290)"
else
    fail "show took ${elapsed} ms (limit 200)"
fi

# -----------------------------------------------------------------------------
section "Config errors"

printf '[show discharging]\ntitel = oops\n' >"$work/config/battery-notify/config"
check "show: a config error is exit 3" 3 "$(PATH="$work/bin:$PATH" XDG_CONFIG_HOME="$work/config" code show)"
error="$(run_isolated status 2>&1 >/dev/null || true)"
check "the error names the file and line" \
    "battery-notify: $work/config/battery-notify/config:2: unknown key 'titel'" "$error"
: >"$work/notify-send.log"
check "daemon: a config error is exit 3" 3 "$(PATH="$work/bin:$PATH" XDG_CONFIG_HOME="$work/config" code daemon)"
check "daemon: and it is notified once" 1 "$(log_count notify-send)"
check "daemon: before reading the battery" 0 "$(log_count busctl)"
rm "$work/config/battery-notify/config"

# -----------------------------------------------------------------------------
section "The daemon, across real UPower events (40 s)"

: >"$work/busctl.log"
: >"$work/notify-send.log"
# Started directly (not through run_isolated) so $! is the daemon itself.
env PATH="$work/bin:$PATH" XDG_CONFIG_HOME="$work/config" "$BATTERY_NOTIFY" daemon 2>"$work/daemon.err" &
daemon_pid=$!
sleep 40
if kill -0 "$daemon_pid" 2>/dev/null; then
    pass "still running after 40 s"
else
    fail "exited early; stderr: $(cat "$work/daemon.err")"
fi
reads="$(log_count busctl)"
if ((reads >= 2)); then
    pass "it read the battery at start and on $((reads - 1)) UPower event(s)"
else
    fail "only $reads battery reading(s): no UPower event was handled"
fi
check "nothing on stderr" "" "$(cat "$work/daemon.err")"

# -----------------------------------------------------------------------------
if [[ "$charger_checks" == true ]]; then
    section "Charger: unplug and replug"
    cat <<'EOF'
  The daemon under test is still running. Your installed battery-notify service
  may notify these events too, so you may see each notification twice.
EOF
    if [[ "$(field state)" =~ ^(discharging|empty|pending-discharge)$ ]]; then
        read -rp "  Plug the charger in first, then press Enter... "
        sleep 3
    fi

    # wait_for_notification TITLE SECONDS: wait until the daemon sent TITLE.
    wait_for_notification() {
        local -r limit=$(($(now_ms) + $2 * 1000))
        while (($(now_ms) < limit)); do
            if grep -qF -- "$1" "$work/notify-send.log"; then
                now_ms
                return 0
            fi
            sleep 0.1
        done
        return 1
    }

    : >"$work/notify-send.log"
    read -rp "  Unplug the charger, then press Enter right away... "
    asked="$(now_ms)"
    if seen="$(wait_for_notification "Charger disconnected" 30)"; then
        pass "'Charger disconnected' was notified ($((seen - asked)) ms after Enter)"
    else
        fail "no 'Charger disconnected' within 30 s"
    fi

    read -rp "  Plug it back in, then press Enter right away... "
    asked="$(now_ms)"
    if seen="$(wait_for_notification "Charger connected" 30)"; then
        pass "'Charger connected' was notified ($((seen - asked)) ms after Enter)"
    else
        fail "no 'Charger connected' within 30 s"
    fi
    check "nothing on stderr" "" "$(cat "$work/daemon.err")"
fi

# -----------------------------------------------------------------------------
printf '\n'
if ((failures == 0)); then
    echo "All checks passed."
else
    echo "$failures check(s) failed."
    exit 1
fi
