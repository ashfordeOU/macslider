<div align="center">

<img src="assets/icon.png" width="160" alt="MacSlider icon">

# MacSlider

**A scrolling window manager for macOS.**
Every window sits side by side on one endless strip. Nothing shrinks, nothing overlaps.

[Download](https://github.com/ashfordeOU/macslider/releases/latest) ·
[Shortcuts](#keyboard-shortcuts) ·
[Build from source](#build-from-source) ·
[License](#license)

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Universal](https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-blue)
![License: AGPL v3](https://img.shields.io/badge/license-AGPL--3.0-green)
[![CI](https://github.com/ashfordeOU/macslider/actions/workflows/ci.yml/badge.svg)](https://github.com/ashfordeOU/macslider/actions/workflows/ci.yml)

</div>

---

Grid tilers squeeze every new window into the space that's already there.
MacSlider does the opposite: each window is a column on a horizontal strip that
runs past the edges of your display. Open a window and it slides in next to the
one you're using. Everything else keeps its size. Move focus and the strip
glides just far enough to bring the window into view.

## Highlights

- **One endless strip per display.** Each display, and each Space on it, has its own strip with its own focus and scroll position.
- **Slides grouped by app.** Two Safari windows share a full-screen slide side by side; terminals tile four to a slide (2×2). Apps with one window pair up with another, so no space is wasted.
- **Slider in the menu bar.** Click the menu bar icon for the slider and your slides as cards; right-click for the full menu.
- **Slider bar.** A glass mini-map of the whole strip glides in while you move: every slide as a tile with its app icons, and a frame showing what's on screen. Drag it to slide every window along, click a tile to jump.
- **Overview.** One key (<kbd>⌃⌥O</kbd>) shows every slide in every workspace, laid out in order. Click to jump there, drag windows between slides, drag slides to reorder.
- **Workspaces.** Up to nine per display. <kbd>⌃⌥1</kbd>–<kbd>⌃⌥9</kbd> switches; add <kbd>⇧</kbd> to take the window with you.
- **Slide mode: no chords to remember.** Tap the right ⌥ key, then press ← → to slide between windows. R sets the width, F fills the screen, Esc finishes.
- **Scroll with your mouse.** Hold ⌥ and turn the wheel: each notch moves one window. Or just scroll over the menu bar, or click the ‹ › buttons next to the menu bar icon.
- **Trackpad native.** Hold ⌥ and swipe two fingers, or turn on a plain three- or four-finger swipe. The strip follows your fingers and settles on the nearest window.
- **Shortcuts too.** Focus, move, resize and arrange with Control-Option plus the arrow keys or H J K L. Every shortcut can be rebound.
- **Slide layouts.** Up to six windows per slide as a grid (2×2, 3×2), columns, rows, main + side, main + bottom, or tabs. Resize the main window, make any window the main one, and set a layout per app.
- **Either direction.** Run the strip left to right, or right to left with everything mirrored.
- **Pinned columns.** Keep a column at the left or right edge while the rest of the strip scrolls.
- **Smart floating.** Dialogs, panels and fixed-size windows float automatically. Per-app rules float apps or give them a default width and position.
- **Safe by design.** Pause, quit or log out and every window is put back fully on screen. The layout is restored when MacSlider restarts.
- **Native and private.** Written in Swift with AppKit and SwiftUI. No account, no telemetry. The only permission is Accessibility; the only network request is an optional daily update check.

## Install

### Download

1. Download **MacSlider.dmg** from the [latest release](https://github.com/ashfordeOU/macslider/releases/latest).
2. Open it and drag **MacSlider** to **Applications**.
3. Open MacSlider and allow **Accessibility** access when asked.

> [!NOTE]
> Release builds are not yet notarized by Apple. The first time you open MacSlider,
> macOS may say it can't verify the developer. Open **System Settings → Privacy & Security**
> and click **Open Anyway**. The Terminal installer below avoids this step.

### Terminal

```bash
curl -fsSL https://raw.githubusercontent.com/ashfordeOU/macslider/main/scripts/install.sh | bash
```

This downloads the latest release, installs it in `/Applications` and opens it.

### Requirements

- macOS 13 Ventura or later
- Apple silicon or Intel (universal binary)
- A trackpad, only if you want swipe gestures

## Getting started

When MacSlider first opens, a short welcome tour walks you through granting
Accessibility access and the easiest ways to get around.

### Slide mode

Tap the **right ⌥ Option** key on its own. A small cheat sheet appears at
the bottom of the screen, and until you press <kbd>Esc</kbd> (or pause for a
few seconds) plain keys drive MacSlider:

| Key | What it does |
| --- | --- |
| <kbd>←</kbd> <kbd>→</kbd> | Slide to the previous / next window. |
| <kbd>⇧←</kbd> <kbd>⇧→</kbd> | Move the window along the strip. |
| <kbd>↑</kbd> <kbd>↓</kbd> | Move between windows stacked in a column (add <kbd>⇧</kbd> to reorder). |
| <kbd>R</kbd> | Step through preset widths (¼ ⅓ ½ ⅔ ¾). |
| <kbd>F</kbd> | Fill the screen. Press again to go back. |
| <kbd>C</kbd> | Centre the window. |
| <kbd>1</kbd>–<kbd>9</kbd> | Jump to a column. |
| <kbd>-</kbd> <kbd>=</kbd> | Narrower / wider. |
| <kbd>[</kbd> <kbd>]</kbd> | Stack into the left column / unstack. |
| <kbd>T</kbd> <kbd>W</kbd> <kbd>P</kbd> <kbd>D</kbd> | Float, tabs, pin, send to the next display. |
| <kbd>Esc</kbd> <kbd>Return</kbd> | Done. Any other key also ends slide mode and goes to your app. |

The trigger key can be right ⌥, ⌘, ⌃ or ⇧ in **Settings → Motion & Input**.
Holding the key as a normal modifier never turns slide mode on, only a tap does.

### Slides and the overview

With **Group windows into slides by app** on (the default), MacSlider fills
the strip with full-screen slides:

- Windows of the same app share a slide: two side by side, or four in a 2×2 grid for terminals (Terminal, iTerm, Ghostty, Warp, kitty, Alacritty, WezTerm).
- A new window of an app that's not on the strip yet gets a slide of its own. Pressing <kbd>⌃⌥A</kbd> pairs lone windows of different apps (or turn on pairing as they open in **Settings → Layout**).
- Open a second window of an app that is sharing a slide, and the two windows move to a slide of their own.
- Windows that come back return to exactly where they were: unhidden, unminimised, reopened from the Dock after closing, or after quitting and relaunching the app.

**Layouts stay put.** Some apps (Firefox, for one) occasionally resize or
move their own windows. MacSlider notices that it wasn't you — no mouse button
was down — and snaps the window straight back. Dragging and resizing by hand
still work as before. Turn this off in **Settings → Layout** if you prefer.

**Your own pairings stick.** Pair windows yourself (say one Safari and one
Finder window) by dragging in the overview or with <kbd>⌃⌥[</kbd> / <kbd>⌃⌥]</kbd>,
and MacSlider keeps that slide as you made it: new windows won't break it up
or squeeze into it, and it's saved across MacSlider restarts. To go back,
**Reset to smart pairs** (<kbd>⌃⌥A</kbd>, the ✨ button in the menu bar slider,
or the overview) regroups every workspace by app in one step.

Change the tiles per slide (up to six — more gets too crowded) and the layout for any app under **Settings → Apps**.

### Slide layouts

<kbd>⌃⌥G</kbd> (or <kbd>G</kbd> in slide mode) cycles the focused slide through:

| Layout | Arrangement |
| --- | --- |
| Grid | Grows with the count: 2 side by side, 2×2, 3×2. A short last row stretches to fill. |
| Columns | All side by side, full height. |
| Main + side | One large window, the rest stacked beside it. |
| Main + bottom | One large window on top, the rest in a row below. |
| Rows | All stacked, full width. |

<kbd>⌃⌥.</kbd> and <kbd>⌃⌥,</kbd> make the main window larger or smaller;
<kbd>⌃⌥M</kbd> makes the focused window the main one. <kbd>⌃⌥W</kbd> turns a
slide into tabs. Arrow keys move between tiles by where they are on screen, then
on to the next slide. Choose the layout for new slides in **Settings → Layout**.

### Right to left

Set **Strip direction** to **Right to left** in **Settings → Layout** and the
first slide sits at the right edge, new windows open to its left, and keys,
swipes, the slider bar and the overview all follow.

Press <kbd>⌃⌥O</kbd> (or <kbd>O</kbd> in slide mode, or **Overview** in the
menu bar) to see every slide of every workspace at once:

- **Click** a window to jump to it, or a workspace title to switch to it.
- **Drag a window** onto another slide to group it there, or into the gap between slides to give it a column of its own. It can go to another workspace too.
- **Drag a slide** by its ≡ handle to reorder the strip.
- Turn on **Show live previews** to see window contents. This needs Screen Recording permission; without it you see app icons and titles.

### Slider bar

**Click the MacSlider icon** in the menu bar for the slider, every slide as a
card, and pause, overview and settings buttons. Right-click (or ⌃-click) the
icon for the full menu.

While the strip moves, a slider bar fades in at the bottom of the screen:
every slide in the workspace as a small tile with its apps' icons, and a
highlighted frame for the part that's on screen.

- **Drag** the frame, or anywhere on the bar, and all your windows slide along with it.
- **Click** a tile to jump to that slide.
- **Dots** on the left switch workspaces; the grid button on the right opens the overview.

In **Settings → Appearance** you can keep it on screen all the time (windows
then leave room for it), move it to the top, or turn it off.

### Workspaces

Each display has four workspaces by default (up to nine in **Settings → General**).
<kbd>⌃⌥1</kbd>–<kbd>⌃⌥9</kbd> switches workspace, and <kbd>⌃⌥⇧1</kbd>–<kbd>⌃⌥⇧9</kbd>
moves the focused window to one. The menu bar shows where you are (`2 · 3/5` is
workspace 2, slide 3 of 5). Switching to a window with ⌘Tab takes you to its workspace.

### With the mouse

- Hold <kbd>⌥</kbd> and **scroll**. With a mouse wheel each notch moves one window; on a trackpad the strip follows your fingers.
- **Scroll over the menu bar**. No keys needed.
- **Click ‹ ›** next to the MacSlider icon in the menu bar.
- **Click** any window, even the thin edge of one off-screen, and the strip scrolls to show it.

The menu bar icon shows where you are (`3/8`), lists the windows on the
current strip, and has Pause, Search Windows, Retile and Settings.

## Keyboard shortcuts

If you prefer chords to slide mode, all shortcuts start with <kbd>⌃⌥</kbd> by default. In **Settings → Shortcuts**
you can switch the prefix to <kbd>⌥</kbd>, <kbd>⌘⌥</kbd> or <kbd>⌃⌘</kbd> in
one step, rebind any action and give an action more than one shortcut.
Shortcuts are stored by physical key, so they stay on the same keys with
AZERTY, QWERTZ, Dvorak and other layouts.

| Action | Shortcut |
| --- | --- |
| Focus left / right | <kbd>⌃⌥H</kbd> <kbd>⌃⌥L</kbd> · <kbd>⌃⌥←</kbd> <kbd>⌃⌥→</kbd> |
| Focus up / down in a stack | <kbd>⌃⌥K</kbd> <kbd>⌃⌥J</kbd> · <kbd>⌃⌥↑</kbd> <kbd>⌃⌥↓</kbd> |
| Focus first / last column | <kbd>⌃⌥Home</kbd> <kbd>⌃⌥End</kbd> |
| Overview | <kbd>⌃⌥O</kbd> · <kbd>⌃⌥Tab</kbd> |
| Search windows | <kbd>⌃⌥Space</kbd> |
| Switch to workspace 1–9 | <kbd>⌃⌥1</kbd> … <kbd>⌃⌥9</kbd> |
| Move window to workspace 1–9 | <kbd>⌃⌥⇧1</kbd> … <kbd>⌃⌥⇧9</kbd> |
| Move column left / right | <kbd>⌃⌥⇧H</kbd> <kbd>⌃⌥⇧L</kbd> · <kbd>⌃⌥⇧←</kbd> <kbd>⌃⌥⇧→</kbd> |
| Move window up / down in a stack | <kbd>⌃⌥⇧K</kbd> <kbd>⌃⌥⇧J</kbd> · <kbd>⌃⌥⇧↑</kbd> <kbd>⌃⌥⇧↓</kbd> |
| Send window to next display | <kbd>⌃⌥D</kbd> · <kbd>⌃⌥N</kbd> |
| Cycle width forward / backward | <kbd>⌃⌥R</kbd> <kbd>⌃⌥⇧R</kbd> |
| Narrower / wider | <kbd>⌃⌥-</kbd> <kbd>⌃⌥=</kbd> |
| Full width on / off | <kbd>⌃⌥F</kbd> |
| Centre column | <kbd>⌃⌥C</kbd> |
| macOS full screen | <kbd>⌃⌥⇧F</kbd> |
| Reset to smart pairs (regroup by app) | <kbd>⌃⌥A</kbd> |
| Stack into the column on the left / right | <kbd>⌃⌥[</kbd> <kbd>⌃⌥]</kbd> |
| Pop out of a stack to the left / right | <kbd>⌃⌥⇧[</kbd> <kbd>⌃⌥⇧]</kbd> |
| Next slide layout | <kbd>⌃⌥G</kbd> |
| Main window larger / smaller | <kbd>⌃⌥.</kbd> <kbd>⌃⌥,</kbd> |
| Make main window | <kbd>⌃⌥M</kbd> |
| Tabbed column on / off | <kbd>⌃⌥W</kbd> · <kbd>⌃⌥⇧T</kbd> |
| Pin column to left / right edge | <kbd>⌃⌥P</kbd> <kbd>⌃⌥⇧P</kbd> |
| Float / tile window | <kbd>⌃⌥T</kbd> |
| Retile everything | <kbd>⌃⌥Esc</kbd> |
| Pause / resume | <kbd>⌃⌥Q</kbd> |

Jumping to a slide by number is <kbd>1</kbd>–<kbd>9</kbd> in slide mode, and
can be bound to any keys in Settings. Every shortcut is also listed under
**Keyboard Shortcuts** in the menu bar, where choosing one runs it.

## Mouse and trackpad

- **Click** any window, including the thin edge of one parked off-screen, and the strip scrolls to show it.
- **Drag** a window by its title bar onto another column to reorder the strip. Dragging a window out of a stack unstacks it.
- **Resize** a window's edge to change its column's width.
- **Scroll** while holding <kbd>⌥</kbd> (you can choose ⌘, ⌃ or ⌃⌥ instead), or with no keys over the menu bar. A mouse wheel moves one window per notch; a trackpad or Magic Mouse moves the strip with your fingers.
- **‹ › buttons** next to the menu bar icon step one window at a time.
- **Swipe** with three or four fingers, no keys, once you turn it on in **Settings → Motion & Input**. If macOS uses the same finger count to switch Spaces, **Settings → General → Mac setup** shows you where to change it.
- **Focus follows mouse** and **mouse follows focus** are optional and off by default.

## Settings

Everything is set in a standard Settings window, and changes apply immediately.

| Pane | What you can change |
| --- | --- |
| General | Launch at login, pause, what clicking the menu bar icon does, workspaces per display, update checks, menu bar position indicator, where new windows open, Mac setup checks |
| Layout | Strip direction, grouping into slides by app, windows per slide, slide layout, gaps between windows and at screen edges (down to zero), default width, width presets, centring behaviour, keep each window's own height, tab bar height |
| Motion & Input | Slide mode key, scroll modifier, menu bar scrolling, ‹ › buttons, three/four-finger swipe, sensitivity, direction, animation speed, focus follows mouse, mouse follows focus |
| Appearance | Slider bar (while sliding, always or never; top or bottom), focus border with colour and width, dimming of inactive windows |
| Apps | Per-app rules: always float, windows per slide, slide layout, default width, open at the start, next to focus or at the end |
| Shortcuts | Modifier prefix, every binding, extra bindings, restore defaults |

Settings are saved to `~/Library/Application Support/MacSlider/settings.json`,
and the strip layout to `layout.json` in the same folder.

**Mac setup** checks for Accessibility access, other window managers that
might move windows too (Rectangle, Magnet, Amethyst, AeroSpace, yabai and
others), Stage Manager, “Displays have separate Spaces” and conflicting
trackpad gestures. Each check links to the right System Settings pane.

## Automation

Every action has a `macslider://` URL, so you can drive MacSlider from
Raycast, Alfred, Shortcuts, Keyboard Maestro or a shell script:

```bash
open -g macslider://focus-right
```

The app also includes a small command-line tool. Link it onto your `PATH`:

```bash
sudo ln -sf /Applications/MacSlider.app/Contents/Resources/macslider /usr/local/bin/macslider
```

Then run any action:

```bash
macslider cycle-width
```

Run `macslider --help` for the full list of actions. `settings` and `welcome`
open those windows.

## How it works

MacSlider lays out each strip as a row of columns in its own coordinate
space and maps the visible part onto the display. macOS won't put a window
entirely off-screen, so columns that scroll out of view are **parked** at the
display edge with a few points showing. Click a parked window and it slides
back into view.

The layout model (`Sources/MacSliderCore`) is plain Swift with no AppKit
code, so it is unit-tested on macOS and Linux. The app
(`Sources/MacSlider`) applies that model to real windows:

- **Accessibility (`AXUIElement`, `AXObserver`)** moves and resizes windows and follows window creation, focus, minimising and closing.
- **A `CGEventTap`** handles global shortcuts, slide mode and strip scrolling, and passes every other event straight through.
- **Mission Control Spaces** are read through the system window server, so each Space keeps its own layout. If that lookup ever fails, MacSlider treats each display as one Space instead of breaking.
- **Multitouch input** is read directly from the trackpad for three- and four-finger swipes. It is only loaded when that option is on.
- **Animations** use a short ease-out curve. Windows are resized once, then slid into place, so apps don't have to re-layout their content on every frame.

## Privacy

MacSlider needs one permission, **Accessibility**, which macOS requires
before any app can move other apps' windows. You can revoke it at any time in
**System Settings → Privacy & Security → Accessibility**.

Live previews in the overview are optional and need **Screen Recording**
permission. Previews are drawn on your Mac and never stored or sent anywhere.

MacSlider has no account, analytics or telemetry. Its only network request is
a daily check of this repository's latest release, which you can turn off in
**Settings → General**.

## Build from source

You need Xcode 15 or later (or the matching Swift toolchain) on macOS 13 or later.

```bash
git clone https://github.com/ashfordeOU/macslider.git
cd macslider
make test      # run the unit tests
make app       # build dist/MacSlider.app (universal, ad-hoc signed)
make package   # also build the .zip, .dmg and SHA256SUMS
make run       # build and open the app
```

### Signing

macOS ties the Accessibility permission to the app's code signature. Release
builds are signed with MacSlider's own certificate, so the permission carries
over from one version to the next. (Updating from a release before 0.2.2 needs
one last re-grant: remove MacSlider from **Privacy & Security → Accessibility**
with **–**, then open it again.)

The certificate is self-signed and lives in two repository secrets,
`MACSLIDER_SIGNING_CERT` and `MACSLIDER_SIGNING_PASSWORD`. To create or replace
it, run this on your Mac. It uses the GitHub CLI if it's installed, and
otherwise walks you through pasting the two secrets:

```bash
scripts/make-signing-cert.sh
```

Local builds are signed ad hoc unless you set `SIGN_IDENTITY` to a code-signing
identity (a name or SHA-1 hash, such as a Developer ID) before running
`scripts/build-app.sh`. After installing an ad-hoc build, switch MacSlider off
and on in **Privacy & Security → Accessibility**.

### Project layout

```
Sources/MacSliderCore/   Layout model: strips, columns, widths, scrolling, keymap, settings
Sources/MacSlider/       macOS app: engine, input, overlays, menu bar, settings UI
Tests/                   Unit tests for the layout model
Resources/Info.plist     App bundle metadata
assets/icon.png          App icon master (rendered by scripts/render-icon.py)
scripts/                 Build, package, install, icon and command-line tools
.github/workflows/       CI, plus release builds on version tags
```

## Troubleshooting

- **Shortcuts do nothing.** Check that MacSlider is enabled in **Privacy & Security → Accessibility**. Then use **Settings → General → Check again**.
- **A window won't tile.** Some apps have fixed-size windows, or open panels instead of standard windows. These float on purpose. Press <kbd>⌃⌥T</kbd> to tile one anyway.
- **Windows jumped around after a display change.** Press <kbd>⌃⌥Esc</kbd> to retile.
- **Everything's in a mess.** Pause with <kbd>⌃⌥Q</kbd>. Every window comes back on screen, and you can move them by hand.

## Contributing

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Copyright © 2026 Ashforde OÜ.

MacSlider is free software: you can redistribute it and/or modify it under the
terms of the [GNU Affero General Public License v3.0](LICENSE) as published by
the Free Software Foundation.
