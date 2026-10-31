# Changelog

All notable changes to Monorail by Ashforde® are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/).

## [0.9.0] - 2026-10-31

### Added
- A cheat sheet of every shortcut while you hold ⌃⌥ (or ⌃⌥⇧/).
- Redo (⌃⌥Y).
- Next and previous workspace (⌃⌥PageDown/PageUp), and moving a window there (add ⇧).
- Focus the next display (⌃⌥⇧.), move the whole workspace to the next display (⌃⌥⇧,), swap the two displays' workspaces, and move a window to the display under the pointer.
- Next window of the same app (⌃⌥\\) and swap with the window you were just on (⌃⌥⇧Tab).
- Rotate (⌃⌥⇧G) and flip (⌃⌥⇧M) a slide, sort slides by app, and widen a slide to fill the free space.
- Close or minimise a whole slide, and gather an app's windows into one slide.
- Name a slide and lock a slide, from its right-click menu.
- Tile every floating window, and Rescue Windows to bring everything back on screen.
- Solo mode (⌃⌥⇧B): hide every other app, then bring them back.
- Gaps on or off (⌃⌥⇧0), bigger and smaller gaps.
- Centre a floating window, and sizes for recordings (1280 × 720, 1920 × 1080 and more).
- New windows can open in the focused slide, or next to their app's other windows.
- Per-app home display, Never Manage This App, and remembered floating window positions.
- Settings lists the apps that need a whole slide, with a way to let one share again.
- The workspace's name as you switch, overview search and card size, window titles on slider tiles, a compact slider bar, menu bar styles (dots or workspace number), quiet mode, a soft click on slide changes, and VoiceOver announcements.
- Focus follows mouse delay, and no animations on battery.
- A "Last session" snapshot on quit and before sleep, daily settings backups with restore, Copy Diagnostics, and Insights as CSV.
- AppleScript (perform, apply layout, open pair, start template, restore snapshot, current state, window list) and a richer `monorail` command line.

## [0.8.0] - 2026-10-31

### Added
- Window hints (⌃⌥V): a letter on every window on screen; type one to go there.
- Resize mode (⌃⌥⇧E): arrows, 1–9 and 0 resize the focused slide without the mouse.
- Zoom out on the strip with ⌥ + pinch (or ⌃⌥⇧Z), live under your fingers; click a slide to go there.
- Vertical workspace swipes: workspaces slide up and down.
- Recent slides in the menu bar and the command palette.
- Remembered widths per app, a centred lone window, and the focused one of two windows growing a little.
- Projects: windows whose titles name a project gather in its workspace.
- App icons on tabs, and dragging a tab onto another slide.
- Workspace templates: apps with their files and links, started together in one slide.
- Meetings: video calls from your calendar open a minute early, optionally switching profile.
- Presentation mode (⌃⌥⇧Y) and recording the slide (⌃⌥⇧V).
- Time per workspace and app in Insights.
- Share layouts, templates and app pairs as .monorail files.
- A local API and an MCP server (`Monorail --mcp`) so AI assistants can arrange your windows.
- JavaScript plugins in the Scripts folder.
- A Raycast extension and an Alfred workflow.
- Deutsch, Français, Español and 日本語 for the menu bar menu, Settings tabs and welcome tour.
- Practice windows in the welcome tour.

## [0.7.0] - 2026-10-31

### Added
- Radial menu (⌃⌥E): point towards a side or corner, see where the window goes, let go to snap it.
- Hold ⌃⌥ and drag anywhere in a window to move it; right-drag to resize.
- Two-finger swipes on title bars: left and right move the window's slide, up makes it full width, down minimises.
- Spiral and accordion slide layouts.
- Even out widths and splits (⌃⌥⇧=), back to the last workspace (⌃⌥⇧⌫), move a window to an empty workspace (⌃⌥⇧N), go to the window that wants attention (⌃⌥⇧A), show desktop (⌃⌥⇧D), screenshot the slide (⌃⌥⇧C), and an overview of one app's windows (⌃⌥⇧O).
- A size label while resizing, a gradient focus border, and a desktop picture per workspace.
- Auto rules that run when a display is connected.
- For status bars and scripts: state.json, a distributed notification, an event script, and live reload of settings.json.
- New README tour with pictures of the overview, slider, menu bar panel, command palette, focus mode, snap picker, themes and Insights.

### Changed
- Branded as Monorail by Ashforde® in the app, menus, Settings, welcome tour, overview, installer and README.
- Animations step aside when Reduce Motion or Low Power Mode is on.

### Fixed
- Restore defaults in Settings → Shortcuts now works every time. Recording a shortcut no longer leaves Monorail's shortcuts paused if you restore defaults or close Settings before typing one. Each changed shortcut can also go back on its own, and General has Restore All Settings to Defaults.

## [0.6.0] - 2026-10-31

### Added
- Focus mode (⌃⌥B): everything but the slide you're in fades away, for 15–90 minutes or until you turn it off.
- Per-display settings: each display can have its own gaps, new-window width and slider bar.
- Smart gaps: no gaps around a lone window, wider gaps on big displays.
- Session snapshots (⌃⌥⇧S): every workspace of every profile and the apps that are open; restoring reopens the apps and puts their windows back.
- Rules by window title, like a browser window titled "Meet" floating or getting its own slide, applied even when the title changes after the window opens.
- Peek: hold ⌥ over a slide in the slider and the strip slides to show it; let go to slide back, or click to stay.
- Three-finger tap for the overview; swipe up on the slider bar to park the workspace, down to bring it back.
- Themes: Vivid, Ocean, Sunset, Forest and Monochrome for the overview, slider and workspace dots.
- Export and import settings as one file, or sync them between Macs through iCloud Drive.
- Command palette (⌃⌥/): type to go to windows and workspaces, open app pairs, park, restore snapshots, switch profiles or run any action.
- Insights: counts of switches, windows and pairings, kept on your Mac, and suggestions for app pairs you use often.
- Show a window on every workspace (⌃⌥S), like a chat or music app.
- Auto rules: switch profile or apply a layout at a time of day or when you join a Wi-Fi network.
- Picture in picture (⌃⌥I): a small live view of a window in a screen corner.
- Zoom a tile to fill its slide (⌃⌥X), and go back to the last window (⌃⌥⌫).
- Quick launch: ⌃⌥U then a letter opens an app or goes to its window.
- The menu bar can show the focused app's name.
- Automation URLs for the Shortcuts app and scripts: layouts, pairs, snapshots, profiles, workspaces, focus mode.
- Drag a slide onto another display's or workspace's strip in the overview.
- The welcome tour asks how you want to see your slides: slider bar plus menu bar icon, or the menu bar icon only.

### Changed
- The slider bar is a simple on/off switch in Settings → Appearance, with its options under it.
- The menu bar slider hangs right under its icon and closes when you click anywhere else.
- Windows that can't shrink as far as their tile get the room they need from their slide-mates; only one that needs nearly the whole slide gets a slide of its own.

### Fixed
- Shortcuts for actions added in an update now work for people upgrading, not only for new installs.

## [0.5.0] - 2026-10-30

### Added
- Snap layouts picker: drag a window towards the top of the screen and drop it on a zone.
- Swap inside a slide: drag a window over a slide-mate and they trade places live.
- Custom slide layouts, designed in Settings (columns, each split into rows).
- App pairs: save a slide's apps and open them together from the menu bar.
- Profiles: separate sets of workspaces, switched with ⌃⌥0 or the menu bar.
- Dynamic workspaces: show only the workspaces in use, plus one.
- Marks (⌃⌥⇧; then a letter, ⌃⌥; then the letter to jump back).
- Scratchpad: one floating window that drops in and hides with ⌃⌥`.
- Park a workspace's windows in the Dock and bring them back to the same slides.
- Attention markers: red dots on windows whose apps show a Dock badge.
- ⌥ + pinch opens the overview; arrow keys, return and delete work there, and a bin closes windows dropped on it.
- Live previews in window search.
- Haptic taps as the strip settles on a slide, and VoiceOver labels for window tiles.

### Changed
- Workspaces are renamed in place in the overview: the name becomes a text field right where it is; no more dialogs.
- The overview's header clears the menu bar with even spacing, and its hint sits on its own line.

### Fixed
- Apps whose windows can't shrink to half the screen (like the App Store) no longer spill off the edge or over their neighbour: Monorail notices, gives the window a slide of its own, and remembers the app for next time.
- Previews and the overview leave gaps between windows.

## [0.4.0] - 2026-10-30

### Added
- Saved layouts: save the current arrangement under a name and bring it back from the menu; windows are matched by app and title.
- Restore after restart: windows go back to their slide and workspace when apps reopen them after the Mac restarts.
- Snapping for floating windows (⌃⌥⌘ + a key): halves, thirds, two thirds, quarters, maximise, centre, and restore.
- Home workspaces per app in Settings → Apps.
- Coach tips: during the welcome tour a card at the bottom of the screen shows the next step to try and ticks along.
- Hot edges (optional): rest the pointer on a screen edge to slide.
- An update waiting shows as a dot on the menu bar icon and an "Update to …" item at the top of the menu.

### Changed
- Much faster: windows are moved and resized in the background, one lane per app, so a busy app can never slow Monorail down; window titles are cached; live previews are captured in parallel.
- Releases publish automatically when the version changes.

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
