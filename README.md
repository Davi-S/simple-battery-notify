# simple-battery-notify

Customizable battery notifications for Linux, from UPower.

`battery-notify` shows a notification when the charger is connected or
disconnected, when the battery reaches the levels you choose, when it is full,
and on demand from a keybinding. A small daemon, run by a systemd user service,
listens to UPower's D-Bus events: it reacts the moment something changes and
otherwise does nothing.

- **Levels with a direction.** Low-battery warnings only while on battery,
  charging levels only while on AC. A jump over several levels (after a suspend)
  fires only the most severe one.
- **Customizable.** Every notification's title, message, urgency and timeout,
  in a simple config file; built-in defaults without one.
- **Fast and light.** `battery-notify show` takes about 40 ms; the daemon uses
  about 11 MB. It is plain Bash.
- **Scriptable.** `battery-notify status` prints `key=value` lines, and every
  outcome has its own exit status.

## Installation

### Arch Linux (AUR)

```bash
paru -S simple-battery-notify
```

### From source

Dependencies: `bash`, `systemd`, `glib2` (for `gdbus`), `libnotify`, `upower`,
and `make` to install.

```bash
git clone https://github.com/Davi-S/simple-battery-notify.git
cd simple-battery-notify
sudo make install              # installs to /usr/local; use PREFIX=/usr to change
sudo make uninstall            # to remove
```

## Usage

Start the daemon with your desktop session:

```bash
systemctl --user enable --now battery-notify.service
```

It runs as part of `graphical-session.target`. If your session doesn't activate
that target, start `battery-notify daemon` from your compositor's autostart
instead.

Upgrading from 1.x? Re-enable the service once, since it moved to the desktop
session:

```bash
systemctl --user reenable battery-notify.service
systemctl --user restart battery-notify.service
```

Show the battery now, e.g. from a keybinding:

```bash
battery-notify show
```

Read it from a script:

```console
$ battery-notify status
state=discharging
percentage=58
time_to_empty=12960
time_to_full=0
```

### Exit status

| Code | Meaning |
|---|---|
| 0 | Success |
| 2 | Usage error |
| 3 | Configuration mistake |
| 4 | System error (UPower unreachable, connection lost) |
| 5 | No battery |

## Configuration

Copy the defaults, edit them, and restart the service:

```bash
mkdir -p ~/.config/battery-notify
cp /usr/share/doc/simple-battery-notify/config.example ~/.config/battery-notify/config
systemctl --user restart battery-notify.service
```

The file replaces the defaults entirely. Each section is an event:

```ini
[discharging 15]
urgency = critical
title = Battery low
message = Connect the charger: {level}% left

[charging 80]
title = Charged to 80%

[plugged]
title = Charger connected
message = {level}% · {time} to full
```

| Event | Fires when |
|---|---|
| `[discharging N]` | on battery, the level drops to N% or below |
| `[charging N]` | on AC, the level rises to N% or above |
| `[full]` | UPower reports "fully charged" |
| `[plugged]`, `[unplugged]` | the charger is connected or removed |
| `[show discharging]`, `[show charging]`, `[show full]` | `battery-notify show`, by state |

Keys: `title` (required), `message`, `urgency` (`low`, `normal`, `critical`)
and `timeout` (milliseconds; 2000 by default, 0 for critical: until dismissed).
Placeholders: `{level}` (percentage) and `{time}` (time left, as `3h 36m`, or
`estimating...`).

A mistake stops every command with its file and line; the daemon also shows it
as a critical notification. See `man battery-notify` for the full reference.

### Suspending when the battery is nearly empty

battery-notify only notifies. To suspend, hibernate or power off at a critical
level, use UPower's own action (`PercentageAction` and `CriticalPowerAction` in
`/etc/UPower/UPower.conf`), which works even if your session has frozen.

## Development

- `make check` runs `shellcheck` and `shfmt`, and `make test` runs the test suite
  (needs `bats`: `pacman -S bash-bats`). CI runs both on every push.
- `make integration` tests against your real UPower; run it before a release
  (`CHARGER=1` adds an unplug/replug check).
- The design and the reasons behind it are in [`docs/DESIGN.md`](docs/DESIGN.md).
- Record changes under `## [Unreleased]` in [`CHANGELOG.md`](CHANGELOG.md).
- Releases and AUR publishing are described in [`RELEASING.md`](RELEASING.md).

## License

[GPL-3.0-or-later](LICENSE)
