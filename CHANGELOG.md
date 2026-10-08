# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [2.2.0] - 2026-10-08

### Changed

- `{time}` shows its units: `3h 36m` instead of `3:36`, and `estimating...`
  instead of `unknown` while UPower has no estimate yet (#2).

## [2.1.0] - 2026-09-29

### Changed

- Default configuration (applies when you have no config file):
  - "Charger connected" also shows the time to full.
  - "Battery Full" (and `show` when full) shows the percentage as its message.
  - `show` while charging is titled "Battery N%", like on battery.
  - Every discharging level (90% down to 5%) now has a charging level too,
    "Battery N%" with the time to full, always of normal urgency.

## [2.0.0] - 2026-09-29

A ground-up rewrite, from Python to Bash. **Not compatible with 1.x**: the
commands, the configuration file and its format all changed.

**After upgrading, re-enable the service** (it now belongs to the desktop
session): `systemctl --user reenable battery-notify.service`, then
`systemctl --user restart battery-notify.service`. To keep a
customized 1.x config, rewrite it in the new format; see `man battery-notify`.

### Changed

- Commands are now `show` (notify now), `status` and `daemon` (was: no
  argument, and `--daemon`).
- The configuration is `~/.config/battery-notify/config` (or under
  `$XDG_CONFIG_HOME`), in a simple `[event]` / `key = value` format; without
  it, built-in defaults apply. The JSON file and `/etc/battery-notify.json`
  are no longer read or installed.
- Placeholders are `{level}` and `{time}` (were `%LEVEL%` and `%TIME%`);
  `{time}` is h:mm, or `unknown` while UPower is estimating.
- `show` takes about 40 ms (was about 290 ms); the daemon uses about 11 MB
  (was about 20 MB).
- The service starts with the desktop session (`graphical-session.target`),
  and restarts only when a retry can help.
- A configuration mistake stops every command with its file and line (exit 3);
  the daemon also notifies it.
- Every outcome has its own exit status: 2 usage, 3 config, 4 system error,
  5 no battery.
- Dependencies: `bash`, `systemd`, `glib2`, `libnotify`, `upower`; no Python.

### Added

- Events `[charging N]` and `[full]`.
- `battery-notify status` (`key=value` lines) and `--version`.
- At daemon start-up on battery at or below a critical level, that level fires.
- Man page and bash completion.
- `Makefile` with `install` / `uninstall` (honours `PREFIX` and `DESTDIR`).
- `LICENSE` file (GPL-3.0-or-later).

### Removed

- Running commands at a level. Use UPower's own `CriticalPowerAction`
  (`/etc/UPower/UPower.conf`), which works even if the session has frozen.

### Fixed

- Low-battery warnings while charging (#1): levels now have a direction.
- When several levels are crossed at once, only the most severe fires.
- The charger notifications now also fire when the battery is full or held at
  a charge limit.

## [1.0.5] - 2026-05-22

### Changed

- Updated the default configuration.

## [1.0.4] - 2026-05-22

### Fixed

- A level is no longer missed when the battery jumps more than 1% at once.

## [1.0.3] - 2026-05-22

### Changed

- Packaging files are no longer tracked in the repository.

## [1.0.2] - 2026-05-22

### Changed

- Packaging files are no longer tracked in the repository.

## [1.0.1] - 2026-05-22

### Added

- README.

## [1.0.0] - 2026-05-22

- Initial release: a UPower D-Bus daemon and CLI, configured in JSON.
