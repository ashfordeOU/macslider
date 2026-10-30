# Changelog

All notable changes to MacSlider are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-30

First public release.

### Added
- Scrolling strip layout with one strip per display and per Space.
- New windows open next to the focused window; existing windows keep their size.
- Keyboard focus, move, width cycling, narrower/wider, full width, centring and jump-to-column.
- Stacks, tabbed columns with a clickable tab bar, and columns pinned to the left or right edge.
- Two-finger swipe with modifier keys, and optional three- or four-finger swipe.
- Click to reveal, drag to reorder, and resize a window to set its column width.
- Automatic floating for dialogs, panels and fixed-size windows; float/tile on demand.
- Per-app rules for floating, default width and opening position.
- Focus border, inactive-window dimming, focus follows mouse and mouse follows focus.
- Window search (⌃⌥Space) and a menu bar indicator with the windows on the current strip.
- Settings window with rebindable shortcuts, a one-step modifier prefix switch, and Mac setup checks.
- Welcome tour, launch at login, `macslider://` URL scheme and a `macslider` command-line tool.
- Windows are put back on screen when MacSlider pauses or quits; layouts are restored on relaunch.
