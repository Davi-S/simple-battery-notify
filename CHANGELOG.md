# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `battery-notify --version`.
- Man page and bash completion.
- `Makefile` with `install` / `uninstall` (honours `PREFIX`, `SYSCONFDIR` and
  `DESTDIR`); the user service points at the installed program.
- `LICENSE` file (GPL-3.0-or-later).

### Fixed

- Package upgrades no longer overwrite local edits to `/etc/battery-notify.json`.

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
