# Changelog

All notable changes to MacSlider are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/).

## [0.2.1] - 2026-10-30

### Added
- A new app icon, and a matching menu bar icon.

### Fixed
- Clicking an app in the Dock no longer rearranges the strip: hidden, minimised and reopened windows, and relaunched apps, return to exactly where they were.
- New windows no longer get paired with another app's window as they open; lone windows pair up only when you regroup (⌃⌥A), unless you turn pairing on in Settings.

## [0.2.0] - 2026-10-30

Slides, overview and workspaces, and much easier to drive with or without the keyboard.

### Added
- Slides grouped by app: same-app windows share a full-screen slide (four per slide for terminals), single-window apps pair up.
- Slide layouts: grid (2×2, 3×2, 3×3), columns, rows, main + side and main + bottom, with up to nine windows per slide.
- Resize the main window (⌃⌥. / ⌃⌥,) and make any window the main one (⌃⌥M); per-app slide layouts.
- Right-to-left strip direction, mirroring layout, keys, swipes, the slider bar and the overview.
- Click the menu bar icon for a slider popover with slide cards; right-click for the menu.
- Slider bar: a mini-map of the strip that glides in while you move; drag it to slide, click a slide to jump.
- Overview (⌃⌥O): every slide of every workspace at once; click to jump, drag to group or reorder.
- Workspaces: up to nine per display, ⌃⌥1–9 to switch, ⌃⌥⇧1–9 to move a window.
- Stack into the right column (⌃⌥]) and pop out of a stack to either side (⌃⌥⇧[ / ⌃⌥⇧]).
- Per-app windows-per-slide setting.
- Full shortcut list in the menu bar, and a practice pad in the welcome tour.
- Optional daily update check, and Check for Updates… in the menu bar.
- Slide mode: tap the right ⌥ key, then use plain keys (← → to slide, ⇧← ⇧→ to move, R, F, C, 1–9 …). A cheat sheet shows while it is on.
- Mouse wheel support: hold ⌥ and scroll to move one window per notch.
- Scroll over the menu bar to move the strip, no keys needed.
- ‹ › buttons in the menu bar to step between windows.
- Settings for the slide mode key, the scroll modifier, menu bar scrolling and the ‹ › buttons.

### Changed
- Scrolling the strip now uses ⌥ alone instead of ⌃⌥ (configurable).
- ⌃⌥1–9 now switch workspaces. Jumping to a slide by number moved to slide mode (1–9) and can be bound in Settings.
- ⌃⌥] now stacks into the right column; unstacking moved to ⌃⌥⇧].
- The welcome tour teaches slide mode and mouse scrolling first.

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
