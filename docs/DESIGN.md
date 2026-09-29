# simple-battery-notify 2.0 design

Ground-up rewrite, from Python to Bash. No backwards compatibility with 1.x;
ships as 2.0.0. Unless stated here, it follows the design of expresso
(https://github.com/Davi-S/expresso/blob/main/docs/DESIGN.md) and decaf, so the
three tools behave, and are scripted and maintained, the same way.
This file records decisions. Open items are listed at the end.

## Why the rewrite

- **Issue #1:** low-battery warnings fire while charging. 1.x fires a level when
  the percentage crosses it in either direction.
- **Speed:** the on-demand notification takes 310–370 ms, ~245 ms of it starting
  Python and loading its D-Bus libraries. Reading UPower with `busctl` takes
  ~7 ms and `notify-send` ~31 ms, so Bash can show it in ~40 ms. (Measured
  2026-09-29.) The daemon also holds ~20 MB for the Python runtime.

## Goals

- Bash only. Runtime dependencies: `bash`, `systemd` (`busctl`), `glib2`
  (`gdbus`), `libnotify`, `upower`. No Python.
- Every feature is always on or doesn't exist.
- A strict, scriptable CLI, as in expresso and decaf.
- Fully testable in CI.

## CLI

```
battery-notify show       notify the current battery state (the keybind)
battery-notify status     print the battery state as key=value lines
battery-notify daemon     run by the systemd user service
battery-notify --help | --version
```

stdout is data only; messages and errors go to stderr.

## Runtime model

- `battery-notify.service` (systemd user service, enabled by the user) runs
  `battery-notify daemon` for the whole session.
- The daemon runs `gdbus monitor` on UPower. Each change line for the display
  device makes it read the current values with `busctl` (~7 ms) and compare them
  with the previous ones; that decides which notifications fire. Event-driven,
  no polling. UPower sends a change about every 30 s and on every charger event.
- The device is UPower's `DisplayDevice` (the combined battery).

## Levels and events

- **Levels have a direction** (fixes #1). A discharging level fires only while
  discharging, when the battery drops to or below it; a charging level fires
  only while charging, when it rises to or above it. A jump over several levels
  still fires, but only in that level's direction.
- **No commands.** 1.x could run a shell command at a level (e.g. hibernate at
  5%). Dropped: UPower's own critical action (`CriticalPowerAction` and
  `PercentageAction` in `/etc/UPower/UPower.conf`) does this more reliably, as a
  system service, even if the session is frozen. battery-notify only warns.

## Configuration

- **Fully customizable,** as in 1.x: which events notify, and each one's title,
  message, urgency and timeout.
- **Format:** simple `key=value` text, read by a strict Bash parser; never
  executed as code, and no `jq`. The 1.x JSON config is not read.

## Default notifications

The on-demand `show` notification, in the default config:

| State | Title | Body |
|---|---|---|
| On battery | Battery 58% | 3:36 remaining |
| Charging | Battery 58% · charging | 1:10 to full |
| Full | Battery full | |

## Code structure and testing

As in expresso and decaf: one file, `src/battery-notify`, in layers
(cli → core → system → values), discipline in place of types, bats with recording
fakes (`gdbus`, `busctl`, `notify-send`, …), and a local `tests/integration.sh`
against the real UPower.

## Open

- Config format for per-event rules, its location, precedence and error handling.
- The set of events, and message placeholders.
- `status` keys and exit codes.
- Daemon edge cases: start-up, several levels crossed at once, UPower restarts,
  no battery.
- Migration hint for the 1.x JSON config.
- The menu does not apply (this tool has none).
