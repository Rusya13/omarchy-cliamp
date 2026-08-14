# Omarchy Cliamp Bar Widget

A small Omarchy top-bar widget for [cliamp](https://github.com/bjarneo/cliamp).
It shows the live now-playing title, a compact equalizer, station selection,
play/pause, volume, station navigation, and cliamp EQ sound-mode controls.

## Requirements

- Omarchy shell with third-party plugin support
- `cliamp` running in another terminal or as a daemon
- Python 3 (used for cliamp queue IPC)

## Install

```bash
omarchy plugin add https://github.com/Rusya13/omarchy-cliamp.git --enable --yes
omarchy bar move rus.cliamp --section right
```

The widget is hidden automatically when cliamp is not running. Existing
`shell.json` layout entries are preserved by Omarchy; this repository does not
include a machine-specific shell configuration.

## Controls

- Left-click: play/pause
- Right-click: open the station popup
- Middle-click / scroll: previous or next station
- Popup: station list, previous/play/next, volume, EQ sound-mode cycling, and Open in Pi
- Open in Pi: moves/focuses the running cliamp Herdr pane into the Pi workspace,
  or creates a new cliamp tab in the Pi window

Colors follow the active Omarchy theme dynamically.
