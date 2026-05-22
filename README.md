# simple-battery-notify

A lightweight, customizable, and instantly-reacting battery notification daemon
and CLI tool for Linux.

Unlike traditional battery monitors that aggressively poll `acpi` on a timer,
`simple-battery-notify` is a pure event-driven daemon. It listens directly to
the system D-Bus for UPower hardware events. This means it consumes virtually
zero CPU cycles while idling and reacts to charger connections and percentage
changes the exact millisecond they happen.

## Features

- **Event-Driven:** Instantly triggers on AC plug/unplug events and percentage
  changes via UPower D-Bus signals.
- **Highly Customizable:** Define your own percentage thresholds, notification
  urgencies, and custom text.
- **Action Execution:** Automatically run arbitrary shell commands when specific
  battery levels are hit (e.g., automatically running `systemctl suspend` at
  5%).
- **CLI Mode:** Can be run manually or bound to a keyboard shortcut to instantly
  display the current battery status.
- **JSON Configuration:** Easy to read and manage configuration files.

## Dependencies

- `python`
- `python-gobject`
- `python-pydbus`
- `upower` (for battery D-Bus events)
- `libnotify` (provides `notify-send`)

## Installation

### Arch Linux (AUR)

The package is available in the Arch User Repository (AUR). You can install it
using your preferred AUR helper (such as `yay` or `paru`):

```bash
paru -S simple-battery-notify
```

## Usage

### 1. The Background Daemon

Because this tool interacts with your desktop notifications, it runs as a
**systemd user service**.

Enable and start the daemon so it runs in the background automatically:

```bash
systemctl --user enable --now battery-notify.service
```

If you make changes to your configuration file, restart the service to apply
them:

```bash
systemctl --user restart battery-notify.service
```

### 2. The CLI Tool

You can manually trigger a notification detailing your current battery status by
running the command directly in your terminal. This is highly useful for binding
to a custom keyboard shortcut in your window manager or desktop environment.

```bash
battery-notify
```

## Configuration

The default configuration file is installed at `/etc/battery-notify.json`. To
customize your settings, copy it to your local user directory:

```bash
mkdir -p ~/.config/battery-notify
cp /etc/battery-notify.json ~/.config/battery-notify/config.json

```

### Configuration Structure

The JSON configuration allows you to set a default notification timeout and an
array of `levels`.

```json
{
  "timeout": 2000,
  "levels": [
    {
      "trigger": "plugged",
      "urgency": "normal",
      "title": "Charger Connected",
      "message": "Running on AC power. Current level: %LEVEL%%.",
      "command": ""
    },
    {
      "trigger": "cli-discharging",
      "urgency": "normal",
      "title": "Battery Status",
      "message": "Battery is at %LEVEL%% (%TIME% remaining).",
      "command": ""
    },
    {
      "trigger": 15,
      "urgency": "critical",
      "title": "Battery Critical",
      "message": "Connect the charger! Only %LEVEL%% remaining.",
      "command": ""
    },
    {
      "trigger": 5,
      "urgency": "critical",
      "title": "System Suspend",
      "message": "Battery at %LEVEL%%! Suspending to prevent data loss.",
      "command": "systemctl suspend"
    }
  ]
}
```

### Trigger Types

The `trigger` key determines when a specific rule is fired. It accepts the
following values:

- **Integers (`100`, `30`, `5`, etc.):** Triggers when the battery drops or
  charges to this exact percentage.
- **`"plugged"`:** Triggers instantly when the AC adapter is connected.
- **`"unplugged"`:** Triggers instantly when the AC adapter is disconnected.
- **`"cli-charging"`:** Triggers when the `battery-notify` command is run
  manually and the device is plugged in.
- **`"cli-discharging"`:** Triggers when the `battery-notify` command is run
  manually and the device is on battery power.

### Variables

You can use the following variables inside your `message` strings. They will be
dynamically replaced when the notification fires:

- `%LEVEL%`: The current battery percentage.
- `%TIME%`: The estimated time remaining (e.g., `01:25:00`). If charging, this
  displays the time until full. If discharging, it displays the time until
  empty.

