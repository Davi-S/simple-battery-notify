#!/usr/bin/env bats
#
# Pure functions, tested by sourcing the script (main does not run).

setup() {
    load helpers
    common_setup
    # shellcheck source=src/battery-notify
    source "$BATTERY_NOTIFY"
}

# config TEXT: parse TEXT as a config; rules are printed with | for the
# separator, so expectations are readable.
config() {
    local out
    out="$(parse_config "$1")" || {
        local -r code=$?
        printf '%s\n' "$out"
        return "$code"
    }
    printf '%s\n' "$out" | tr '\037' '|'
}

# --- parse_config: valid files -----------------------------------------------

@test "config: a section with every key" {
    run config $'[discharging 15]\nurgency = critical\ntimeout = 5000\ntitle = Battery low\nmessage = {level}% left'
    assert_status 0
    assert_output "discharging 15|critical|5000|Battery low|{level}% left"
}

@test "config: defaults for urgency, timeout and message" {
    run config $'[plugged]\ntitle = Charger connected'
    assert_output "plugged|normal|2000|Charger connected|"
}

@test "config: critical notifications stay until dismissed by default" {
    run config $'[discharging 5]\nurgency = critical\ntitle = Battery critical'
    assert_output "discharging 5|critical|0|Battery critical|"
}

@test "config: every event name" {
    local event
    for event in "discharging 1" "discharging 100" "charging 80" full plugged unplugged \
        "show discharging" "show charging" "show full"; do
        run config "[$event]"$'\ntitle = x'
        assert_status 0
        assert_output "$event|normal|2000|x|"
    done
}

@test "config: comments, blank lines and spaces around = and values are ignored" {
    run config $'# comment\n\n  [plugged]  \n  # another\ntitle=Charger   \n  message   =   Battery {level}%  \n'
    assert_status 0
    assert_output "plugged|normal|2000|Charger|Battery {level}%"
}

@test "config: a # inside a value is kept" {
    run config $'[plugged]\ntitle = Charger #1'
    assert_output "plugged|normal|2000|Charger #1|"
}

@test "config: several sections, in file order" {
    run config $'[plugged]\ntitle = a\n\n[discharging 10]\ntitle = b'
    assert_output $'plugged|normal|2000|a|\ndischarging 10|normal|2000|b|'
}

@test "config: an empty file has no rules" {
    run config ""
    assert_status 0
    assert_output ""
}

# --- parse_config: errors ----------------------------------------------------

# assert_config_error TEXT MESSAGE: parsing TEXT fails with "LINE: problem".
assert_config_error() {
    run config "$1"
    assert_status 1
    assert_output "$2"
}

@test "config errors: unknown or malformed event" {
    assert_config_error "[discharge 15]" "1: unknown event 'discharge 15'"
    assert_config_error "[discharging]" "1: unknown event 'discharging'"
    assert_config_error "[discharging 0]" "1: unknown event 'discharging 0'"
    assert_config_error "[discharging 101]" "1: unknown event 'discharging 101'"
    assert_config_error "[discharging 015]" "1: unknown event 'discharging 015'"
    assert_config_error "[charging  80]" "1: unknown event 'charging  80'"
    assert_config_error "[show]" "1: unknown event 'show'"
    assert_config_error "[]" "1: unknown event ''"
}

@test "config errors: duplicate section" {
    assert_config_error $'[plugged]\ntitle = a\n[plugged]\ntitle = b' "3: duplicate section [plugged]"
}

@test "config errors: keys" {
    assert_config_error $'[plugged]\ntitel = a' "2: unknown key 'titel'"
    assert_config_error $'[plugged]\ntitle = a\ntitle = b' "3: duplicate key 'title'"
    assert_config_error $'title = a' "1: 'title' is outside a section"
    assert_config_error $'[plugged]\nmessage = x' "1: section [plugged] has no title"
    assert_config_error $'[plugged]\ntitle =' "2: empty title"
}

@test "config errors: values" {
    assert_config_error $'[plugged]\ntitle = a\nurgency = high' "3: invalid urgency 'high': expected low, normal or critical"
    assert_config_error $'[plugged]\ntitle = a\ntimeout = 2s' "3: invalid timeout '2s': expected milliseconds from 0 to 9999999"
    assert_config_error $'[plugged]\ntitle = a\ntimeout = 010' "3: invalid timeout '010': expected milliseconds from 0 to 9999999"
    assert_config_error $'[plugged]\ntitle = Battery {percent}%' "2: unknown placeholder '{percent}': expected {level} or {time}"
    assert_config_error $'[plugged]\ntitle = a\nmessage = {LEVEL}' "3: unknown placeholder '{LEVEL}': expected {level} or {time}"
    assert_config_error "[plugged]"$'\n'"title = a"$'\037'"b" "2: invalid character in title"
}

@test "config errors: a line that is neither a section nor a key" {
    assert_config_error $'[plugged]\ntitle = a\njust some text' "3: expected '[event]' or 'key = value'"
    assert_config_error $'[plugged\ntitle = a' "1: expected '[event]' or 'key = value'"
}

@test "config errors: the first error is reported" {
    assert_config_error $'[plugged]\ntitel = a\nurgency = high' "2: unknown key 'titel'"
}

@test "config: the built-in defaults are valid" {
    run config "$DEFAULT_CONFIG"
    assert_status 0
    local event
    for event in "show discharging" "show charging" "show full" plugged unplugged full \
        "discharging 15" "discharging 10" "discharging 5"; do
        grep -q "^$event|" <<<"$output" || fail "no [$event] in the defaults"
    done
}

# --- battery values ----------------------------------------------------------

@test "state_name maps UPower's State to names" {
    local -A names=([0]=unknown [1]=charging [2]=discharging [3]=empty [4]=full
        [5]=pending-charge [6]=pending-discharge)
    local code
    for code in "${!names[@]}"; do
        assert_equal "$(state_name "$code")" "${names[$code]}"
    done
    run state_name 7
    assert_status 1
}

@test "power_source: on AC or on battery, by state" {
    local state
    for state in charging full pending-charge; do
        assert_equal "$(power_source "$state")" ac
    done
    for state in discharging empty pending-discharge; do
        assert_equal "$(power_source "$state")" battery
    done
    assert_equal "$(power_source unknown)" unknown
}

@test "format_time: hours and minutes, or unknown" {
    assert_equal "$(format_time 12960)" "3:36"
    assert_equal "$(format_time 3600)" "1:00"
    assert_equal "$(format_time 59)" "0:00"
    assert_equal "$(format_time 360000)" "100:00"
    assert_equal "$(format_time 0)" "unknown"
}

@test "time_for: time to empty on battery, to full while charging, else none" {
    assert_equal "$(time_for discharging 12960 0)" 12960
    assert_equal "$(time_for charging 0 4200)" 4200
    assert_equal "$(time_for full 0 0)" 0
    assert_equal "$(time_for pending-charge 0 0)" 0
}

@test "fill_placeholders" {
    assert_equal "$(fill_placeholders 'Battery {level}% ({time} left)' 58 3:36)" "Battery 58% (3:36 left)"
    assert_equal "$(fill_placeholders '{level}{level}' 5 x)" "55"
    assert_equal "$(fill_placeholders 'no placeholders & more' 5 x)" "no placeholders & more"
    assert_equal "$(fill_placeholders '{time}' 5 'A&B')" "A&B"
}

@test "format_status" {
    run format_status discharging 58 12960 0
    assert_output "$(printf '%s\n' state=discharging percentage=58 time_to_empty=12960 time_to_full=0)"
}

@test "show_event: by state" {
    assert_equal "$(show_event discharging)" "show discharging"
    assert_equal "$(show_event empty)" "show discharging"
    assert_equal "$(show_event pending-discharge)" "show discharging"
    assert_equal "$(show_event unknown)" "show discharging"
    assert_equal "$(show_event charging)" "show charging"
    assert_equal "$(show_event pending-charge)" "show charging"
    assert_equal "$(show_event full)" "show full"
}

# --- decide_events: which notifications fire ---------------------------------

LEVELS_CONFIG=$'[discharging 20]\ntitle = a\n[discharging 15]\ntitle = a\n[discharging 10]\ntitle = a\n[charging 80]\ntitle = a\n[charging 100]\ntitle = a\n[plugged]\ntitle = a\n[unplugged]\ntitle = a\n[full]\ntitle = a'

# events PREV_STATE PREV_PERCENT STATE PERCENT: the events that fire, on one line.
events() {
    local rules
    rules="$(parse_config "$LEVELS_CONFIG")"
    decide_events "$1" "$2" "$3" "$4" "$rules" | paste -sd, -
}

@test "decide_events: nothing changes, nothing fires" {
    assert_equal "$(events discharging 50 discharging 50)" ""
    assert_equal "$(events discharging 50 discharging 49)" ""
}

@test "decide_events: a discharging level fires when the battery drops to it" {
    assert_equal "$(events discharging 16 discharging 15)" "discharging 15"
    assert_equal "$(events discharging 15 discharging 14)" ""
}

@test "decide_events: issue #1: no low-battery warning while charging" {
    assert_equal "$(events charging 9 charging 10)" ""
    assert_equal "$(events charging 14 charging 16)" ""
    assert_equal "$(events charging 19 charging 21)" ""
}

@test "decide_events: a charging level fires only on AC, rising to it" {
    assert_equal "$(events charging 79 charging 80)" "charging 80"
    assert_equal "$(events discharging 81 discharging 80)" ""
}

@test "decide_events: a jump over several levels fires only the most severe" {
    assert_equal "$(events discharging 40 discharging 12)" "discharging 15"
    assert_equal "$(events discharging 40 discharging 3)" "discharging 10"
    assert_equal "$(events charging 50 charging 100)" "charging 100"
}

@test "decide_events: plugged and unplugged, with a level crossed at the same time" {
    assert_equal "$(events discharging 30 charging 30)" "plugged"
    assert_equal "$(events full 100 discharging 100)" "unplugged"
    assert_equal "$(events charging 16 discharging 15)" "unplugged,discharging 15"
    assert_equal "$(events discharging 79 charging 80)" "plugged,charging 80"
}

@test "decide_events: full fires when UPower reports fully charged" {
    assert_equal "$(events charging 99 full 100)" "charging 100,full"
    assert_equal "$(events charging 100 full 100)" "full"
    assert_equal "$(events full 100 full 100)" ""
}

@test "decide_events: pending-charge (held at a charge limit) counts as on AC" {
    assert_equal "$(events charging 79 pending-charge 80)" "charging 80"
    assert_equal "$(events pending-charge 80 pending-charge 80)" ""
    assert_equal "$(events discharging 60 pending-charge 60)" "plugged"
}

@test "decide_events: unknown states fire nothing" {
    assert_equal "$(events unknown 50 discharging 14)" "discharging 15"
    assert_equal "$(events discharging 50 unknown 14)" ""
}

@test "decide_events: events without a section are silent" {
    local rules
    rules="$(parse_config $'[discharging 10]\ntitle = a')"
    assert_equal "$(decide_events discharging 50 charging 50 "$rules")" ""
    assert_equal "$(decide_events discharging 11 discharging 10 "$rules")" "discharging 10"
}

# --- startup_events ----------------------------------------------------------

startup() {
    local rules
    rules="$(parse_config "$LEVELS_CONFIG")"
    startup_events "$1" "$2" "$rules" | paste -sd, -
}

@test "startup_events: on battery at or below a level, the nearest one fires" {
    assert_equal "$(startup discharging 8)" "discharging 10"
    assert_equal "$(startup discharging 12)" "discharging 15"
    assert_equal "$(startup discharging 15)" "discharging 15"
}

@test "startup_events: nothing above every level, or when not on battery" {
    assert_equal "$(startup discharging 21)" ""
    assert_equal "$(startup charging 8)" ""
    assert_equal "$(startup full 100)" ""
}

# --- rule_for, render_rule ---------------------------------------------------

@test "rule_for finds the rule of an event" {
    local rules
    rules="$(parse_config "$LEVELS_CONFIG")"
    assert_equal "$(rule_for "discharging 15" "$rules" | tr '\037' '|')" "discharging 15|normal|2000|a|"
    run rule_for "discharging 5" "$rules"
    assert_status 1
    assert_output ""
}

@test "render_rule fills the placeholders" {
    local rule
    rule="$(parse_config $'[plugged]\nurgency = low\ntitle = Battery {level}%\nmessage = {time} to full')"
    assert_equal "$(render_rule "$rule" 58 1:10 | tr '\037' '|')" "low|2000|Battery 58%|1:10 to full"
}

# --- cli ---------------------------------------------------------------------

usage_hint="Try 'battery-notify --help' for more information."

@test "cli: commands take no arguments" {
    local cmd
    for cmd in show status daemon --help --version; do
        run --separate-stderr main "$cmd" extra
        assert_status 2
        assert_stderr "battery-notify: '$cmd' takes no arguments"$'\n'"$usage_hint"
    done
}
