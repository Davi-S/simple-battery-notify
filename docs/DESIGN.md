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
- **Measured with the rewrite** (same machine): `show` takes ~74 ms, against
  ~290 ms for 1.x, about 4× faster; ~31 ms of it is `notify-send` itself, and
  ~18 ms parsing the config. `status` takes ~39 ms. The parser returns each
  section's rule through a nameref instead of `$(...)`: a fork per section had
  cost ~30 ms.

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

- **Levels have a direction** (fixes #1). A discharging level fires only on
  battery, when the percentage drops across it; a charging level fires only on
  AC, when it rises across it. "On AC" is UPower's charging, fully-charged and
  pending-charge (held at a charge limit) states, because batteries often jump
  to "fully charged" at 100% or stop at a limit. A jump over several levels
  still fires, but only in that level's direction.
- **No commands.** 1.x could run a shell command at a level (e.g. hibernate at
  5%). Dropped: UPower's own critical action (`CriticalPowerAction` and
  `PercentageAction` in `/etc/UPower/UPower.conf`) does this more reliably, as a
  system service, even if the session is frozen. battery-notify only warns.

## Configuration

- **Fully customizable,** as in 1.x: which events notify, and each one's title,
  message, urgency and timeout.
- **One file, the XDG way:** `$XDG_CONFIG_HOME/battery-notify/config`
  (default `~/.config/battery-notify/config`). No `/etc` file: this is a
  per-user service. Without the file, built-in defaults apply (the notifications
  below); with it, the file replaces the defaults entirely (no merging). An
  example is installed at `/usr/share/doc/simple-battery-notify/config.example`.
  After editing, restart the service.
- **Format:** INI-like sections, read by a strict Bash parser; never executed as
  code, and no `jq`. A section names an event; `key = value` lines follow.

  ```
  [discharging 15]
  urgency = critical
  title = Battery low
  message = Connect the charger: {level}% left

  [charging 100]
  title = Battery full

  [plugged]
  title = Charger connected
  message = {level}% · {time} to full
  ```
- **Errors:** every command checks the config first and fails with the line
  (`battery-notify: config line 12: unknown key 'titel'`). The daemon also sends
  one critical notification about it, since it runs where nobody sees stderr.
- **1.x's JSON config is not read,** and nothing mentions it: it is simply gone.

### Events

| Event | Fires when |
|---|---|
| `discharging N` | on battery, the level drops to N% or below |
| `charging N` | on AC, the level rises to N% or above |
| `full` | UPower reports "fully charged" (works with a charge limit) |
| `plugged`, `unplugged` | the charger is connected or removed |
| `show discharging`, `show charging`, `show full` | `battery-notify show`, by state |

- An event with no section is silent. `show` with no matching section fails with
  a config error.
- Placeholders in messages: `{level}` (percentage) and `{time}` (`3:36`, or
  `unknown` while UPower is still estimating). An unknown placeholder is a
  config error.

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

## `status` and exit codes

```
state=discharging     # charging, discharging, full, empty, pending-charge, pending-discharge, unknown
percentage=58
time_to_empty=12960   # seconds; 0 when not applicable or not known yet
time_to_full=0
```

| Code | Meaning |
|---|---|
| 0 | Success (`status`: the battery could be read; the state is in the output) |
| 2 | Usage error |
| 3 | Config error |
| 4 | System error: UPower unreachable, connection lost, unexpected answer |
| 5 | No battery (e.g. a desktop) |

## Daemon behaviour

- **Start-up:** if already on battery at or below a *critical* discharging level
  (logging in at 8%), the nearest one fires once. Levels that are not critical
  stay quiet: with status levels every 10%, every login on battery would notify.
- **Several levels crossed at once** (e.g. resuming at 12% after 40%): only the
  most severe fires: the lowest for discharging, the highest for charging.
- **UPower restarts or the monitor dies:** the daemon exits 4 and systemd
  restarts it after 5 s (`Restart=on-failure`, `RestartSec=5`).
- **No battery** (exit 5), **config error** (exit 3, notified once) and usage
  errors (exit 2) are not restarted (`RestartPreventExitStatus=2 3 5`): fix the
  config, then restart the service.
- **A failed notification** is logged; the daemon keeps watching.
- **The service** is `PartOf=`, `After=` and `WantedBy=graphical-session.target`:
  it starts and stops with the desktop session (notifications need one), not
  for SSH logins. Sessions that don't activate that target (e.g. a compositor
  started without a session manager) need it started another way.
- **Measured:** ~11 MB (Bash ~4.4 MB + `gdbus monitor` ~6.9 MB), against ~20 MB
  for 1.x.

## Open

- Nothing for 2.0.
