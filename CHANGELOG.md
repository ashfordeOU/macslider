# Changelog

All notable changes to MacSlider are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/).

## [0.3.1] - 2026-10-30

### Added
- A proper installer: the disk image opens to Monorail beside your Applications folder, over a background that shows you to drag it across.
- A new README with an animated banner, a how-it-works diagram, a guide to slide layouts, a comparison and an FAQ.

### Changed
- Links point to the repository's new home, github.com/ashfordeOU/monorail.

### Fixed
- Clicking a slide on the slider bar always jumps to it, even if the pointer moves a little while clicking. Clicking one half of a pair (or one cell of a grid) jumps straight to that window.

## [0.3.0] - 2026-10-30

### Changed
- MacSlider is now **Monorail**. The app, its menus, downloads, the `monorail` command-line tool and `monorail://` links all use the new name; old `macslider://` links keep working.
- Windows dragged into a single-window slide now follow your slide layout (side by side by default) instead of stacking. Right-click a window, or a slide's handle in the overview, for Slide Layout: side by side, up and down, grid, main + side, main + bottom or tabs.
- The app icon fills macOS's icon shape exactly, so newer macOS shows it full size instead of on a grey plate.
- Built with the newest Xcode available.
- Updating keeps everything: the app's identity and signature are unchanged, so Accessibility and Screen Recording stay granted, and settings and layouts move over automatically. The app is installed as Monorail.app on update.

### Fixed
- Menu bar menu commands (Reset to Smart Pairs, Undo Layout Change and the rest) now always run: the menu opens in a way that delivers the chosen item reliably.
- Reset to smart pairs and Undo confirm what they did with a short message.

## [0.2.5] - 2026-10-30

### Fixed
- File pickers, save panels and other dialogs are no longer tiled into slides. They float, centred over the window that opened them, and the strip doesn't scroll away when one opens.

## [0.2.4] - 2026-10-30

### Added
- Window controls in previews and the overview: close, minimise and full-screen buttons on every window tile.
- Right-click a window tile to rename it (MacSlider shows your name everywhere), give it its own slide, or move it to another workspace.
- Workspace names: set them in Settings, or right-click a dot on the slider bar or a workspace in the overview. Hovering a dot shows its name.
- A colourful overview: gradient backdrop with soft glows and a dot pattern, and a coloured card per workspace.
- New app icon (the "offset M") and a matching menu bar icon.

## [0.2.3] - 2026-10-30

### Fixed
- Live previews now use ScreenCaptureKit on macOS 14 and later, so window images show on current macOS versions.
- After allowing Screen Recording, MacSlider offers to relaunch itself, which macOS needs before the permission applies.

## [0.2.2] - 2026-10-30

### Added
- Resize assist: resizing a window in a slide resizes its neighbours live, then offers Keep, Own slide, Move others out or Undo.
- Undo (⌃⌥Z): step back through recent layout changes.
- Live previews: hover a slide on the slider bar to see its windows live, and click one to jump to it. Scrolling over the bar slides the strip.
- One-click updates: MacSlider downloads, verifies (checksum and code signature), installs and relaunches itself. Optional fully automatic installs, and an Update button in the menu bar slider.

### Fixed
- The overview now sits on a frosted, blurred backdrop, so windows behind it no longer show through the text.

### Changed
- Releases are signed with MacSlider's own certificate, so macOS keeps the Accessibility permission across updates. Updating from an earlier version needs one last re-grant.

## [0.2.1] - 2026-10-30

### Added
- A new app icon, and a matching menu bar icon.
- Your own pairings stick: slides you arrange by hand are kept as they are and saved, until you reset.
- Reset to smart pairs (⌃⌥A, the menu, the menu bar slider or the overview) regroups every workspace by app in one step.
- Layouts stay put: when an app resizes or moves its own window (as Firefox sometimes does), MacSlider snaps it back.

### Changed
- A slide holds at most six windows; a seventh gets a slide of its own.

### Fixed
- Clicking an app in the Dock no longer rearranges the strip: hidden, minimised and reopened windows, and relaunched apps, return to exactly where they were.
- New windows no longer get paired with another app's window as they open; lone windows pair up only when you regroup (⌃⌥A), unless you turn pairing on in Settings.

## [0.2.0] - 2026-10-30

Slides, overview and workspaces, and much easier to drive with or without the keyboard.

### Added
- Slides grouped by app: same-app windows share a full-screen slide (four per slide for terminals), single-window apps pair up.
- Slide layouts: grid (2×2, 3×2), columns, rows, main + side and main + bottom.
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
