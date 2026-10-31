#if os(macOS)
import AppKit
import MonorailCore
import os

let log = Logger(subsystem: "org.ashforde.macslider", category: "engine")

/// One display on one Mission Control Space.
struct ScreenKey: Hashable, Codable {
    var display: String
    var space: UInt64
}

/// A strip lives on one display, one Mission Control Space and one
/// Monorail workspace (0-based).
struct StripKey: Hashable, Codable {
    var display: String
    var space: UInt64
    var workspace: Int

    init(screen: ScreenKey, workspace: Int) {
        display = screen.display
        space = screen.space
        self.workspace = workspace
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        display = try c.decode(String.self, forKey: .display)
        space = try c.decode(UInt64.self, forKey: .space)
        workspace = try c.decodeIfPresent(Int.self, forKey: .workspace) ?? 0
    }

    var screen: ScreenKey { ScreenKey(display: display, space: space) }
}

/// A window Monorail knows about: tiled on a strip (`key` set) or floating.
final class ManagedWindow {
    let id: WindowID
    let pid: pid_t
    let element: AXUIElement
    let bundleID: String?
    let appName: String
    /// The frame the window had before Monorail first touched it.
    let home: CGRect
    /// The last frame Monorail applied, to skip redundant moves and to tell
    /// the user's own moves apart from ours.
    var lastApplied: Rect?
    /// When Monorail last moved this window, to tell our moves from the user's.
    var appliedAt: CFTimeInterval = 0
    /// The strip the window is tiled on, or nil when it floats.
    var key: StripKey?

    init(id: WindowID, pid: pid_t, element: AXUIElement, bundleID: String?, appName: String, home: CGRect) {
        self.id = id
        self.pid = pid
        self.element = element
        self.bundleID = bundleID
        self.appName = appName
        self.home = home
    }

    /// Cached; refreshed when the window reports a title change, so building
    /// menus and the overview never waits on a busy app.
    lazy var title: String = element.title ?? ""
}

/// Owns the strips and keeps real windows in line with them.
///
/// Everything runs on the main thread. Accessibility calls are bounded by a
/// global messaging timeout so an unresponsive app cannot stall the engine
/// for long.
final class Engine {
    var settings: AppSettings {
        didSet { settingsDidChange(from: oldValue) }
    }

    private(set) var isPaused = false
    private(set) var isRunning = false

    /// Called whenever something the menu bar shows may have changed.
    var onStateChange: () -> Void = {}
    /// Called for the "Search windows" action.
    var onShowSwitcher: () -> Void = {}
    /// Called for the "Overview" action.
    var onShowOverview: () -> Void = {}
    /// Called for the command palette and "Take a snapshot" actions.
    var onShowPalette: () -> Void = {}
    /// Called to float a live picture of a window in a corner.
    var onPictureInPicture: (WindowID) -> Void = { _ in }
    /// Called for the radial menu and the overview of one app's windows.
    var onRadialMenu: () -> Void = {}
    var onShowAppOverview: (String) -> Void = { _ in }
    /// While resizing by hand: the window's frame (Accessibility coordinates), or nil when done.
    var onResizeHUD: (CGRect?) -> Void = { _ in }
    /// Window hints, resize mode and the strip zoom are drawn by the app.
    var onWindowHints: () -> Void = {}
    var onResizeMode: (Bool) -> Void = { _ in }
    var onStripZoom: () -> Void = {}
    /// A window was adopted (for scripts): id, app, title.
    var onWindowOpened: (WindowID, String, String) -> Void = { _, _, _ in }
    /// Changes a setting the user owns (gaps, open-into-slide), through the settings store.
    var onAdjustSettings: ((inout AppSettings) -> Void) -> Void = { _ in }
    /// The workspace shown changed: its name, number and how many there are.
    var onWorkspaceShown: (String, Int, Int) -> Void = { _, _, _ in }
    /// Ask the user for a slide name; the cheat sheet.
    var onAskForSlideName: (WindowID, String) -> Void = { _, _ in }
    var onCheatSheet: () -> Void = {}
    /// A slide or workspace change worth announcing to VoiceOver.
    var onAnnounce: (String) -> Void = { _ in }
    var onAskForSnapshotName: () -> Void = {}
    /// A short confirmation to show the user ("Nothing to undo").
    var onNotice: (String) -> Void = { _ in }
    /// Marks need a letter typed next: the app reads it and calls back.
    var onAskForLetter: (Action) -> Void = { _ in }
    /// The user started dragging a window (for the snap layouts picker).
    var onWindowDrag: (WindowID) -> Void = { _ in }
    /// Something worth counting for Insights happened.
    var onUsage: (UsageEvent) -> Void = { _ in }

    private var windows: [WindowID: ManagedWindow] = [:]
    private var strips: [StripKey: Strip] = [:]
    /// The workspace shown on each display and Space.
    private var activeWorkspace: [ScreenKey: Int] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var displays: [Display] = []
    private let animator = Animator()
    private let writer = WindowWriter()
    private let overlays = Overlays()
    private var lastApplyTime: CFTimeInterval = 0
    private var enhancedUIRestore: Set<pid_t> = []
    private var workspaceTokens: [NSObjectProtocol] = []
    private var mouseUpTimer: Timer?
    private var saveTimer: Timer?
    private var syncTimer: Timer?
    private var swipeDisplay: Display?
    private var lastFocusFollowsMouse: CFTimeInterval = 0
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    init(settings: AppSettings) {
        self.settings = settings
        animator.apply = { [weak self] id, rect, sizeChanged in
            self?.apply(rect, to: id, sizeChanged: sizeChanged)
        }
        animator.onFinish = { [weak self] in
            self?.restoreEnhancedUI()
            self?.updateOverlays()
        }
        overlays.onSelectWindow = { [weak self] id in self?.focusAndReveal(id) }
        overlays.onDropTab = { [weak self] id, point in self?.dropTab(id, at: point) }
        // The app's own move/resize notifications arrive after the write lands;
        // stamping the time then keeps them from looking like the user's moves.
        writer.didApply = { [weak self] id in
            self?.windows[id]?.appliedAt = CACurrentMediaTime()
            self?.scheduleFitCheck(id)
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        loadState()
        registerWorkspaceNotifications()
        sync()
        attentionTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refreshAttention()
        }
        log.info("Engine started with \(self.windows.count) windows")
    }

    /// Puts every window back on screen and saves the layout. Called on quit.
    func shutdown() {
        guard isRunning else { return }
        attentionTimer?.invalidate()
        animator.finishNow()
        if settings.autoSnapshot { saveSnapshot(named: Self.lastSessionName, quiet: true) }
        saveState()
        restoreAll()
        overlays.hideAll()
    }

    func togglePause() {
        setPaused(!isPaused)
    }

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        if paused {
            animator.finishNow()
            restoreAll()
            overlays.hideAll()
        } else {
            for window in windows.values { window.lastApplied = nil }
            sync()
        }
        onStateChange()
    }

    /// Forgets cached frames and re-applies the layout from scratch.
    func retile() {
        guard !isPaused else { return }
        for window in windows.values { window.lastApplied = nil }
        sync()
    }

    private func settingsDidChange(from old: AppSettings) {
        guard isRunning, !isPaused else { return }
        if activeProfile >= settings.profiles.count { switchProfile(to: 0) }
        if settings.attentionMarkers != old.attentionMarkers { refreshAttention() }
        if settings.layout != old.layout || settings.keepHeights != old.keepHeights
            || settings.sliderBar != old.sliderBar || settings.sliderBarEdge != old.sliderBarEdge
        {
            for (key, var strip) in strips {
                if let display = display(for: key) {
                    strip.revealFocused(config: layoutConfig(for: display), viewportWidth: viewport(of: display).width)
                }
                strips[key] = strip
            }
            layout(animated: true)
        } else {
            updateOverlays()
        }
        onStateChange()
    }

    // MARK: - Actions

    func perform(_ requested: Action) {
        let action = visual(requested)
        switch action {
        case .togglePause:
            togglePause()
            return
        case .retile:
            retile()
            return
        case .windowSwitcher:
            onShowSwitcher()
            return
        case .overview:
            onShowOverview()
            return
        case .undo:
            undo()
            return
        case .setMark, .jumpToMark:
            onAskForLetter(requested)
            return
        default:
            break
        }
        guard isRunning, !isPaused else { return }
        switch action {
        case .toggleScratchpad:
            toggleScratchpad()
            return
        case .makeScratchpad:
            makeScratchpad()
            return
        case .nextProfile:
            switchProfile(to: (activeProfile + 1) % max(settings.profiles.count, 1))
            return
        case .toggleFocusMode:
            setFocusMode(!isFocusMode)
            return
        case .commandPalette:
            onShowPalette()
            return
        case .takeSnapshot:
            onAskForSnapshotName()
            return
        case .toggleSticky:
            if let id = focusedWindowID() { toggleSticky(id) }
            return
        case .zoomTile:
            toggleZoom()
            return
        case .lastWindow:
            focusLastWindow()
            return
        case .quickLaunch:
            onAskForLetter(.quickLaunch)
            return
        case .pictureInPicture:
            if let id = focusedWindowID() { onPictureInPicture(id) }
            return
        case .radialMenu:
            onRadialMenu()
            return
        case .workspaceBackAndForth:
            if let (_, key) = activeContext(), let previous = previousWorkspace[key.screen],
                previous / Self.profileStride == activeProfile
            {
                switchWorkspace(to: previous - base)
            }
            return
        case .moveToEmptyWorkspace:
            moveFocusedToEmptyWorkspace()
            return
        case .focusAttention:
            if let id = windows.values.first(where: { attentionApps.contains($0.appName) })?.id {
                focusAndReveal(id)
            } else {
                onNotice("Nothing needs your attention")
            }
            return
        case .showDesktop:
            showingDesktop.toggle()
            layout(animated: true)
            return
        case .screenshotSlide:
            screenshotSlide()
            return
        case .appOverview:
            if let id = focusedWindowID(), let window = windows[id] { onShowAppOverview(Self.appKey(window)) }
            return
        case .balanceSizes:
            balanceSizes()
            return
        case .windowHints:
            onWindowHints()
            return
        case .resizeMode:
            onResizeMode(true)
            return
        case .stripZoom:
            onStripZoom()
            return
        case .presentationMode:
            setPresenting(!isPresenting)
            return
        case .recordSlide:
            toggleRecording()
            return
        case .redo:
            redo()
            return
        case .nextWorkspace, .previousWorkspace:
            switchWorkspaceVertically(next: action == .nextWorkspace)
            return
        case .moveToNextWorkspace, .moveToPreviousWorkspace:
            if let (_, key) = activeContext() {
                let target = key.workspace - base + (action == .moveToNextWorkspace ? 1 : -1)
                if target >= 0, target < workspaceLimit {
                    moveFocusedWindow(toWorkspace: target)
                    onNotice("Moved to \(settings.workspaceName(target))")
                }
            }
            return
        case .focusNextDisplay:
            focusNextDisplay()
            return
        case .moveWorkspaceToNextDisplay:
            moveWorkspaceToNextDisplay()
            return
        case .swapDisplays:
            swapDisplays()
            return
        case .moveToPointerDisplay:
            moveFocusedToPointerDisplay()
            return
        case .cycleAppWindows:
            cycleAppWindows()
            return
        case .swapWithRecent:
            swapWithRecent()
            return
        case .closeSlide, .minimizeSlide:
            if let id = focusedWindowID(), let key = windows[id]?.key, let strip = strips[key], let (c, _) = strip.locate(id) {
                for mate in strip.columns[c].windows {
                    if action == .closeSlide { closeWindow(mate) } else { minimizeWindow(mate) }
                }
            }
            return
        case .gatherApp:
            gatherFocusedApp()
            return
        case .tileAllFloating:
            tileAllFloating()
            return
        case .rescueWindows:
            rescueWindows()
            return
        case .soloMode:
            toggleSolo()
            return
        case .toggleGaps, .biggerGaps, .smallerGaps:
            adjustGaps(action)
            return
        case .centerFloating:
            centerFocusedFloating()
            return
        case .openIntoSlide:
            let on = !settings.openIntoFocusedSlide
            onAdjustSettings { $0.openIntoFocusedSlide = on }
            onNotice(on ? "New windows join the focused slide" : "New windows get their own place again")
            return
        case .cheatSheet:
            onCheatSheet()
            return
        case .nameSlide:
            if let id = focusedWindowID(), windows[id]?.key != nil { onAskForSlideName(id, slideName(of: id) ?? "") }
            return
        case .lockSlide:
            if let id = focusedWindowID() { toggleLock(id) }
            return
        default:
            break
        }
        if Self.undoable.contains(action) || action.moveToWorkspaceNumber != nil { recordHistory() }
        if let n = action.workspaceNumber {
            switchWorkspace(to: n - 1)
            return
        }
        if action == .regroup {
            resetToSmartPairs()
            return
        }
        if let position = action.snapPosition {
            snap(position)
            return
        }
        if action == .snapRestore {
            snapRestore()
            return
        }
        if let n = action.moveToWorkspaceNumber {
            moveFocusedWindow(toWorkspace: n - 1)
            return
        }
        animator.finishNow()

        switch action {
        case .toggleFloat:
            toggleFloat()
            return
        case .sendToNextDisplay:
            sendToNextDisplay()
            return
        case .toggleNativeFullScreen:
            if let id = focusedWindowID(), let window = windows[id] ?? adoptFocused(id) {
                window.element.set("AXFullScreen", (window.element.isFullScreen ? kCFBooleanFalse : kCFBooleanTrue)!)
            }
            return
        default:
            break
        }

        guard let (display, key) = activeContext(), var strip = strips[key], !strip.isEmpty else { return }
        strip.pairingArrangement = settings.slideArrangement
        let config = layoutConfig(for: display)
        let columnBefore = strip.focusedColumn
        let width = viewport(of: display).width
        if let focused = focusedWindowID(), strip.contains(focused) { strip.focus(focused) }

        var reveal = true
        switch action {
        case .focusLeft: strip.moveFocus(.left)
        case .focusRight: strip.moveFocus(.right)
        case .focusUp: strip.moveFocus(.up)
        case .focusDown: strip.moveFocus(.down)
        case .focusFirst: strip.focusColumn(at: 0)
        case .focusLast: strip.focusColumn(at: strip.columns.count - 1)
        case .moveLeft: strip.moveFocused(.left)
        case .moveRight: strip.moveFocused(.right)
        case .moveUp: strip.moveFocused(.up)
        case .moveDown: strip.moveFocused(.down)
        case .cycleWidth: strip.cycleWidth(presets: config.sanitizedPresets, forward: true)
        case .cycleWidthBackward: strip.cycleWidth(presets: config.sanitizedPresets, forward: false)
        case .narrower: strip.adjustWidth(by: -0.1)
        case .wider: strip.adjustWidth(by: 0.1)
        case .toggleFullWidth: strip.toggleFullWidth()
        case .center:
            strip.centerFocused(config: config, viewportWidth: width)
            reveal = false
        case .consumeIntoLeft: strip.consumeIntoLeft()
        case .consumeIntoRight: strip.consumeIntoRight()
        case .expelLeft: strip.expelLeft()
        case .expel: strip.expel()
        case .cycleLayout: strip.cycleArrangement()
        case .mainLarger: strip.adjustSplit(by: 0.05)
        case .mainSmaller: strip.adjustSplit(by: -0.05)
        case .makeMain: strip.promoteToMain()
        case .regroup:
            strip = smartPairs(strip)
        case .pinLeft: strip.togglePin(.left)
        case .pinRight: strip.togglePin(.right)
        case .toggleTabbed: strip.toggleTabbed()
        case .rotateSlide: strip.rotateFocused()
        case .flipSlide: strip.flipFocused()
        case .sortSlides:
            strip.sortColumns { [weak self] column in
                column.windows.first.flatMap { self?.windows[$0]?.appName } ?? ""
            }
        case .expandToFill:
            expandToFill(&strip, display: display)
        default:
            if let number = action.columnNumber { strip.focusColumn(at: number - 1) }
        }
        if reveal { strip.revealFocused(config: config, viewportWidth: width) }
        if strip.focusedColumn != columnBefore {
            haptic()
            onUsage(.switched)
        }
        strips[key] = strip
        layout(animated: true)
        if let target = strip.focusedWindow, target != focusedWindowID() {
            focus(target, warpMouse: true)
        }
        scheduleSave()
    }

    /// Actions that change the arrangement (not just focus or scrolling).
    private static let undoable: Set<Action> = [
        .moveLeft, .moveRight, .moveUp, .moveDown, .cycleWidth, .cycleWidthBackward, .narrower, .wider,
        .toggleFullWidth, .consumeIntoLeft, .consumeIntoRight, .expelLeft, .expel, .pinLeft, .pinRight,
        .toggleTabbed, .cycleLayout, .mainLarger, .mainSmaller, .makeMain, .regroup, .toggleFloat,
        .sendToNextDisplay, .rotateSlide, .flipSlide, .sortSlides, .expandToFill,
    ]

    /// Keys name what you see: with a right-to-left strip, "left" is the
    /// strip's next column, so left and right actions swap.
    private func visual(_ action: Action) -> Action {
        guard settings.layout.direction == .rightToLeft else { return action }
        let swaps: [Action: Action] = [
            .focusLeft: .focusRight, .focusRight: .focusLeft,
            .moveLeft: .moveRight, .moveRight: .moveLeft,
            .consumeIntoLeft: .consumeIntoRight, .consumeIntoRight: .consumeIntoLeft,
            .expelLeft: .expel, .expel: .expelLeft,
            .pinLeft: .pinRight, .pinRight: .pinLeft,
        ]
        return swaps[action] ?? action
    }

    /// Focuses any managed window, scrolling its strip to show it.
    func focusAndReveal(_ id: WindowID) {
        guard let window = windows[id] else { return }
        if let key = window.key { showWorkspace(of: key) }
        if let key = window.key, var strip = strips[key], let display = display(for: key) {
            strip.focus(id)
            strip.revealFocused(config: layoutConfig(for: display), viewportWidth: viewport(of: display).width)
            strips[key] = strip
            layout(animated: true)
        }
        focus(id, warpMouse: true)
    }

    private func toggleFloat() {
        guard let id = focusedWindowID() else { return }
        guard let window = windows[id] else {
            // An unmanaged (e.g. ignored) window: tile it.
            if let window = adoptFocused(id), window.key == nil { tile(window) }
            return
        }
        if let key = window.key {
            let display = self.display(for: key)
            removeFromStrip(window)
            if let display {
                let visible = display.visibleFrame
                let size = CGSize(
                    width: min(window.home.width, visible.width * 0.8),
                    height: min(window.home.height, visible.height * 0.8))
                let frame = CGRect(
                    x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                    width: size.width, height: size.height)
                window.element.setFrame(frame)
            }
            window.lastApplied = nil
            layout(animated: true)
        } else {
            tile(window)
        }
        focus(id, warpMouse: false)
    }

    private func tile(_ window: ManagedWindow) {
        if scratchpad == window.id { scratchpad = nil }
        guard let frame = window.element.frame, let display = display(containing: frame) ?? displays.first else {
            return
        }
        place(window, in: currentKey(display), display: display, focus: true, restoring: false)
        layout(animated: true)
    }

    /// Adds a window to a strip: grouped into a slide by app when grouping is
    /// on, otherwise as a column of its own.
    private func place(
        _ window: ManagedWindow, in key: StripKey, display: Display, focus: Bool, width: Double? = nil,
        restoring: Bool = true
    ) {
        // After a restart (new window IDs), windows go back to the slide they
        // were in last session, matched by app and title.
        if restoring, placeFromLastSession(window, display: display, focus: focus) { return }
        // A window coming back (unhidden, unminimised, reopened from the Dock,
        // or its app relaunched) returns to exactly where it was.
        if restoring, let memory = memory(for: window), memory.key.screen == key.screen {
            var strip = strips[memory.key] ?? Strip()
            let visible = memory.key == key
            strip.restore(window.id, to: memory.slot, focus: focus && visible)
            if focus && visible {
                strip.revealFocused(config: layoutConfig(for: display), viewportWidth: viewport(of: display).width)
            }
            strips[memory.key] = strip
            window.key = memory.key
            scheduleSave()
            return
        }
        var strip = strips[key] ?? Strip()
        let rule = settings.rule(for: window.bundleID, title: window.title)
        let position = rule?.position ?? settings.newWindowPosition
        let columnsBefore = strip.columns.count
        if settings.openIntoFocusedSlide, rule?.ownSlide != true, strip.columns.indices.contains(strip.focusedColumn),
            !strip.columns[strip.focusedColumn].isLocked, !strip.columns[strip.focusedColumn].isFull,
            strip.columns[strip.focusedColumn].pin == nil
        {
            // Open-into-slide mode: the window joins the slide you're in.
            strip.add(window.id, toColumn: strip.focusedColumn, focus: focus, custom: true)
        } else if rule?.ownSlide == true || (settings.groupByApp && roomyApps.contains(Self.appKey(window))) {
            // A rule asks for it, or the app can't shrink to share a slide.
            strip.insertSlide(
                [window.id], width: 1, arrangement: settings.arrangement(for: window.bundleID),
                position: position, focus: focus)
        } else if settings.groupByApp {
            let decision = Grouping.decide(
                newApp: Self.appKey(window),
                strip: strip,
                app: { [weak self] id in self?.windows[id].map(Self.appKey) },
                capacity: { [weak self] app in self?.settings.tiles(for: app) ?? 2 },
                pairSize: settings.tilesPerSlide,
                pairLoneWindows: settings.pairLoneWindowsOnOpen
            )
            let roomy = { [weak self] (id: WindowID) -> Bool in
                guard let self, let other = self.windows[id] else { return false }
                return self.roomyApps.contains(Self.appKey(other))
            }
            // Never squeeze a window in next to one that can't shrink.
            let blocked: Bool
            switch decision {
            case .join(let column): blocked = strip.columns[column].windows.contains(where: roomy)
            case .pairWith(let other): blocked = roomy(other)
            case .newSlide: blocked = false
            }
            switch blocked ? Grouping.Decision.newSlide : decision {
            case .join(let column):
                strip.add(window.id, toColumn: column, focus: focus)
            case .pairWith(let other):
                strip.remove(other)
                strip.insertSlide(
                    [other, window.id], width: 1, arrangement: settings.arrangement(for: window.bundleID),
                    position: .afterFocused, focus: focus)
            case .newSlide:
                strip.insertSlide(
                    [window.id], width: rememberedWidth(window) ?? 1, arrangement: settings.arrangement(for: window.bundleID),
                    position: position, focus: focus)
            }
        } else {
            strip.insert(
                window.id, width: width ?? rule?.width ?? rememberedWidth(window) ?? settings.layout.defaultWidth,
                position: position, focus: focus)
        }
        // Next to the app's other windows, if that's the preference.
        if settings.openNextToSameApp, strip.columns.count > columnsBefore, let new = strip.locate(window.id)?.column,
            let last = strip.columns.indices.last(where: { index in
                index != new && strip.columns[index].windows.contains { windows[$0].map(Self.appKey) == Self.appKey(window) }
            })
        {
            strip.moveColumn(from: new, to: last < new ? last + 1 : last)
        }
        if focus { strip.revealFocused(config: layoutConfig(for: display), viewportWidth: viewport(of: display).width) }
        strips[key] = strip
        window.key = key
        scheduleSave()
    }

    /// Windows are grouped by app bundle, or by name for apps without one.
    static func appKey(_ window: ManagedWindow) -> String {
        window.bundleID ?? window.appName
    }

    /// Regroups `strip` by app: same-app windows share slides, lone windows pair up.
    private func smartPairs(_ strip: Strip) -> Strip {
        var strip = strip
        let groups = Grouping.plan(
            strip.columns.filter { $0.pin == nil && !$0.isLocked }.flatMap(\.windows),
            app: { [weak self] id in self?.windows[id].map(Self.appKey) ?? "" },
            capacity: { [weak self] app in self?.settings.tiles(for: app) ?? 2 },
            pairSize: settings.tilesPerSlide
        )
        strip.regroup(groups, width: 1) { [weak self] group in
            guard let self, let first = group.first else { return .grid }
            return self.settings.arrangement(for: self.windows[first]?.bundleID)
        }
        return strip
    }

    /// The single "undo my own pairings" action: every workspace on the
    /// visible Spaces goes back to smart pairs.
    func resetToSmartPairs() {
        guard isRunning, !isPaused else { return }
        let screens = Set(displays.map { currentKey($0).screen })
        var changed = false
        var slides = 0
        for (key, strip) in strips where screens.contains(key.screen) {
            var paired = smartPairs(strip)
            changed = changed || paired.columns.map(\.windows) != strip.columns.map(\.windows)
                || paired.columns.contains(where: \.isCustom) != strip.columns.contains(where: \.isCustom)
            if key == displays.first.map(currentKey) { slides = paired.columns.count }
            if let display = display(for: key) {
                paired.revealFocused(config: layoutConfig(for: display), viewportWidth: viewport(of: display).width)
            }
            strips[key] = paired
        }
        appMemory.removeAll()
        windowMemory.removeAll()
        layout(animated: true)
        scheduleSave()
        onStateChange()
        onNotice(changed ? "Smart pairs · \(slides) \(slides == 1 ? "slide" : "slides")" : "Already in smart pairs")
    }

    // MARK: - Workspaces

    /// Shows workspace `index` on the active display.
    /// `slide`: +1 brings the workspace up from below, -1 down from above, 0 as usual.
    func switchWorkspace(to index: Int, slide: Int = 0) {
        guard index >= 0, index < workspaceLimit, let (display, key) = activeContext(),
            base + index != key.workspace
        else { return }
        previousWorkspace[key.screen] = key.workspace
        showingDesktop = false
        activeWorkspace[key.screen] = base + index
        let newKey = currentKey(display)
        carryStickyWindows(to: newKey)
        if var strip = strips[newKey] {
            strip.revealFocused(config: layoutConfig(for: display), viewportWidth: viewport(of: display).width)
            strips[newKey] = strip
            if slide != 0 {
                // Start each window a screen below (or above) where it goes, so the workspace slides in.
                for placement in strip.layout(config: layoutConfig(for: display), viewport: viewport(of: display)) {
                    var start = placement.frame
                    start.y += Double(display.frame.height) * Double(slide)
                    windows[placement.window]?.lastApplied = start
                }
            }
        }
        layout(animated: true)
        if let target = strips[newKey]?.focusedWindow { focus(target, warpMouse: false) }
        scheduleSave()
        onStateChange()
        let name = settings.workspaceName(index)
        onWorkspaceShown(name, index, visibleWorkspaceCount(on: key.screen))
        onAnnounce("\(name), \(strips[newKey]?.columns.count ?? 0) slides")
    }

    /// Makes the workspace that holds `key` the visible one on its display.
    private func showWorkspace(of key: StripKey) {
        let profile = key.workspace / Self.profileStride
        if profile != activeProfile {
            // A window of another profile was focused (⌘Tab): show that profile.
            profileWorkspaces[activeProfile] = activeWorkspace
            activeProfile = profile
            activeWorkspace = profileWorkspaces[profile] ?? [:]
            onNotice("Profile · \(profileName)")
        }
        guard (activeWorkspace[key.screen] ?? base) != key.workspace else { return }
        activeWorkspace[key.screen] = key.workspace
        onStateChange()
    }

    // MARK: - Profiles

    /// Profiles are separate sets of workspaces. Workspace numbers are
    /// absolute: profile × 100 plus the workspace within the profile.
    static let profileStride = 100
    private(set) var activeProfile = 0
    /// The workspace each screen last showed in each profile.
    private var profileWorkspaces: [Int: [ScreenKey: Int]] = [:]

    private var base: Int { activeProfile * Self.profileStride }

    var profileName: String {
        settings.profiles.indices.contains(activeProfile) ? settings.profiles[activeProfile] : "Default"
    }

    /// Shows another profile: its windows come back, the current ones wait.
    func switchProfile(to index: Int) {
        guard isRunning, !isPaused, index != activeProfile, index >= 0,
            index < max(settings.profiles.count, 1)
        else { return }
        animator.finishNow()
        profileWorkspaces[activeProfile] = activeWorkspace
        activeProfile = index
        activeWorkspace = profileWorkspaces[index] ?? [:]
        for display in displays {
            let key = currentKey(display)
            carryStickyWindows(to: key)
            if var strip = strips[key] {
                strip.revealFocused(config: layoutConfig(for: display), viewportWidth: viewport(of: display).width)
                strips[key] = strip
            }
        }
        layout(animated: true)
        if let (_, key) = activeContext(), let target = strips[key]?.focusedWindow { focus(target, warpMouse: false) }
        scheduleSave()
        onStateChange()
        onNotice("Profile · \(profileName)")
    }

    // MARK: - Dynamic workspaces

    /// How many workspaces the keys can reach.
    private var workspaceLimit: Int { settings.dynamicWorkspaces ? 9 : settings.workspaceCount }

    /// The workspaces offered on `screen`: all of them, or with dynamic
    /// workspaces the ones in use plus one empty one.
    func visibleWorkspaceCount(on screen: ScreenKey) -> Int {
        guard settings.dynamicWorkspaces else { return settings.workspaceCount }
        let used = strips.filter { key, strip in
            key.screen == screen && key.workspace / Self.profileStride == activeProfile && !strip.isEmpty
        }.map { $0.key.workspace - base }
        let shown = (activeWorkspace[screen] ?? base) - base
        return min(9, max(used.max() ?? 0, shown) + 2)
    }

    /// The workspaces offered on the active display, for menus.
    var workspaceCount: Int {
        guard let (_, key) = activeContext() else { return settings.workspaceCount }
        return visibleWorkspaceCount(on: key.screen)
    }

    private func moveFocusedWindow(toWorkspace index: Int) {
        guard index >= 0, index < workspaceLimit, let id = focusedWindowID(), let window = windows[id],
            let key = window.key, key.workspace != base + index, let display = display(for: key)
        else { return }
        let width = strips[key].flatMap { strip in strip.locate(id).map { strip.columns[$0.column].width } }
        removeFromStrip(window)
        var target = key
        target.workspace = base + index
        place(window, in: target, display: display, focus: true, width: width, restoring: false)
        layout(animated: true)
        if let next = strips[key]?.focusedWindow { focus(next, warpMouse: false) }
        onStateChange()
    }

    // MARK: - Window commands (previews, overview)

    /// Names the user gave windows in Monorail; shown instead of the title.
    private var names: [WindowID: String] = [:]

    func displayTitle(_ window: ManagedWindow) -> String {
        names[window.id] ?? window.title
    }

    func customName(of id: WindowID) -> String? { names[id] }

    /// Renames a window in Monorail (the app's own title is untouched).
    /// An empty name goes back to the window's title.
    func rename(_ id: WindowID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        names[id] = trimmed.isEmpty ? nil : trimmed
        scheduleSave()
        updateOverlays()
        onStateChange()
    }

    func closeWindow(_ id: WindowID) {
        guard let close = windows[id]?.element.element(kAXCloseButtonAttribute) else { return }
        AXUIElementPerformAction(close, kAXPressAction as CFString)
    }

    func minimizeWindow(_ id: WindowID) {
        windows[id]?.element.set(kAXMinimizedAttribute, kCFBooleanTrue)
    }

    func toggleFullScreen(_ id: WindowID) {
        guard let element = windows[id]?.element else { return }
        element.set("AXFullScreen", (element.isFullScreen ? kCFBooleanFalse : kCFBooleanTrue)!)
    }

    func workspaceIndex(of id: WindowID) -> Int? { windows[id]?.key.map { $0.workspace - base } }

    /// The rows of the custom layout of the slide holding `id`, if it has one.
    func slideRows(of id: WindowID) -> [Int]? {
        guard let key = windows[id]?.key, let strip = strips[key], let (c, _) = strip.locate(id),
            strip.columns[c].arrangement == .custom
        else { return nil }
        return strip.columns[c].customRows
    }

    /// The layout of the slide holding `id`: an arrangement, or nil for tabs.
    func slideLayout(of id: WindowID) -> Arrangement?? {
        guard let key = windows[id]?.key, let strip = strips[key], let (c, _) = strip.locate(id) else { return nil }
        return .some(strip.columns[c].isTabbed ? nil : strip.columns[c].arrangement)
    }

    /// Sets the layout of the slide holding `id` (nil for tabs).
    func setSlideLayout(of id: WindowID, to arrangement: Arrangement?, rows: [Int]? = nil) {
        guard let key = windows[id]?.key, var strip = strips[key] else { return }
        recordHistory()
        strip.focus(id)
        if let arrangement {
            strip.setArrangement(arrangement, rows: rows)
        } else if let (c, _) = strip.locate(id), !strip.columns[c].isTabbed {
            strip.toggleTabbed()
        }
        commit(strip, key)
        onStateChange()
    }

    /// Moves any window (not just the focused one) to a workspace on its display.
    func moveWindow(_ id: WindowID, toWorkspace index: Int) {
        guard index >= 0, index < workspaceLimit, let window = windows[id], let key = window.key,
            key.workspace != base + index, let display = display(for: key)
        else { return }
        recordHistory()
        let width = strips[key].flatMap { strip in strip.locate(id).map { strip.columns[$0.column].width } }
        removeFromStrip(window)
        var target = key
        target.workspace = base + index
        place(window, in: target, display: display, focus: false, width: width, restoring: false)
        layout(animated: true)
        onStateChange()
    }

    // MARK: - Overview

    struct OverviewColumn: Identifiable {
        var id: Int
        var windows: [WindowSummary]
        var width: Double
        var arrangement: Arrangement
        var split: Double
        var isTabbed: Bool
        var isFocused: Bool
        var pin: PinSide?
        var customRows: [Int]?
        var name: String?
        var isLocked = false
    }

    struct OverviewStrip: Identifiable {
        var id: StripKey { key }
        var key: StripKey
        var title: String
        var isActive: Bool
        var columns: [OverviewColumn]
        /// Index of the workspace, for its colour.
        var workspace: Int
        var aspectRatio: Double
        var isRightToLeft: Bool
        /// Windows waiting in the Dock while the workspace is parked.
        var parkedCount: Int = 0
        /// The workspace's own name, without display or profile.
        var name: String = ""
    }

    /// Every workspace on the displays' current Spaces, for the overview.
    /// Every workspace, or with `onlyApp` just that app's windows.
    func overview(onlyApp: String? = nil) -> [OverviewStrip] {
        let focused = focusedWindowID()
        var result: [OverviewStrip] = []
        for display in displays {
            let current = currentKey(display)
            let count = visibleWorkspaceCount(on: current.screen)
            for workspace in 0..<count {
                let key = StripKey(screen: current.screen, workspace: base + workspace)
                let strip = strips[key] ?? Strip()
                let columns = strip.columns.enumerated().map { index, column in
                    OverviewColumn(
                        id: index,
                        windows: column.windows.compactMap { id in
                            windows[id].map { summary($0, focused: id == focused) }
                        },
                        width: column.effectiveWidth,
                        arrangement: column.arrangement,
                        split: column.split,
                        isTabbed: column.isTabbed,
                        isFocused: index == strip.focusedColumn && key == current,
                        pin: column.pin,
                        customRows: column.customRows,
                        name: column.name,
                        isLocked: column.isLocked
                    )
                }.compactMap { column -> OverviewColumn? in
                    guard let onlyApp else { return column }
                    var column = column
                    column.windows = column.windows.filter { summary in
                        windows[summary.id].map(Self.appKey) == onlyApp
                    }
                    return column.windows.isEmpty ? nil : column
                }
                if onlyApp != nil && columns.isEmpty { continue }
                var title = count > 1 ? settings.workspaceName(workspace) : "Windows"
                if settings.profiles.count > 1 { title = "\(profileName) · \(title)" }
                if displays.count > 1 { title = "\(display.name) · \(title)" }
                result.append(
                    OverviewStrip(
                        key: key, title: title, isActive: key == current, columns: columns, workspace: workspace,
                        aspectRatio: display.visibleFrame.width / max(display.visibleFrame.height, 1),
                        isRightToLeft: settings.layout.direction == .rightToLeft,
                        parkedCount: parked[key]?.elements.count ?? 0,
                        name: settings.workspaceName(workspace)))
            }
        }
        return result
    }

    /// Drag and drop in the overview: moves `id` into column `column` of the
    /// strip `target`, or into a new column at `newColumnAt`.
    func overviewMove(_ id: WindowID, to target: StripKey, column: Int? = nil, newColumnAt: Int? = nil) {
        guard let window = windows[id], let source = window.key else { return }
        recordHistory()
        let width = strips[source].flatMap { strip in strip.locate(id).map { strip.columns[$0.column].width } }
            ?? settings.layout.defaultWidth
        if source == target {
            guard var strip = strips[target] else { return }
            strip.pairingArrangement = settings.slideArrangement
            if let column {
                strip.moveWindow(id, intoColumn: column)
            } else if let newColumnAt {
                strip.moveWindow(id, toNewColumnAt: newColumnAt, width: width)
            }
            strips[target] = strip
        } else {
            // Work out the target position before removing, in case both strips are the same list.
            removeFromStrip(window)
            var strip = strips[target] ?? Strip()
            strip.pairingArrangement = settings.slideArrangement
            if let column, strip.columns.indices.contains(column) {
                strip.add(id, toColumn: column, focus: true, custom: true)
            } else {
                strip.insert(id, width: width, position: .end, focus: true)
                if let newColumnAt { strip.moveColumn(from: strip.columns.count - 1, to: newColumnAt) }
            }
            strips[target] = strip
            window.key = target
        }
        layout(animated: true)
        scheduleSave()
        onStateChange()
    }

    /// Reorders whole columns in the overview.
    func overviewMoveColumn(from: Int, to: Int, in key: StripKey) {
        guard var strip = strips[key] else { return }
        recordHistory()
        strip.moveColumn(from: from, to: to > from ? to - 1 : to)
        strips[key] = strip
        layout(animated: true)
        scheduleSave()
    }

    // MARK: - Slider bar

    struct MiniWindow: Equatable, Identifiable {
        var id: WindowID
        var pid: pid_t
        var appName: String
        var title: String
        var needsAttention = false
    }

    struct MiniTile: Equatable, Identifiable {
        var id: Int
        /// Position and width in strip points.
        var x: Double
        var width: Double
        var windows: [MiniWindow]
        var arrangement: Arrangement
        var split: Double
        var isFocused: Bool
        var customRows: [Int]?
        var name: String?
        var isLocked = false
    }

    /// Everything the slider bar draws for one display.
    struct MiniMap: Equatable {
        var displayUUID: String
        /// The display's visible frame, in Cocoa coordinates (for placing the bar).
        var screenFrame: CGRect
        var workspace: Int
        var workspaceCount: Int
        var workspaceNames: [String]
        var tiles: [MiniTile]
        var totalWidth: Double
        /// The part of the strip on screen, in strip points.
        var viewportX: Double
        var viewportWidth: Double
        var isRightToLeft: Bool
        /// Whether the slider bar shows on this display.
        var barMode: SliderBarMode = .whileMoving
    }

    func miniMaps() -> [MiniMap] {
        guard isRunning, !isPaused else { return [] }
        let focused = focusedWindowID()
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return displays.map { display in
            let key = currentKey(display)
            let strip = strips[key] ?? Strip()
            let width = viewport(of: display).width
            let config = layoutConfig(for: display)
            let offsets = strip.columnOffsets(config: config, viewportWidth: width)
            let tiles = strip.columns.indices.filter { strip.columns[$0].pin == nil }.map { index in
                let column = strip.columns[index]
                return MiniTile(
                    id: index,
                    x: offsets[index],
                    width: strip.width(ofColumn: index, config: config, viewportWidth: width),
                    windows: column.windows.compactMap { id in
                        windows[id].map {
                            MiniWindow(
                                id: id, pid: $0.pid, appName: $0.appName, title: displayTitle($0),
                                needsAttention: attentionApps.contains($0.appName))
                        }
                    },
                    arrangement: column.arrangement,
                    split: column.split,
                    isFocused: index == strip.focusedColumn && column.windows.contains { $0 == focused },
                    customRows: column.customRows,
                    name: column.name,
                    isLocked: column.isLocked
                )
            }
            let visible = display.visibleFrame
            return MiniMap(
                displayUUID: display.uuid,
                screenFrame: CGRect(
                    x: visible.minX, y: primaryHeight - visible.maxY, width: visible.width, height: visible.height),
                workspace: key.workspace - base,
                workspaceCount: visibleWorkspaceCount(on: key.screen),
                workspaceNames: (0..<visibleWorkspaceCount(on: key.screen)).map(settings.workspaceName),
                tiles: tiles,
                totalWidth: strip.totalWidth(config: config, viewportWidth: width),
                viewportX: strip.scroll,
                viewportWidth: strip.scrollArea(config: config, viewportWidth: width).width,
                isRightToLeft: settings.layout.direction == .rightToLeft,
                barMode: settings.sliderBar(for: display.uuid)
            )
        }
    }

    /// Drags the strip on `displayUUID` so its viewport starts at `stripX`.
    func slide(to stripX: Double, displayUUID: String) {
        guard isRunning, !isPaused, let display = displays.first(where: { $0.uuid == displayUUID }) else { return }
        let key = currentKey(display)
        guard var strip = strips[key], !strip.isEmpty else { return }
        swipeDisplay = display
        animator.cancel()
        overlays.hideTransient()
        let width = viewport(of: display).width
        strip.scroll(by: stripX - strip.scroll, config: layoutConfig(for: display), viewportWidth: width)
        strips[key] = strip
        layout(animated: false, updateOverlays: false)
    }

    /// Ends a slider-bar drag the same way a swipe ends.
    func endSlide() {
        endSwipe()
    }

    /// Shows a workspace from the overview without focusing a particular window.
    func overviewShow(_ key: StripKey) {
        showWorkspace(of: key)
        layout(animated: true)
        if let target = strips[key]?.focusedWindow { focus(target, warpMouse: false) }
    }

    private func sendToNextDisplay() {
        guard displays.count > 1, let id = focusedWindowID(), let window = windows[id], let key = window.key,
            let index = displays.firstIndex(where: { $0.uuid == key.display })
        else { return }
        let width = strips[key].flatMap { strip in strip.locate(id).map { strip.columns[$0.column].width } }
        removeFromStrip(window)
        let next = displays[(index + 1) % displays.count]
        place(window, in: currentKey(next), display: next, focus: true, width: width, restoring: false)
        window.lastApplied = nil
        layout(animated: false)
        focus(id, warpMouse: true)
        scheduleSave()
    }

    // MARK: - Trackpad scrolling

    /// Scrolls the strip under the mouse pointer by `delta` points.
    func swipe(by delta: Double) {
        guard isRunning, !isPaused else { return }
        let display = swipeDisplay ?? displayUnderMouse()
        guard let display else { return }
        swipeDisplay = display
        let key = currentKey(display)
        guard var strip = strips[key], !strip.isEmpty else { return }
        let mirrored = settings.layout.direction == .rightToLeft
        let factor = settings.swipeSensitivity * (settings.invertSwipe != mirrored ? -1 : 1)
        animator.cancel()
        overlays.hideTransient()
        strip.scroll(by: delta * factor, config: layoutConfig(for: display), viewportWidth: viewport(of: display).width)
        strips[key] = strip
        layout(animated: false, updateOverlays: false)
    }

    /// Ends a swipe: settles on a column edge and focuses the centred column.
    func endSwipe() {
        guard let display = swipeDisplay else { return }
        swipeDisplay = nil
        let key = currentKey(display)
        guard var strip = strips[key], !strip.isEmpty else { return }
        strip.settle(config: layoutConfig(for: display), viewportWidth: viewport(of: display).width)
        strips[key] = strip
        haptic()
        layout(animated: true)
        if let target = strip.focusedWindow, target != focusedWindowID() {
            focus(target, warpMouse: false)
        }
        scheduleSave()
    }

    /// Moves one column left or right on the display under the mouse pointer
    /// (a mouse-wheel notch or a click on the menu bar arrows).
    /// `visual` steps (the ‹ › buttons) go to the window on that side of the
    /// screen; others (the mouse wheel) go to the strip's next window.
    func step(forward: Bool, honourReverse: Bool = true, visual: Bool = false) {
        guard isRunning, !isPaused else { return }
        var next = honourReverse && settings.invertSwipe ? !forward : forward
        if visual && settings.layout.direction == .rightToLeft { next.toggle() }
        guard let display = displayUnderMouse() ?? displays.first else { return }
        let key = currentKey(display)
        guard var strip = strips[key], !strip.isEmpty else { return }
        if let focused = focusedWindowID(), strip.contains(focused) { strip.focus(focused) }
        let before = strip.focusedColumn
        strip.moveFocus(next ? .right : .left)
        if strip.focusedColumn != before {
            haptic()
            onUsage(.switched)
        }
        strip.revealFocused(config: layoutConfig(for: display), viewportWidth: viewport(of: display).width)
        strips[key] = strip
        layout(animated: true)
        if let target = strip.focusedWindow, target != focusedWindowID() {
            focus(target, warpMouse: false)
        }
        scheduleSave()
    }

    // MARK: - Focus follows mouse

    func mouseMoved(to point: CGPoint) {
        guard settings.focusFollowsMouse, isRunning, !isPaused, swipeDisplay == nil,
            NSEvent.pressedMouseButtons == 0
        else { return }
        let now = CACurrentMediaTime()
        guard now - lastFocusFollowsMouse > max(settings.focusFollowsMouseDelay, 0.05) else { return }
        lastFocusFollowsMouse = now
        guard let id = topWindow(at: point), let window = windows[id], window.key != nil,
            id != focusedWindowID()
        else { return }
        focus(id, warpMouse: false)
    }

    /// The front-most normal window under `point` (Accessibility coordinates).
    private func topWindow(at point: CGPoint) -> WindowID? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for entry in info {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                bounds.contains(point),
                let number = entry[kCGWindowNumber as String] as? NSNumber
            else { continue }
            if (entry[kCGWindowOwnerPID as String] as? pid_t) == ownPID { continue }
            return WindowID(number.uint32Value)
        }
        return nil
    }

    // MARK: - Queries for the UI

    struct Status {
        var workspace: Int
        var focusedColumn: Int
        var columnCount: Int
    }

    func status() -> Status? {
        guard isRunning, let (_, key) = activeContext() else { return nil }
        let strip = strips[key] ?? Strip()
        return Status(
            workspace: key.workspace - base + 1,
            focusedColumn: strip.isEmpty ? 0 : strip.focusedColumn + 1,
            columnCount: strip.columns.count)
    }

    struct WindowSummary: Identifiable {
        var id: WindowID
        var appName: String
        var title: String
        var isTiled: Bool
        var isFocused: Bool
        var icon: NSImage?
        var needsAttention = false
        /// The letter the window is marked with, if any.
        var mark: String?
    }

    /// Windows of the active strip, left to right.
    func activeStripWindows() -> [WindowSummary] {
        guard let (_, key) = activeContext(), let strip = strips[key] else { return [] }
        let focused = strip.focusedWindow
        return strip.allWindows.compactMap { id in
            windows[id].map { summary($0, focused: id == focused) }
        }
    }

    /// Every managed window on the current Spaces, tiled ones first.
    func allWindowSummaries() -> [WindowSummary] {
        let focused = focusedWindowID()
        var result: [WindowSummary] = []
        for display in displays {
            guard let strip = strips[currentKey(display)] else { continue }
            for id in strip.allWindows {
                if let window = windows[id] { result.append(summary(window, focused: id == focused)) }
            }
        }
        for window in windows.values where window.key == nil {
            result.append(summary(window, focused: window.id == focused))
        }
        return result
    }

    private func summary(_ window: ManagedWindow, focused: Bool) -> WindowSummary {
        WindowSummary(
            id: window.id,
            appName: window.appName,
            title: displayTitle(window),
            isTiled: window.key != nil,
            isFocused: focused,
            icon: NSRunningApplication(processIdentifier: window.pid)?.icon,
            needsAttention: attentionApps.contains(window.appName),
            mark: marks.first { $0.value == window.id }?.key
        )
    }

    // MARK: - Layout

    private func layout(animated: Bool, updateOverlays shouldUpdateOverlays: Bool = true, skip: Set<WindowID> = []) {
        guard isRunning, !isPaused else { return }
        var targets: [WindowID: (from: Rect, to: Rect)] = [:]
        for display in displays {
            let key = currentKey(display)
            let strip = strips[key] ?? Strip()
            for placement in strip.layout(config: layoutConfig(for: display), viewport: viewport(of: display)) {
                guard let window = windows[placement.window] else { continue }
                var frame = placement.frame
                if showingDesktop {
                    // Show desktop: everything slides off to the corner.
                    let from = window.lastApplied ?? window.element.frame.map(Rect.init) ?? frame
                    targets[placement.window] = (from, Rect(
                        x: display.frame.maxX - 1, y: display.frame.maxY - 1, width: frame.width, height: frame.height))
                    continue
                }
                if placement.window == zoomed, let (c, _) = strip.locate(placement.window) {
                    // A zoomed tile fills its whole slide, over its slide-mates.
                    frame = strip.columnFrames(config: layoutConfig(for: display), viewport: viewport(of: display))[c].frame
                }
                if settings.keepHeights, placement.window != zoomed, let (c, _) = strip.locate(placement.window),
                    strip.columns[c].windows.count == 1, !strip.columns[c].isTabbed
                {
                    frame.height = min(frame.height, window.home.height.rounded())
                }
                let from = window.lastApplied ?? window.element.frame.map(Rect.init) ?? frame
                targets[placement.window] = (from, frame)
            }
            // Windows of the other workspaces wait in the bottom-right corner,
            // a point from fully hidden (macOS won't move them all the way off).
            for (otherKey, other) in strips where otherKey.screen == key.screen && otherKey != key {
                for id in other.allWindows {
                    guard let window = windows[id] else { continue }
                    let current = window.lastApplied ?? window.element.frame.map(Rect.init)
                    guard let current else { continue }
                    let hidden = Rect(
                        x: display.frame.maxX - 1, y: display.frame.maxY - 1,
                        width: current.width, height: current.height)
                    targets[id] = (current, hidden)
                }
            }
        }

        applyComfortTweaks(&targets)
        for id in skip { targets[id] = nil }

        if animated && settings.animate && !reduceMotion {
            disableEnhancedUI(for: Set(targets.keys.compactMap { windows[$0]?.pid }))
            overlays.hideTransient()
            animator.animate(targets, duration: settings.animationDuration)
        } else {
            animator.cancel()
            for (id, target) in targets {
                guard let window = windows[id] else { continue }
                if let last = window.lastApplied, last.isClose(to: target.to, tolerance: 0.5) { continue }
                let sizeChanged =
                    window.lastApplied.map {
                        abs($0.width - target.to.width) > 0.5 || abs($0.height - target.to.height) > 0.5
                    } ?? true
                apply(target.to, to: id, sizeChanged: sizeChanged)
            }
            if shouldUpdateOverlays { updateOverlays() }
        }
        onStateChange()
    }

    private func apply(_ rect: Rect, to id: WindowID, sizeChanged: Bool) {
        guard let window = windows[id] else { return }
        writer.set(CGRect(rect), of: id, element: window.element, pid: window.pid, sizeChanged: sizeChanged)
        window.lastApplied = rect
        window.appliedAt = CACurrentMediaTime()
        lastApplyTime = window.appliedAt
    }

    /// Apps with enhanced accessibility UI turned on animate every frame change
    /// themselves, which fights the animator. Turn it off while windows move.
    private func disableEnhancedUI(for pids: Set<pid_t>) {
        for pid in pids where !enhancedUIRestore.contains(pid) {
            let app = AXUIElement.application(pid)
            if app.bool("AXEnhancedUserInterface") == true {
                app.set("AXEnhancedUserInterface", kCFBooleanFalse)
                enhancedUIRestore.insert(pid)
            }
        }
    }

    private func restoreEnhancedUI() {
        for pid in enhancedUIRestore {
            AXUIElement.application(pid).set("AXEnhancedUserInterface", kCFBooleanTrue)
        }
        enhancedUIRestore.removeAll()
    }

    private func updateOverlays() {
        guard isRunning, !isPaused, !isPresenting else {
            overlays.hideAll()
            return
        }
        let focusedID = focusedWindowID()
        var focused: (WindowID, CGRect)?
        var inactive: [(WindowID, CGRect)] = []
        var bars: [Overlays.TabBarModel] = []
        // In focus mode the whole focused slide stays bright.
        var brightSlide: Set<WindowID> = []
        if isFocusMode, let id = focusedID, let key = windows[id]?.key, let strip = strips[key],
            let (c, _) = strip.locate(id)
        {
            brightSlide = Set(strip.columns[c].windows)
        }

        for display in displays {
            let key = currentKey(display)
            guard let strip = strips[key], !strip.isEmpty else { continue }
            for placement in strip.layout(config: layoutConfig(for: display), viewport: viewport(of: display))
            where !placement.isParked && !placement.isHiddenTab {
                guard let frame = windows[placement.window]?.lastApplied else { continue }
                if placement.window == focusedID {
                    focused = (placement.window, CGRect(frame))
                } else if brightSlide.contains(placement.window) {
                    continue
                } else {
                    inactive.append((placement.window, CGRect(frame)))
                }
            }
            for bar in strip.tabBars(config: layoutConfig(for: display), viewport: viewport(of: display)) {
                let tabs = bar.windows.map { id in
                    Overlays.Tab(id: id, title: windows[id].map { window in
                        let title = displayTitle(window)
                        return title.isEmpty ? window.appName : title
                    } ?? "", pid: windows[id]?.pid ?? 0)
                }
                bars.append(Overlays.TabBarModel(frame: CGRect(bar.frame), tabs: tabs, active: bar.active))
            }
        }
        var look = settings
        if isFocusMode {
            look.dimInactive = true
            look.dimAmount = min(max(settings.focusDim, 0.2), 0.9)
        }
        overlays.update(focused: focused, inactive: inactive, tabBars: bars, settings: look)
    }

    // MARK: - Focus helpers

    func focusedWindowID() -> WindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return AXUIElement.application(app.processIdentifier).focusedWindow?.windowID
    }

    private func adoptFocused(_ id: WindowID) -> ManagedWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication,
            let element = AXUIElement.application(app.processIdentifier).focusedWindow
        else { return nil }
        adopt(element, pid: app.processIdentifier, focus: true, force: true)
        return windows[id]
    }

    private func focus(_ id: WindowID, warpMouse: Bool) {
        guard let window = windows[id] else { return }
        window.element.set(kAXMainAttribute, kCFBooleanTrue)
        window.element.raise()
        AXUIElement.application(window.pid).set(kAXFrontmostAttribute, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
        if warpMouse && settings.mouseFollowsFocus, let target = targetFrame(of: id) {
            CGWarpMouseCursorPosition(CGPoint(x: target.midX, y: target.midY))
        }
    }

    private func targetFrame(of id: WindowID) -> Rect? {
        guard let key = windows[id]?.key, let strip = strips[key], let display = display(for: key) else { return nil }
        return strip.layout(config: layoutConfig(for: display), viewport: viewport(of: display)).first { $0.window == id }?.frame
    }

    /// The display and strip keyboard actions apply to: the focused window's
    /// strip, or else the display under the mouse pointer.
    private func activeContext() -> (Display, StripKey)? {
        if let id = focusedWindowID(), let key = windows[id]?.key, let display = display(for: key),
            currentKey(display) == key
        {
            return (display, key)
        }
        guard let display = displayUnderMouse() ?? displays.first else { return nil }
        return (display, currentKey(display))
    }

    // MARK: - Displays

    /// The area windows are laid out in: the display's visible frame, minus
    /// room for the slider bar when it is always shown.
    private func viewport(of display: Display) -> Rect {
        var area = display.viewport
        guard settings.sliderBar(for: display.uuid) == .always else { return area }
        let reserved = AppSettings.sliderBarHeight - (settings.compactSlider ? 12 : 0)
        area.height -= reserved
        if settings.sliderBarEdge == .top { area.y += reserved }
        return area
    }

    /// Gaps and widths for a display, with its own overrides from Settings.
    private func layoutConfig(for display: Display) -> LayoutConfig {
        let count = settings.smartGaps ? strips[currentKey(display)]?.allWindows.count ?? 0 : 2
        return settings.layout(for: display.uuid, displayWidth: Double(display.frame.width), windowCount: count)
    }

    private func currentKey(_ display: Display) -> StripKey {
        let screen = ScreenKey(display: display.uuid, space: Spaces.current(displayUUID: display.uuid))
        let stored = activeWorkspace[screen] ?? base
        let relative = stored / Self.profileStride == activeProfile ? stored % Self.profileStride : 0
        return StripKey(screen: screen, workspace: base + min(relative, workspaceLimit - 1))
    }

    private func display(for key: StripKey) -> Display? {
        displays.first { $0.uuid == key.display }
    }

    private func display(containing frame: CGRect) -> Display? {
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        return displays.first { $0.frame.contains(centre) }
            ?? displays.max { $0.frame.intersection(frame).area < $1.frame.intersection(frame).area }
    }

    private func displayUnderMouse() -> Display? {
        let location = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let point = CGPoint(x: location.x, y: primaryHeight - location.y)
        return displays.first { $0.frame.contains(point) }
    }

    // MARK: - Window discovery

    /// Re-reads displays, apps and windows and re-applies the layout.
    func sync() {
        guard isRunning, !isPaused else { return }
        animator.finishNow()
        refreshDisplays()

        let hiddenPIDs = Set(NSWorkspace.shared.runningApplications.filter(\.isHidden).map(\.processIdentifier))
        for (id, window) in windows {
            if !window.element.isAlive || window.element.isMinimized || window.element.isFullScreen
                || hiddenPIDs.contains(window.pid)
            {
                forget(id)
            }
        }

        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != ownPID {
            syncApp(app.processIdentifier, layoutAfter: false)
        }

        // Drop restored or stale entries for windows that no longer exist on the current Spaces.
        let currentScreens = Set(displays.map { currentKey($0).screen })
        for key in strips.keys where currentScreens.contains(key.screen) {
            for id in strips[key]!.allWindows where windows[id]?.key != key {
                strips[key]!.remove(id)
            }
        }

        if let focused = focusedWindowID(), let key = windows[focused]?.key {
            strips[key]?.focus(focused)
        }
        for display in displays {
            let key = currentKey(display)
            guard var strip = strips[key] else { continue }
            strip.clampScroll(config: layoutConfig(for: display), viewportWidth: viewport(of: display).width)
            strip.revealFocused(config: layoutConfig(for: display), viewportWidth: viewport(of: display).width)
            strips[key] = strip
        }
        layout(animated: false)
        scheduleSave()
    }

    private func syncApp(_ pid: pid_t, layoutAfter: Bool) {
        guard pid != ownPID else { return }
        observe(pid)
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        let focusedID = frontmost ? AXUIElement.application(pid).focusedWindow?.windowID : nil
        var changed = false
        for element in AXUIElement.application(pid).windows {
            let id = element.windowID
            changed = adopt(element, pid: pid, focus: id != nil && id == focusedID) || changed
        }
        if changed && layoutAfter { layout(animated: true) }
    }

    private func refreshDisplays() {
        let fresh = Display.all()
        guard fresh != displays else { return }
        displays = fresh
        // Windows on displays that went away join the strip of the first display.
        let uuids = Set(displays.map(\.uuid))
        guard let fallback = displays.first else { return }
        let fallbackKey = currentKey(fallback)
        for key in Array(strips.keys) where !uuids.contains(key.display) {
            guard let orphan = strips.removeValue(forKey: key) else { continue }
            var target = strips[fallbackKey] ?? Strip()
            for column in orphan.columns {
                for id in column.windows {
                    target.insert(id, width: column.width, position: .end, focus: false)
                    windows[id]?.key = fallbackKey
                    windows[id]?.lastApplied = nil
                }
            }
            strips[fallbackKey] = target
        }
    }

    /// Starts managing `element` if it is a normal window. Returns true if a
    /// strip changed.
    @discardableResult
    private func adopt(_ element: AXUIElement, pid: pid_t, focus: Bool, force: Bool = false) -> Bool {
        guard let id = element.windowID, pid != ownPID || demoWindows.contains(id) else { return false }
        if let existing = windows[id] {
            // Known window: just follow focus.
            if focus, let key = existing.key { strips[key]?.focus(id) }
            return false
        }
        guard element.role == kAXWindowRole,
            element.subrole == kAXStandardWindowSubrole,
            !element.isMinimized, !element.isFullScreen,
            element.isSettable(kAXPositionAttribute),
            let frame = element.frame, frame.width >= 80, frame.height >= 60
        else { return false }
        let app = NSRunningApplication(processIdentifier: pid)
        guard pid == ownPID || (app?.activationPolicy == .regular && app?.isHidden == false) else { return false }
        guard !Self.isSystemUI(app?.bundleIdentifier) else { return false }
        // ⌃⌥T (force) can still tile a window the dialog heuristic got wrong.
        guard force || !Self.looksLikeDialog(element) else { return false }

        if displays.isEmpty { refreshDisplays() }
        guard let display = display(containing: frame) ?? displays.first else { return false }
        let key = currentKey(display)
        let spaces = Spaces.spaces(of: id)
        if !spaces.isEmpty && key.space != 0 && !spaces.contains(key.space) { return false }

        let window = ManagedWindow(
            id: id, pid: pid, element: element,
            bundleID: app?.bundleIdentifier,
            appName: app?.localizedName ?? "App",
            home: frame
        )
        windows[id] = window
        observeWindow(element)
        // The scratchpad floats above every workspace.
        if id == scratchpad { return false }
        onUsage(.windowOpened)
        onWindowOpened(id, window.appName, window.title)

        // A window restored from the saved layout keeps its place.
        if let restored = strips.first(where: { $0.value.contains(id) })?.key {
            window.key = restored
            if focus { strips[restored]?.focus(id) }
            return true
        }

        let rule = settings.rule(for: window.bundleID, title: window.title)
        if rule?.isTitleRule == true { titleRuled.insert(id) }
        let floats = rule?.float == true || element.hasFixedSize || !element.isSettable(kAXSizeAttribute)
        if floats && !force {
            // A floating window goes back where you last put this app's windows.
            if settings.rememberFloatingPositions, let frame = floatingFrames[Self.appKey(window)],
                displays.contains(where: { $0.frame.intersects(frame) })
            {
                element.setFrame(frame)
            }
            return false
        }

        // Apps can have a home workspace ("Slack opens in Chat") and display.
        var target = key
        var targetDisplay = display
        if let name = rule?.display, let home = displays.first(where: { $0.name == name }), home.uuid != display.uuid {
            targetDisplay = home
            target = currentKey(home)
        }
        if let home = rule?.workspace, home >= 0, home < workspaceLimit { target.workspace = base + home }
        // A project's windows gather where its first window is.
        if let project = ProjectMatcher.project(in: window.title, projects: settings.projects) {
            projectPlaced.insert(id)
            if let home = projectHomes[project], home.screen == key.screen, home.workspace / Self.profileStride == activeProfile {
                target = home
            } else {
                projectHomes[project] = target
            }
        }
        place(window, in: target, display: targetDisplay, focus: focus && target == key)
        return true
    }

    private func removeFromStrip(_ window: ManagedWindow) {
        guard let key = window.key, var strip = strips[key] else { return }
        strip.remove(window.id)
        if let display = display(for: key) {
            strip.clampScroll(config: layoutConfig(for: display), viewportWidth: viewport(of: display).width)
            strip.revealFocused(config: layoutConfig(for: display), viewportWidth: viewport(of: display).width)
        }
        strips[key] = strip
        window.key = nil
        scheduleSave()
    }

    private func forget(_ id: WindowID) {
        guard let window = windows[id] else { return }
        remember(window)
        removeFromStrip(window)
        windows[id] = nil
    }

    /// A place on a strip that a window (or an app's next window) goes back to.
    private struct Memory {
        var key: StripKey
        var slot: Strip.Slot
    }

    /// Hidden, minimised and closed windows, by window ID.
    private var windowMemory: [WindowID: Memory] = [:]
    /// Where each app's most recently removed window was, for when the app
    /// opens a window again (a Dock click after closing it, or a relaunch).
    private var appMemory: [String: Memory] = [:]

    private func remember(_ window: ManagedWindow) {
        guard let key = window.key, let slot = strips[key]?.slot(of: window.id) else { return }
        let memory = Memory(key: key, slot: slot)
        windowMemory[window.id] = memory
        appMemory[Self.appKey(window)] = memory
    }

    /// Where a returning window belongs, if Monorail remembers. The app's
    /// slot is only used when none of its windows are on that strip, so a
    /// genuinely new second window still opens normally.
    private func memory(for window: ManagedWindow) -> Memory? {
        if let memory = windowMemory.removeValue(forKey: window.id) { return memory }
        let app = Self.appKey(window)
        guard let memory = appMemory[app] else { return nil }
        let strip = strips[memory.key] ?? Strip()
        let appOnStrip = strip.allWindows.contains { windows[$0].map(Self.appKey) == app }
        guard !appOnStrip else { return nil }
        appMemory[app] = nil
        return memory
    }

    private func window(for element: AXUIElement) -> ManagedWindow? {
        if let id = element.windowID, let window = windows[id] { return window }
        return windows.values.first { CFEqual($0.element, element) }
    }

    // MARK: - Dialogs

    /// macOS processes that show panels on behalf of apps (open/save panels,
    /// Quick Look, password prompts…). Their windows are never tiled.
    private static func isSystemUI(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        if bundleID.contains(".xpc.") || bundleID.hasSuffix("UIService") || bundleID.hasSuffix("UIAgent") { return true }
        return [
            "com.apple.appkit.xpc.openAndSavePanelService",
            "com.apple.quicklook.QuickLookUIService",
            "com.apple.CoreServicesUIAgent",
            "com.apple.SecurityAgent",
            "com.apple.UserNotificationCenter",
            "com.apple.ViewBridgeAuxiliary",
            "com.apple.coreservices.uiagent",
        ].contains(bundleID)
    }

    /// Open and save panels, alerts and other dialogs: modal windows, or ones
    /// without minimise and full-screen buttons. They float instead of tiling.
    private static func looksLikeDialog(_ element: AXUIElement) -> Bool {
        if element.bool("AXModal") == true { return true }
        return element.element(kAXMinimizeButtonAttribute) == nil && element.element("AXFullScreenButton") == nil
    }

    /// The tiled window most recently focused, to place dialogs over.
    private var lastTiledFocus: WindowID?
    private var placedDialogs: Set<WindowID> = []

    /// Puts a new dialog (say, a file picker) over the window that opened it,
    /// centred near its top like a sheet, instead of wherever it appeared.
    private func centerDialog(_ element: AXUIElement, pid: pid_t) {
        guard isRunning, !isPaused, element.role == kAXWindowRole, let id = element.windowID, windows[id] == nil,
            !placedDialogs.contains(id), !element.isFullScreen, let frame = element.frame
        else { return }
        placedDialogs.insert(id)
        if placedDialogs.count > 200 { placedDialogs.removeAll() }

        let owner = windows.values
            .filter { $0.pid == pid && $0.key != nil && $0.lastApplied != nil }
            .max { $0.appliedAt < $1.appliedAt }
        guard let parent = (owner ?? lastTiledFocus.flatMap { windows[$0] })?.lastApplied,
            let display = display(containing: CGRect(parent))
        else { return }
        let visible = display.visibleFrame
        var x = parent.midX - Double(frame.width) / 2
        var y = parent.y + min(48, max(parent.height - Double(frame.height), 0) / 2)
        x = min(max(x, Double(visible.minX)), Double(visible.maxX - frame.width))
        y = min(max(y, Double(visible.minY)), Double(visible.maxY - frame.height))
        element.setPosition(CGPoint(x: x, y: y))
    }

    // MARK: - Accessibility notifications

    private static let appNotifications = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
    ]

    private static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXTitleChangedNotification,
    ]

    private var refcon: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    private func observe(_ pid: pid_t) {
        guard observers[pid] == nil else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &created) == .success, let observer = created else { return }
        let app = AXUIElement.application(pid)
        var ok = false
        for name in Self.appNotifications {
            let error = AXObserverAddNotification(observer, app, name as CFString, refcon)
            ok = ok || error == .success || error == .notificationAlreadyRegistered
        }
        guard ok else {
            // The app is probably still launching; `didLaunch` and `didActivate` retry.
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func observeWindow(_ element: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, let observer = observers[pid] else { return }
        for name in Self.windowNotifications {
            AXObserverAddNotification(observer, element, name as CFString, refcon)
        }
    }

    private func stopObserving(_ pid: pid_t) {
        writer.forget(pid: pid)
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        for (id, window) in windows where window.pid == pid { forget(id) }
    }

    fileprivate func handle(_ notification: String, element: AXUIElement) {
        guard isRunning, !isPaused else { return }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)

        switch notification {
        case kAXWindowCreatedNotification:
            let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            if adopt(element, pid: pid, focus: frontmost) {
                layout(animated: true)
            } else {
                centerDialog(element, pid: pid)
            }

        case kAXFocusedWindowChangedNotification:
            focusDidChange(to: element, pid: pid)

        case kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification:
            if let window = window(for: element) {
                forget(window.id)
                layout(animated: true)
            }

        case kAXWindowDeminiaturizedNotification:
            if adopt(element, pid: pid, focus: true) { layout(animated: true) }

        case kAXApplicationHiddenNotification:
            for (id, window) in windows where window.pid == pid { forget(id) }
            layout(animated: true)

        case kAXApplicationShownNotification:
            syncApp(pid, layoutAfter: true)

        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            userMovedOrResized(element, resized: notification == kAXWindowResizedNotification)

        case kAXTitleChangedNotification:
            if let window = window(for: element) {
                window.title = element.title ?? ""
                applyTitleRule(window)
            }
            updateOverlays()

        default:
            break
        }
    }

    private func focusDidChange(to element: AXUIElement, pid: pid_t) {
        // The notification's element is usually the window; fall back to asking the app.
        let windowElement = element.role == kAXWindowRole ? element : AXUIElement.application(pid).focusedWindow
        guard let windowElement, let id = windowElement.windowID else { return }
        if windows[id] == nil {
            if adopt(windowElement, pid: pid, focus: true) {
                layout(animated: true)
            } else {
                centerDialog(windowElement, pid: pid)
            }
            return
        }
        if windows[id]?.key != nil { lastTiledFocus = id }
        if focusHistory.last != id {
            focusHistory.removeAll { $0 == id }
            focusHistory.append(id)
            if focusHistory.count > 30 { focusHistory.removeFirst() }
        }
        if showingDesktop, windows[id]?.key != nil {
            // Going to a window brings everything back.
            showingDesktop = false
            layout(animated: true)
        }
        if let zoomed, zoomed != id {
            // Focusing another window ends the zoom.
            self.zoomed = nil
            layout(animated: true)
        }
        guard swipeDisplay == nil, let window = windows[id], let key = window.key, var strip = strips[key],
            let display = display(for: key)
        else {
            updateOverlays()
            return
        }
        let switchedWorkspace = key != currentKey(display)
        if switchedWorkspace {
            // Focused (e.g. with ⌘Tab) a window parked in another workspace: show that workspace.
            showWorkspace(of: key)
        }
        // Catch apps that resized themselves while Monorail wasn't looking.
        if settings.keepWindowsInPlace, NSEvent.pressedMouseButtons == 0, let target = window.lastApplied,
            let frame = window.element.frame, !Rect(frame).isClose(to: target, tolerance: 2)
        {
            snapBack(window)
        }
        strip.focus(id)
        strip.revealFocused(config: layoutConfig(for: display), viewportWidth: viewport(of: display).width)
        let changed = switchedWorkspace || strip != strips[key]
        strips[key] = strip
        if changed {
            layout(animated: true)
            scheduleSave()
        } else {
            updateOverlays()
        }
    }

    /// The user dragged or resized a tiled window. Resizing changes the
    /// column width; dropping a dragged window moves its column to where it
    /// was dropped. Either way the layout is re-applied after mouse-up.
    private func userMovedOrResized(_ element: AXUIElement, resized: Bool) {
        if settings.rememberFloatingPositions, let window = window(for: element), window.key == nil,
            window.id != scratchpad, let frame = element.frame
        {
            floatingFrames[Self.appKey(window)] = frame
            scheduleSave()
        }
        if !resized, !animator.isRunning, NSEvent.pressedMouseButtons != 0, let window = window(for: element),
            CACurrentMediaTime() - window.appliedAt > 0.3
        {
            onWindowDrag(window.id)
        }
        guard !animator.isRunning, let window = window(for: element),
            CACurrentMediaTime() - window.appliedAt > 0.3, let key = window.key, let applied = window.lastApplied,
            let frame = element.frame
        else { return }
        let actual = Rect(frame)
        guard !actual.isClose(to: applied, tolerance: 2) else { return }

        // No mouse button down means the app moved or resized itself (Firefox
        // does this now and then). Put the window back where the user had it.
        if NSEvent.pressedMouseButtons == 0 {
            if settings.keepWindowsInPlace { snapBack(window) }
            return
        }

        if resized {
            guard abs(actual.width - applied.width) > 4, let display = display(for: key) else { return }
            if settings.resizeHUD { onResizeHUD(frame) }
            // Resizing a tile in a slide: the others follow live, then Monorail offers options.
            if let strip = strips[key], let (c, _) = strip.locate(window.id), strip.columns[c].windows.count > 1,
                strip.columns[c].isTiled || strip.columns[c].isTabbed
            {
                liveResize(window, to: actual, key: key, display: display)
                return
            }
            let fraction = layoutConfig(for: display).fraction(forColumnWidth: actual.width, viewportWidth: viewport(of: display).width)
            strips[key]?.setWidth(fraction, of: window.id)
            if settings.rememberWidths { appWidths[Self.appKey(window)] = fraction }
        } else {
            guard abs(actual.x - applied.x) > 8 || abs(actual.y - applied.y) > 8 else { return }
            swapWhileDragging(window, key: key)
        }
        whenMouseIsUp { [weak self] in self?.finishUserMove(window, resized: resized) }
    }

    /// Set once a drag has swapped tiles, so the drag is one undo step.
    private var dragRecorded: WindowID?

    /// Dragging a window over a slide-mate's tile swaps them right away: the
    /// mate slides over to the other side while the pointer is still down.
    private func swapWhileDragging(_ window: ManagedWindow, key: StripKey) {
        guard var strip = strips[key], let display = display(for: key), let (c, _) = strip.locate(window.id),
            strip.columns[c].windows.count > 1, !strip.columns[c].isTabbed
        else { return }
        let mouse = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let point = CGPoint(x: mouse.x, y: primaryHeight - mouse.y)
        let mates = Set(strip.columns[c].windows).subtracting([window.id])
        guard let target = strip.layout(config: layoutConfig(for: display), viewport: viewport(of: display))
            .first(where: { mates.contains($0.window) && CGRect($0.frame).contains(point) })?.window
        else { return }
        if dragRecorded != window.id {
            recordHistory()
            dragRecorded = window.id
        }
        guard strip.swapTiles(window.id, target) else { return }
        strip.focus(window.id)
        strips[key] = strip
        haptic()
        layout(animated: true, skip: [window.id])
    }

    /// The window being resized by hand, if any.
    private var resizing: WindowID?

    private func liveResize(_ window: ManagedWindow, to actual: Rect, key: StripKey, display: Display) {
        if resizing != window.id {
            recordHistory()
            resizing = window.id
        }
        if var strip = strips[key], let (c, _) = strip.locate(window.id) {
            let column = strip.columnFrames(config: layoutConfig(for: display), viewport: viewport(of: display))[c].frame
            let fraction = (width: actual.width / max(column.width, 1), height: actual.height / max(column.height, 1))
            if strip.resizeTile(window.id, toFraction: fraction) {
                strips[key] = strip
                // Move the others now; the window under the pointer is the user's.
                layout(animated: false, updateOverlays: false, skip: [window.id])
            }
        }
        whenMouseIsUp { [weak self] in self?.finishResize(window) }
    }

    private func finishResize(_ window: ManagedWindow) {
        resizing = nil
        onResizeHUD(nil)
        window.lastApplied = nil
        layout(animated: true)
        scheduleSave()
        guard settings.resizeAssist, let key = window.key, let strip = strips[key],
            let (c, _) = strip.locate(window.id), let frame = window.element.frame
        else { return }
        onResized(window.id, frame, window.appName, strip.columns[c].windows.count > 1)
    }

    /// Called after the user resizes a window in a slide, to offer options.
    var onResized: (WindowID, CGRect, String, Bool) -> Void = { _, _, _, _ in }

    /// Resize assist: give the window a slide of its own.
    func giveOwnSlide(_ id: WindowID) {
        guard let key = windows[id]?.key, var strip = strips[key] else { return }
        recordHistory()
        strip.focus(id)
        strip.expel()
        commit(strip, key)
    }

    /// Resize assist: keep the window and move its slide-mates to a new slide.
    func moveOthersOut(keeping id: WindowID) {
        guard let key = windows[id]?.key, var strip = strips[key] else { return }
        recordHistory()
        strip.moveOthersOut(keeping: id)
        commit(strip, key)
    }

    private func commit(_ strip: Strip, _ key: StripKey) {
        var strip = strip
        if let display = display(for: key) {
            strip.revealFocused(config: layoutConfig(for: display), viewportWidth: viewport(of: display).width)
        }
        strips[key] = strip
        layout(animated: true)
        scheduleSave()
    }

    // MARK: - Undo

    private struct Snapshot {
        var strips: [StripKey: Strip]
        var activeWorkspace: [ScreenKey: Int]
    }

    private var history: [Snapshot] = []

    /// Saves the layout before a change, so it can be undone.
    private func recordHistory() {
        history.append(Snapshot(strips: strips, activeWorkspace: activeWorkspace))
        if history.count > 40 { history.removeFirst(history.count - 40) }
        future.removeAll()
    }

    /// Changes undone, to redo.
    private var future: [Snapshot] = []
    var canRedo: Bool { !future.isEmpty }

    func redo() {
        guard isRunning, !isPaused, let snapshot = future.popLast() else {
            onNotice("Nothing to redo")
            return
        }
        history.append(Snapshot(strips: strips, activeWorkspace: activeWorkspace))
        restore(snapshot)
        onNotice("Redid layout change")
    }

    var canUndo: Bool { !history.isEmpty }

    /// Puts the layout back the way it was before the last change. Windows
    /// that closed since are dropped; windows opened since are placed anew.
    func undo() {
        guard isRunning, !isPaused, let snapshot = history.popLast() else {
            onNotice("Nothing to undo")
            return
        }
        onNotice("Undid last layout change")
        future.append(Snapshot(strips: strips, activeWorkspace: activeWorkspace))
        restore(snapshot)
    }

    /// Puts a saved arrangement back: windows that closed since are dropped,
    /// ones opened since are placed anew.
    private func restore(_ snapshot: Snapshot) {
        strips = snapshot.strips
        activeWorkspace = snapshot.activeWorkspace
        var placed = Set<WindowID>()
        for (key, var strip) in strips {
            for id in strip.allWindows where windows[id] == nil { strip.remove(id) }
            strips[key] = strip
            for id in strip.allWindows {
                windows[id]?.key = key
                placed.insert(id)
            }
        }
        for window in windows.values where window.key != nil && !placed.contains(window.id) {
            window.key = nil
            if let frame = window.element.frame, let display = display(containing: frame) ?? displays.first {
                place(window, in: currentKey(display), display: display, focus: false, restoring: false)
            }
        }
        layout(animated: true)
        scheduleSave()
        onStateChange()
    }

    /// Recent snap-backs per window, so Monorail never fights an app that
    /// insists on its own size (it gives up after a few tries).
    private var snapBacks: [WindowID: [CFTimeInterval]] = [:]
    private var snapBackTimers: [WindowID: Timer] = [:]

    private func snapBack(_ window: ManagedWindow) {
        snapBackTimers[window.id]?.invalidate()
        // Wait for the app to finish whatever it is doing, then restore once.
        snapBackTimers[window.id] = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            guard let self, self.isRunning, !self.isPaused, self.windows[window.id] === window,
                let target = window.lastApplied, let frame = window.element.frame,
                !window.element.isMinimized, !window.element.isFullScreen,
                !Rect(frame).isClose(to: target, tolerance: 2)
            else { return }
            let now = CACurrentMediaTime()
            let recent = (self.snapBacks[window.id] ?? []).filter { now - $0 < 10 }
            guard recent.count < 4 else {
                log.info("Window \(window.id) keeps resizing itself; leaving it be")
                return
            }
            self.snapBacks[window.id] = recent + [now]
            self.apply(target, to: window.id, sizeChanged: true)
        }
    }

    private func finishUserMove(_ window: ManagedWindow, resized: Bool) {
        guard let key = window.key, var strip = strips[key], let display = display(for: key) else { return }
        if dragRecorded != window.id { recordHistory() }
        dragRecorded = nil
        if !resized, let frame = window.element.frame, let source = strip.locate(window.id)?.column {
            let frames = strip.columnFrames(config: layoutConfig(for: display), viewport: viewport(of: display))
            let dropX = frame.midX
            if let target = frames.indices.first(where: { frames[$0].frame.minX <= dropX && dropX < frames[$0].frame.maxX }),
                target != source, strip.columns[target].pin == nil
            {
                strip.focus(window.id)
                if strip.columns[source].windows.count > 1 { strip.expel() }
                if let from = strip.locate(window.id)?.column { strip.moveColumn(from: from, to: target) }
            }
        }
        window.lastApplied = nil
        strip.focus(window.id)
        strip.revealFocused(config: layoutConfig(for: display), viewportWidth: viewport(of: display).width)
        strips[key] = strip
        layout(animated: true)
        scheduleSave()
    }

    private func whenMouseIsUp(_ action: @escaping () -> Void) {
        mouseUpTimer?.invalidate()
        mouseUpTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard NSEvent.pressedMouseButtons == 0 else { return }
            timer.invalidate()
            self?.mouseUpTimer = nil
            action()
        }
    }

    // MARK: - Workspace notifications

    private func registerWorkspaceNotifications() {
        let workspace = NSWorkspace.shared.notificationCenter
        func on(
            _ name: Notification.Name, in center: NotificationCenter? = nil,
            _ block: @escaping (Notification) -> Void
        ) {
            let center = center ?? workspace
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main, using: block))
        }
        func app(_ note: Notification) -> NSRunningApplication? {
            note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        }

        on(NSWorkspace.didLaunchApplicationNotification) { [weak self] note in
            guard let pid = app(note)?.processIdentifier else { return }
            for delay in [0.3, 1.0, 2.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard let self, self.isRunning, !self.isPaused else { return }
                    self.syncApp(pid, layoutAfter: true)
                }
            }
        }
        on(NSWorkspace.didTerminateApplicationNotification) { [weak self] note in
            guard let self, let pid = app(note)?.processIdentifier else { return }
            self.stopObserving(pid)
            self.layout(animated: true)
        }
        on(NSWorkspace.didActivateApplicationNotification) { [weak self] note in
            guard let self, self.isRunning, !self.isPaused, let pid = app(note)?.processIdentifier else { return }
            self.syncApp(pid, layoutAfter: true)
            if let element = AXUIElement.application(pid).focusedWindow {
                self.focusDidChange(to: element, pid: pid)
            }
        }
        on(NSWorkspace.didHideApplicationNotification) { [weak self] note in
            guard let self, let pid = app(note)?.processIdentifier else { return }
            for (id, window) in self.windows where window.pid == pid { self.forget(id) }
            self.layout(animated: true)
        }
        on(NSWorkspace.didUnhideApplicationNotification) { [weak self] note in
            guard let self, let pid = app(note)?.processIdentifier else { return }
            self.syncApp(pid, layoutAfter: true)
        }
        on(NSWorkspace.activeSpaceDidChangeNotification) { [weak self] _ in self?.scheduleSync(after: 0.15) }
        on(NSWorkspace.didWakeNotification) { [weak self] _ in self?.scheduleSync(after: 1.0) }
        on(NSWorkspace.screensDidWakeNotification) { [weak self] _ in self?.scheduleSync(after: 1.0) }
        on(NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] _ in self?.scheduleSync(after: 1.0) }
        on(NSWorkspace.willSleepNotification) { [weak self] _ in
            guard let self else { return }
            self.animator.finishNow()
            if self.settings.autoSnapshot { self.saveSnapshot(named: Self.lastSessionName, quiet: true) }
            self.saveState()
        }
        on(NSApplication.didChangeScreenParametersNotification, in: .default) { [weak self] _ in
            self?.scheduleSync(after: 0.5)
        }
    }

    private func scheduleSync(after delay: TimeInterval) {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in self?.sync() }
    }

    // MARK: - Restoring windows

    /// Pulls parked windows fully back onto their display, leaving others where they are.
    private func restoreAll() {
        for window in windows.values where window.key != nil {
            guard let frame = window.element.frame,
                let display = window.key.flatMap(display(for:)) ?? display(containing: frame)
            else { continue }
            let visible = display.visibleFrame
            var target = frame
            target.size.width = min(target.width, visible.width)
            target.size.height = min(target.height, visible.height)
            target.origin.x = min(max(target.minX, visible.minX), visible.maxX - target.width)
            target.origin.y = min(max(target.minY, visible.minY), visible.maxY - target.height)
            if target != frame { window.element.setFrame(target) }
            window.lastApplied = nil
        }
    }

    // MARK: - Persistence

    private struct SavedState: Codable {
        var strips: [StripKey: Strip]
        var activeWorkspace: [ScreenKey: Int]?
        var names: [WindowID: String]?
        /// Every strip by display and workspace, described by window fingerprints,
        /// to restore after the Mac restarts.
        var session: [SessionStrip]?
        var activeProfile: Int?
        var profileWorkspaces: [Int: [ScreenKey: Int]]?
        var marks: [String: WindowID]?
        var scratchpad: WindowID?
        /// Apps that need a whole slide (stored under a new name: 0.5.0 also
        /// listed apps that only needed a little more room).
        var wholeSlideApps: [String]?
        var sticky: [WindowID]?
        var appWidths: [String: Double]?
        var floatingFrames: [String: CGRect]?
        var projectHomes: [String: StripKey]?
    }

    struct SessionStrip: Codable {
        var display: String
        var workspace: Int
        var columns: [SavedColumn]
    }

    private static var stateURL: URL { SettingsStore.directory.appendingPathComponent("layout.json") }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in self?.saveState() }
    }

    /// Window IDs survive a restart of Monorail (not of the apps), so saving
    /// the strips lets an update or relaunch pick up exactly where it left off.
    private func saveState() {
        let session = strips.filter { !$0.value.isEmpty }.map { key, strip in
            SessionStrip(
                display: key.display, workspace: key.workspace,
                columns: strip.columns.map { SavedColumn($0, fingerprint: fingerprint(of:)) })
        }
        let state = SavedState(
            strips: strips.filter { !$0.value.isEmpty }, activeWorkspace: activeWorkspace,
            names: names.filter { windows[$0.key] != nil }, session: session,
            activeProfile: activeProfile, profileWorkspaces: profileWorkspaces, marks: marks, scratchpad: scratchpad,
            wholeSlideApps: roomyApps.sorted(), sticky: Array(stickyWindows), appWidths: appWidths,
            floatingFrames: floatingFrames,
            projectHomes: projectHomes)
        do {
            try FileManager.default.createDirectory(at: SettingsStore.directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: Self.stateURL, options: .atomic)
        } catch {
            log.error("Saving layout failed: \(error.localizedDescription)")
        }
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: Self.stateURL),
            let state = try? JSONDecoder().decode(SavedState.self, from: data)
        else { return }
        strips = state.strips
        activeWorkspace = state.activeWorkspace ?? [:]
        names = state.names ?? [:]
        activeProfile = min(state.activeProfile ?? 0, max(settings.profiles.count - 1, 0))
        profileWorkspaces = state.profileWorkspaces ?? [:]
        marks = state.marks ?? [:]
        scratchpad = state.scratchpad
        roomyApps = Set(state.wholeSlideApps ?? [])
        stickyWindows = Set(state.sticky ?? [])
        appWidths = state.appWidths ?? [:]
        floatingFrames = state.floatingFrames ?? [:]
        projectHomes = state.projectHomes ?? [:]
        lastSession = state.session ?? []
        lastSessionLoaded = Date()
        savedLayouts = (try? Data(contentsOf: Self.layoutsURL))
            .flatMap { try? JSONDecoder().decode([SavedLayout].self, from: $0) } ?? []
    }

    // MARK: - Restoring after a restart

    private var lastSession: [SessionStrip] = []
    private var lastSessionLoaded = Date.distantPast

    func fingerprint(of id: WindowID) -> WindowFingerprint? {
        windows[id].map { WindowFingerprint(app: Self.appKey($0), title: $0.title) }
    }

    /// Puts a window whose ID MacSlider doesn't know back where an identical
    /// window (same app and title) sat last session. Only for a while after
    /// launch, while apps reopen their windows.
    private func placeFromLastSession(_ window: ManagedWindow, display: Display, focus: Bool) -> Bool {
        guard !lastSession.isEmpty, Date().timeIntervalSince(lastSessionLoaded) < 15 * 60,
            strips.values.allSatisfy({ !$0.contains(window.id) }),
            let mark = fingerprint(of: window.id), !mark.title.isEmpty
        else { return false }
        for (s, saved) in lastSession.enumerated() where saved.display == display.uuid {
            for (c, column) in saved.columns.enumerated() {
                guard let row = column.windows.firstIndex(of: mark) else { continue }
                let workspace = saved.workspace / Self.profileStride * Self.profileStride
                    + min(saved.workspace % Self.profileStride, workspaceLimit - 1)
                let key = StripKey(screen: currentKey(display).screen, workspace: workspace)
                var strip = strips[key] ?? Strip()
                let mates = column.windows.enumerated().filter { $0.offset != row }.compactMap { mate in
                    strip.allWindows.first { fingerprint(of: $0) == mate.element }
                }
                let slot = Strip.Slot(
                    columnIndex: min(c, strip.columns.count), row: row, mates: mates, width: column.width,
                    arrangement: column.arrangement, isCustom: true)
                strip.restore(window.id, to: slot, focus: focus && key == currentKey(display))
                strips[key] = strip
                window.key = key
                lastSession[s].columns[c].windows.remove(at: row)
                scheduleSave()
                return true
            }
        }
        return false
    }

    // MARK: - Saved layouts

    private(set) var savedLayouts: [SavedLayout] = []
    private static var layoutsURL: URL { SettingsStore.directory.appendingPathComponent("saved-layouts.json") }

    /// Called after saved layouts or snapshots change on disk (for iCloud sync).
    var onLayoutsSaved: () -> Void = {}

    private func writeLayouts() {
        try? FileManager.default.createDirectory(at: SettingsStore.directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(savedLayouts).write(to: Self.layoutsURL, options: .atomic)
        onLayoutsSaved()
    }

    /// Reads saved layouts again after an import or a sync replaced them.
    func reloadLayouts() {
        savedLayouts = (try? Data(contentsOf: Self.layoutsURL))
            .flatMap { try? JSONDecoder().decode([SavedLayout].self, from: $0) } ?? []
        onStateChange()
    }

    /// Saves every workspace of the active display under `name`.
    func saveLayout(named name: String) {
        guard let (display, _) = activeContext() else { return }
        let screen = currentKey(display).screen
        var workspaces: [Int: [SavedColumn]] = [:]
        for (key, strip) in strips
        where key.screen == screen && key.workspace / Self.profileStride == activeProfile && !strip.isEmpty {
            workspaces[key.workspace - base] = strip.columns.map { SavedColumn($0, fingerprint: fingerprint(of:)) }
        }
        savedLayouts.removeAll { $0.name == name }
        savedLayouts.append(SavedLayout(name: name, workspaces: workspaces))
        savedLayouts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        writeLayouts()
        onNotice("Saved layout “\(name)”")
    }

    /// Adds a layout someone shared (a .monorail file).
    func importLayout(_ layout: SavedLayout) {
        savedLayouts.removeAll { $0.name == layout.name }
        savedLayouts.append(layout)
        savedLayouts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        writeLayouts()
        onStateChange()
    }

    func deleteLayout(named name: String) {
        savedLayouts.removeAll { $0.name == name }
        writeLayouts()
    }

    /// Arranges the open windows of the active display like `name`: matching
    /// windows go to their saved slides; the rest stay, after them.
    func applyLayout(named name: String) {
        guard isRunning, !isPaused, let saved = savedLayouts.first(where: { $0.name == name }),
            let (display, _) = activeContext()
        else { return }
        recordHistory()
        let screen = currentKey(display).screen
        let candidates = windows.values
            .filter { $0.key?.screen == screen }
            .compactMap { window in fingerprint(of: window.id).map { (id: window.id, fingerprint: $0) } }
        var used = Set<WindowID>()
        var placed: [Int: [Column]] = [:]
        for (workspace, columns) in saved.workspaces.sorted(by: { $0.key < $1.key }) where workspace < workspaceLimit {
            placed[workspace] = LayoutMatcher.columns(for: columns, windows: candidates, used: &used)
        }
        let focused = focusedWindowID()
        for workspace in 0..<workspaceLimit {
            let key = StripKey(screen: screen, workspace: base + workspace)
            var strip = strips[key] ?? Strip()
            let leftover: [Column] = strip.columns.compactMap { column in
                var column = column
                column.windows.removeAll { used.contains($0) }
                column.active = min(column.active, max(column.windows.count - 1, 0))
                return column.windows.isEmpty ? nil : column
            }
            strip.replaceColumns((placed[workspace] ?? []) + leftover, keepingFocusOn: focused)
            strip.revealFocused(config: layoutConfig(for: display), viewportWidth: viewport(of: display).width)
            strips[key] = strip
            for id in strip.allWindows { windows[id]?.key = key }
        }
        layout(animated: true)
        scheduleSave()
        onStateChange()
        onNotice(used.isEmpty ? "No open windows match “\(name)”" : "Applied layout “\(name)”")
    }

    // MARK: - Marks

    /// Windows marked with a letter, to jump straight back to.
    private var marks: [String: WindowID] = [:]

    func setMark(_ letter: String) {
        guard let id = focusedWindowID(), windows[id] != nil else {
            onNotice("No window to mark")
            return
        }
        marks = marks.filter { $0.value != id }
        marks[letter] = id
        scheduleSave()
        onNotice("Marked “\(letter)” · ⌃⌥; then \(letter) jumps back")
    }

    func jumpToMark(_ letter: String) {
        guard let id = marks[letter], windows[id] != nil else {
            onNotice("No window marked “\(letter)”")
            return
        }
        if windows[id]?.key == nil {
            focus(id, warpMouse: true)
        } else {
            focusAndReveal(id)
        }
    }

    // MARK: - Scratchpad

    /// One floating window that drops in over everything and hides again.
    private var scratchpad: WindowID?
    private var scratchpadShown = false

    private func makeScratchpad() {
        guard let id = focusedWindowID(), let window = windows[id] ?? adoptFocused(id) else {
            onNotice("Focus a window to make it the scratchpad")
            return
        }
        if window.key != nil {
            removeFromStrip(window)
            window.lastApplied = nil
            layout(animated: true)
        }
        scratchpad = id
        showScratchpad(window)
        scheduleSave()
        onNotice("Scratchpad set · ⌃⌥` shows and hides it")
    }

    private func toggleScratchpad() {
        guard let id = scratchpad, let window = windows[id], window.element.isAlive else {
            onNotice("No scratchpad yet · ⌃⌥⇧` makes the focused window one")
            return
        }
        if scratchpadShown && focusedWindowID() == id {
            hideScratchpad(window)
        } else {
            showScratchpad(window)
        }
    }

    private func showScratchpad(_ window: ManagedWindow) {
        guard let display = displayUnderMouse() ?? displays.first else { return }
        let area = display.visibleFrame
        window.element.setFrame(CGRect(
            x: area.minX + area.width * 0.15, y: area.minY + area.height * 0.08,
            width: area.width * 0.7, height: area.height * 0.8))
        scratchpadShown = true
        focus(window.id, warpMouse: false)
    }

    private func hideScratchpad(_ window: ManagedWindow) {
        let frame = window.element.frame ?? .zero
        guard let display = display(containing: frame) ?? displays.first else { return }
        window.element.setPosition(CGPoint(x: display.frame.maxX - 1, y: display.frame.maxY - 1))
        scratchpadShown = false
        if let (_, key) = activeContext(), let target = strips[key]?.focusedWindow { focus(target, warpMouse: false) }
    }

    // MARK: - App pairs

    /// An app pair made from the slide holding `id`: its apps, in order, and its layout.
    func appPair(from id: WindowID) -> AppPair? {
        guard let key = windows[id]?.key, let strip = strips[key], let (c, _) = strip.locate(id) else { return nil }
        let column = strip.columns[c]
        var bundleIDs: [String] = []
        for window in column.windows.compactMap({ windows[$0] }) {
            if let bundleID = window.bundleID, !bundleIDs.contains(bundleID) { bundleIDs.append(bundleID) }
        }
        guard bundleIDs.count > 1 else { return nil }
        let names = column.windows.compactMap { windows[$0]?.appName }
        var unique: [String] = []
        for name in names where !unique.contains(name) { unique.append(name) }
        return AppPair(
            name: unique.joined(separator: " + "), bundleIDs: bundleIDs,
            arrangement: column.isTabbed ? .columns : column.arrangement, customRows: column.customRows)
    }

    private var pendingPair: String?

    /// Opens the pair's apps (launching any that aren't running) and puts one
    /// window of each in a new slide.
    func openPair(_ pair: AppPair, launch: Bool = true) {
        guard isRunning, !isPaused else { return }
        for bundleID in pair.bundleIDs
        where launch && NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
        pendingPair = pair.id
        // Apps that are launching need a moment to open their windows.
        for delay in [0.05, 1.0, 2.5, 5.0, 8.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.gatherPair(pair, last: delay == 8.0)
            }
        }
    }

    private func gatherPair(_ pair: AppPair, last: Bool) {
        guard pendingPair == pair.id, isRunning, !isPaused, let (_, key) = activeContext() else { return }
        for bundleID in pair.bundleIDs {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                syncApp(app.processIdentifier, layoutAfter: false)
            }
        }
        var ids: [WindowID] = []
        for bundleID in pair.bundleIDs {
            let candidates = windows.values.filter { $0.bundleID == bundleID && $0.key != nil && !ids.contains($0.id) }
            if let pick = candidates.first(where: { $0.key == key })
                ?? candidates.first(where: { $0.key?.screen == key.screen }) ?? candidates.first
            {
                ids.append(pick.id)
            }
        }
        guard ids.count == pair.bundleIDs.count || (last && ids.count > 1) else {
            if last {
                pendingPair = nil
                onNotice("Couldn’t find windows for “\(pair.name)”")
            }
            return
        }
        pendingPair = nil
        recordHistory()
        for id in ids { if let window = windows[id] { removeFromStrip(window) } }
        var strip = strips[key] ?? Strip()
        strip.insertSlide(
            ids, width: 1, arrangement: pair.arrangement, position: .afterFocused, focus: true, custom: true,
            rows: pair.customRows)
        for id in ids { windows[id]?.key = key }
        commit(strip, key)
        if let first = ids.first { focus(first, warpMouse: true) }
        onStateChange()
        onNotice("Opened “\(pair.name)”")
    }

    // MARK: - Parking workspaces

    /// Parked workspaces: their windows wait minimised in the Dock and come
    /// back to exactly the same slides.
    private var parked: [StripKey: (strip: Strip, elements: [WindowID: AXUIElement])] = [:]

    private func workspaceKey(_ index: Int) -> StripKey? {
        guard let (_, current) = activeContext() else { return nil }
        return StripKey(screen: current.screen, workspace: base + index)
    }

    func isParked(_ index: Int) -> Bool { workspaceKey(index).map { parked[$0] != nil } ?? false }

    func parkWorkspace(_ index: Int) {
        guard isRunning, !isPaused, let key = workspaceKey(index), parked[key] == nil,
            let strip = strips[key], !strip.isEmpty
        else { return }
        var elements: [WindowID: AXUIElement] = [:]
        for id in strip.allWindows { if let window = windows[id] { elements[id] = window.element } }
        parked[key] = (strip, elements)
        for element in elements.values { element.set(kAXMinimizedAttribute, kCFBooleanTrue) }
        onStateChange()
        onNotice("Parked “\(settings.workspaceName(index))” · \(elements.count) windows in the Dock")
    }

    func unparkWorkspace(_ index: Int) {
        guard isRunning, !isPaused, let key = workspaceKey(index), let entry = parked.removeValue(forKey: key)
        else { return }
        // Windows closed meanwhile, or already brought back by hand, are skipped.
        let returning = entry.elements.filter { id, element in windows[id] == nil && element.isAlive }
        var columns = entry.strip.columns.compactMap { column -> Column? in
            var column = column
            column.windows.removeAll { returning[$0] == nil }
            column.active = min(column.active, max(column.windows.count - 1, 0))
            return column.windows.isEmpty ? nil : column
        }
        columns += strips[key]?.columns ?? []
        var strip = strips[key] ?? Strip()
        strip.replaceColumns(columns, keepingFocusOn: entry.strip.focusedWindow)
        strips[key] = strip
        for id in returning.keys { windowMemory[id] = nil }
        showWorkspace(of: key)
        // Each window finds its place on the strip as it comes back (see `adopt`).
        for element in returning.values { element.set(kAXMinimizedAttribute, kCFBooleanFalse) }
        layout(animated: true)
        scheduleSave()
        onStateChange()
    }

    // MARK: - Attention

    /// Apps showing a badge in the Dock (unread mail, messages…), by name.
    private(set) var attentionApps: Set<String> = []
    private var attentionTimer: Timer?

    private func refreshAttention() {
        guard settings.attentionMarkers, isRunning,
            let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else {
            if !attentionApps.isEmpty {
                attentionApps = []
                onStateChange()
            }
            return
        }
        let pid = dock.processIdentifier
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var names = Set<String>()
            for list in AXUIElement.application(pid).elements(kAXChildrenAttribute) where list.role == kAXListRole {
                for item in list.elements(kAXChildrenAttribute) {
                    if let label = item.string("AXStatusLabel"), !label.isEmpty, let title = item.title {
                        names.insert(title)
                    }
                }
            }
            DispatchQueue.main.async {
                guard let self, names != self.attentionApps else { return }
                self.attentionApps = names
                self.onStateChange()
            }
        }
    }

    // MARK: - Windows that won't shrink

    /// Apps whose windows can't shrink to share a slide (App Store, some
    /// settings windows): they always get a slide of their own.
    private var roomyApps: Set<String> = []
    private var fitChecks: [WindowID: Timer] = [:]
    /// When each window was last given the room it insisted on.
    private var fittedAt: [WindowID: CFTimeInterval] = [:]

    /// After Monorail sizes a window, check the app accepted the size.
    private func scheduleFitCheck(_ id: WindowID) {
        fitChecks[id]?.invalidate()
        fitChecks[id] = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.fitChecks[id] = nil
            self.checkFit(id)
        }
    }

    /// A window bigger than its tile in a shared slide overlaps its
    /// neighbours or spills off screen. Its slide-mates make room for it, down
    /// to what it needs; only a window that needs nearly the whole slide gets
    /// a slide of its own.
    private func checkFit(_ id: WindowID) {
        guard isRunning, !isPaused, !animator.isRunning, NSEvent.pressedMouseButtons == 0, resizing == nil,
            let window = windows[id], let key = window.key, var strip = strips[key], let display = display(for: key),
            let (c, _) = strip.locate(id), strip.columns[c].windows.count > 1, !strip.columns[c].isTabbed,
            let target = window.lastApplied, let frame = window.element.frame
        else { return }
        let tooWide = Double(frame.width) > target.width + 24
        let tooTall = Double(frame.height) > target.height + 24
        guard tooWide || tooTall else { return }
        let column = strip.columnFrames(config: layoutConfig(for: display), viewport: viewport(of: display))[c].frame
        let fraction = (
            width: min(Double(frame.width), column.width) / max(column.width, 1),
            height: min(Double(frame.height), column.height) / max(column.height, 1))
        let needsWholeSlide = (tooWide && fraction.width > 0.8) || (tooTall && fraction.height > 0.8)
        let focused = strip.focusedWindow
        // If a slide-mate was just made room for too, the two can't both fit.
        let now = CACurrentMediaTime()
        let mateJustFitted = strip.columns[c].windows.contains { $0 != id && now - (fittedAt[$0] ?? 0) < 3 }
        if !needsWholeSlide, !mateJustFitted, strip.resizeTile(id, toFraction: fraction) {
            fittedAt[id] = now
            // Shrink the others instead, keeping this window at the size it insists on.
            if let focused { strip.focus(focused) }
            for mate in strip.columns[c].windows { windows[mate]?.lastApplied = nil }
            commit(strip, key)
            return
        }
        roomyApps.insert(Self.appKey(window))
        strip.moveWindow(id, toNewColumnAt: c + 1, width: 1)
        if let focused { strip.focus(focused) }
        window.lastApplied = nil
        commit(strip, key)
        onNotice("\(window.appName) needs the whole screen, so it has a slide of its own")
    }

    // MARK: - Focus mode

    /// Dims everything but the slide you're working in, for a while.
    private(set) var isFocusMode = false
    private var focusTimer: Timer?
    private(set) var focusEnds: Date?

    func setFocusMode(_ on: Bool) {
        guard on != isFocusMode else { return }
        isFocusMode = on
        focusTimer?.invalidate()
        focusTimer = nil
        focusEnds = nil
        if on, settings.focusMinutes > 0 {
            let minutes = settings.focusMinutes
            focusEnds = Date().addingTimeInterval(Double(minutes) * 60)
            focusTimer = Timer.scheduledTimer(withTimeInterval: Double(minutes) * 60, repeats: false) { [weak self] _ in
                self?.setFocusMode(false)
                self?.onNotice("Focus session done · \(minutes) minutes")
            }
        }
        updateOverlays()
        onStateChange()
        if on {
            onNotice(settings.focusMinutes > 0 ? "Focus mode · \(settings.focusMinutes) minutes" : "Focus mode on")
            onUsage(.focusSession)
        } else if focusEnds == nil {
            onNotice("Focus mode off")
        }
    }

    // MARK: - Title rules

    /// Windows already handled by a title rule.
    private var titleRuled: Set<WindowID> = []

    /// Titles often arrive late (a browser tab loads "Meet" after the window
    /// opens): apply a title rule the first time one matches.
    private func applyTitleRule(_ window: ManagedWindow) {
        gatherProject(window)
        guard isRunning, !isPaused, !titleRuled.contains(window.id),
            let rule = settings.rule(for: window.bundleID, title: window.title), rule.isTitleRule
        else { return }
        titleRuled.insert(window.id)
        if rule.float, window.key != nil {
            removeFromStrip(window)
            window.lastApplied = nil
            if let frame = window.element.frame, let display = display(containing: frame) {
                let visible = display.visibleFrame
                let size = CGSize(width: min(frame.width, visible.width * 0.8), height: min(frame.height, visible.height * 0.8))
                window.element.setFrame(CGRect(
                    x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                    width: size.width, height: size.height))
            }
            layout(animated: true)
        } else if rule.ownSlide == true, let key = window.key, var strip = strips[key],
            let (c, _) = strip.locate(window.id), strip.columns[c].windows.count > 1
        {
            let focused = strip.focusedWindow
            strip.moveWindow(window.id, toNewColumnAt: c + 1, width: 1)
            if let focused { strip.focus(focused) }
            commit(strip, key)
        } else if let home = rule.workspace, home >= 0, home < workspaceLimit, let key = window.key,
            key.workspace != base + home
        {
            moveWindow(window.id, toWorkspace: home)
        }
    }

    // MARK: - Peek

    /// Where the strip was before a peek, to slide back to.
    private var peekOrigin: (key: StripKey, scroll: Double)?

    /// Slides the strip to show column `index` without focusing anything.
    func peek(column index: Int, displayUUID: String) {
        guard isRunning, !isPaused, let display = displays.first(where: { $0.uuid == displayUUID }) else { return }
        let key = currentKey(display)
        guard var strip = strips[key], strip.columns.indices.contains(index) else { return }
        if peekOrigin == nil { peekOrigin = (key, strip.scroll) }
        let width = viewport(of: display).width
        let config = layoutConfig(for: display)
        let offsets = strip.columnOffsets(config: config, viewportWidth: width)
        let target = offsets[index] - (width - strip.width(ofColumn: index, config: config, viewportWidth: width)) / 2
        strip.scroll(by: target - strip.scroll, config: config, viewportWidth: width)
        strips[key] = strip
        layout(animated: true)
    }

    /// Ends a peek: back where you were, or stay there if `keep`.
    func endPeek(keep: Bool = false) {
        guard let origin = peekOrigin else { return }
        peekOrigin = nil
        guard !keep, var strip = strips[origin.key], let display = display(for: origin.key) else { return }
        let width = viewport(of: display).width
        strip.scroll(by: origin.scroll - strip.scroll, config: layoutConfig(for: display), viewportWidth: width)
        strips[origin.key] = strip
        layout(animated: true)
    }

    var isPeeking: Bool { peekOrigin != nil }

    // MARK: - Snapshots

    var snapshots: [SavedLayout] { savedLayouts.filter { $0.isSnapshot == true } }
    var layouts: [SavedLayout] { savedLayouts.filter { $0.isSnapshot != true } }

    /// Saves every workspace of every profile on every display, and the apps
    /// that are open, to bring the whole session back later.
    static let lastSessionName = "Last session"

    func saveSnapshot(named name: String, quiet: Bool = false) {
        var workspaces: [Int: [SavedColumn]] = [:]
        for (key, strip) in strips where !strip.isEmpty {
            workspaces[key.workspace, default: []] += strip.columns.map { SavedColumn($0, fingerprint: fingerprint(of:)) }
        }
        var apps: [String] = []
        for window in windows.values {
            if let bundleID = window.bundleID, !apps.contains(bundleID) { apps.append(bundleID) }
        }
        savedLayouts.removeAll { $0.name == name }
        savedLayouts.append(SavedLayout(name: name, workspaces: workspaces, apps: apps.sorted(), isSnapshot: true,
                                        savedAt: Date()))
        savedLayouts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        writeLayouts()
        onStateChange()
        if !quiet { onNotice("Snapshot “\(name)” · \(workspaces.count) workspaces, \(apps.count) apps") }
    }

    /// Relaunches a snapshot's apps, then puts their windows back as they
    /// were, retrying while the apps open their windows.
    func restoreSnapshot(named name: String) {
        guard isRunning, !isPaused, let snapshot = savedLayouts.first(where: { $0.name == name && $0.isSnapshot == true })
        else { return }
        var launched = 0
        for bundleID in snapshot.apps ?? []
        where NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { continue }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            launched += 1
        }
        onNotice(launched > 0 ? "Restoring “\(name)” · opening \(launched) apps…" : "Restoring “\(name)”")
        recordHistory()
        for delay in launched > 0 ? [0.2, 3.0, 7.0, 12.0] : [0.05] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.sync()
                self?.arrange(snapshot)
            }
        }
    }

    /// Puts open windows where a snapshot had them, on the displays that are
    /// connected (a missing display's workspaces go to the first one).
    private func arrange(_ snapshot: SavedLayout) {
        guard isRunning, !isPaused, let first = displays.first else { return }
        let screen = currentKey(first).screen
        let candidates = windows.values
            .filter { $0.key != nil }
            .compactMap { window in fingerprint(of: window.id).map { (id: window.id, fingerprint: $0) } }
        var used = Set<WindowID>()
        var placed: [Int: [Column]] = [:]
        for (workspace, columns) in snapshot.workspaces.sorted(by: { $0.key < $1.key }) {
            placed[workspace] = LayoutMatcher.columns(for: columns, windows: candidates, used: &used)
        }
        guard !used.isEmpty else { return }
        for id in used { if let window = windows[id] { removeFromStrip(window) } }
        for (workspace, columns) in placed where !columns.isEmpty {
            let key = StripKey(screen: screen, workspace: workspace)
            var strip = strips[key] ?? Strip()
            strip.replaceColumns(columns + strip.columns, keepingFocusOn: focusedWindowID())
            strip.revealFocused(config: layoutConfig(for: first), viewportWidth: viewport(of: first).width)
            strips[key] = strip
            for id in strip.allWindows { windows[id]?.key = key }
        }
        layout(animated: true)
        scheduleSave()
        onStateChange()
    }

    // MARK: - For Insights

    /// The apps sharing each slide on the screens in view, for counting pairs.
    func slideApps() -> [[String]] {
        displays.compactMap { strips[currentKey($0)] }.flatMap(\.columns).compactMap { column in
            let apps = Set(column.windows.compactMap { windows[$0]?.bundleID })
            return apps.count > 1 ? apps.sorted() : nil
        }
    }

    var slideCount: Int { displays.compactMap { strips[currentKey($0)]?.columns.count }.reduce(0, +) }

    // MARK: - Windows on every workspace

    /// Windows that follow you to every workspace (chat, music).
    private(set) var stickyWindows: Set<WindowID> = []

    func isSticky(_ id: WindowID) -> Bool { stickyWindows.contains(id) }

    func toggleSticky(_ id: WindowID) {
        guard let window = windows[id] else { return }
        if stickyWindows.remove(id) == nil {
            stickyWindows.insert(id)
            onNotice("\(window.appName) now follows you to every workspace")
        } else {
            onNotice("\(window.appName) stays in this workspace")
        }
        scheduleSave()
        onStateChange()
    }

    /// Moves sticky windows on `key`'s screen into the workspace being shown,
    /// at the end of its strip.
    private func carryStickyWindows(to key: StripKey) {
        for id in stickyWindows {
            guard let window = windows[id], let from = window.key, from.screen == key.screen, from != key else { continue }
            let width = strips[from].flatMap { strip in strip.locate(id).map { strip.columns[$0.column].width } } ?? 1
            removeFromStrip(window)
            var strip = strips[key] ?? Strip()
            strip.insert(id, width: width, position: .end, focus: false)
            strips[key] = strip
            window.key = key
        }
        stickyWindows = stickyWindows.filter { windows[$0] != nil || windowMemory[$0] != nil }
    }

    // MARK: - Zoom

    /// A tile blown up to fill its slide, until zoomed again or focus moves on.
    private var zoomed: WindowID?

    private func toggleZoom() {
        guard let id = focusedWindowID(), let key = windows[id]?.key, let strip = strips[key],
            let (c, _) = strip.locate(id), strip.columns[c].windows.count > 1
        else {
            zoomed = nil
            return
        }
        zoomed = zoomed == id ? nil : id
        windows[id]?.element.raise()
        layout(animated: true)
    }

    // MARK: - Window history

    /// Windows in the order they were focused, most recent last.
    private var focusHistory: [WindowID] = []

    /// Back to the window you were on before this one (again to come back).
    private func focusLastWindow() {
        let current = focusedWindowID()
        guard let previous = focusHistory.reversed().first(where: { $0 != current && windows[$0] != nil }) else {
            onNotice("No earlier window")
            return
        }
        focusAndReveal(previous)
    }

    // MARK: - Quick launch

    /// Opens the app in `letter`'s slot, or goes to its most recent window.
    func quickLaunch(_ letter: String) {
        guard let bundleID = settings.launchSlots[letter.lowercased()] else {
            onNotice("Nothing on “\(letter.uppercased())” · set quick launch apps in Settings → Apps")
            return
        }
        let mine = windows.values.filter { $0.bundleID == bundleID }
        if let recent = focusHistory.reversed().first(where: { id in mine.contains { $0.id == id } }) ?? mine.first?.id {
            focusAndReveal(recent)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Moving slides between strips

    /// Drags a whole slide from one strip (display or workspace) to another in the overview.
    func overviewMoveColumn(from index: Int, of source: StripKey, to target: StripKey, at position: Int) {
        guard source != target, var from = strips[source], from.columns.indices.contains(index) else { return }
        recordHistory()
        let column = from.columns[index]
        var columns = from.columns
        columns.remove(at: index)
        from.replaceColumns(columns, keepingFocusOn: from.focusedWindow)
        strips[source] = from
        var to = strips[target] ?? Strip()
        var targetColumns = to.columns
        targetColumns.insert(column, at: min(max(position, 0), targetColumns.count))
        to.replaceColumns(targetColumns, keepingFocusOn: column.windows.first)
        strips[target] = to
        for id in column.windows {
            windows[id]?.key = target
            windows[id]?.lastApplied = nil
        }
        layout(animated: true)
        scheduleSave()
        onStateChange()
    }

    /// The focused window's app, for the menu bar.
    var focusedAppName: String? { focusedWindowID().flatMap { windows[$0]?.appName } }

    // MARK: - Power moves

    /// The workspace each screen showed before the current one.
    private var previousWorkspace: [ScreenKey: Int] = [:]
    /// Show desktop: every window on the screens in view waits in the corner.
    private var showingDesktop = false

    /// Animations stay off while macOS asks for less motion or saves power.
    private var reduceMotion: Bool {
        (settings.followReduceMotion
            && (NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled))
            || (settings.skipAnimationsOnBattery && Power.onBattery)
    }

    private func moveFocusedToEmptyWorkspace() {
        guard let (_, key) = activeContext() else { return }
        let empty = (0..<workspaceLimit).first { index in
            base + index != key.workspace && (strips[StripKey(screen: key.screen, workspace: base + index)]?.isEmpty ?? true)
        }
        guard let empty else {
            onNotice("Every workspace has windows")
            return
        }
        moveFocusedWindow(toWorkspace: empty)
        switchWorkspace(to: empty)
        onNotice("Moved to \(settings.workspaceName(empty))")
    }

    /// Evens out every slide's width and split on the strip in view.
    private func balanceSizes() {
        guard let (display, key) = activeContext(), var strip = strips[key] else { return }
        recordHistory()
        strip.balance(width: layoutConfig(for: display).defaultWidth)
        commit(strip, key)
        onNotice("Evened out")
    }

    /// Saves a picture of the focused slide to the Desktop and the clipboard.
    private func screenshotSlide() {
        guard let (display, key) = activeContext(), let strip = strips[key], !strip.isEmpty else { return }
        let frames = strip.columnFrames(config: layoutConfig(for: display), viewport: viewport(of: display))
        guard frames.indices.contains(strip.focusedColumn) else { return }
        let rect = frames[strip.focusedColumn].frame
        let region = "\(Int(rect.x)),\(Int(rect.y)),\(Int(rect.width)),\(Int(rect.height))"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
        let file = desktop.appendingPathComponent("Monorail slide \(formatter.string(from: Date())).png")
        for arguments in [["-x", "-R", region, file.path], ["-x", "-c", "-R", region]] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = arguments
            try? process.run()
        }
        onNotice("Slide saved to the Desktop and copied")
    }

    /// Where a snap would put the focused window, for the radial menu's preview.
    func snapPreview(_ position: SnapPosition) -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication,
            let frame = AXUIElement.application(app.processIdentifier).focusedWindow?.frame,
            let display = display(containing: frame) ?? displays.first
        else { return nil }
        return CGRect(position.frame(in: display.viewport, gap: layoutConfig(for: display).gap))
    }

    func snapFocused(_ position: SnapPosition) {
        guard isRunning, !isPaused else { return }
        recordHistory()
        snap(position)
    }

    // MARK: - Dragging with the modifier keys

    private struct ModifierDrag {
        var id: WindowID
        var start: CGPoint
        var frame: CGRect
        var resize: Bool
    }

    private var modifierDrag: ModifierDrag?

    /// ⌃⌥ + drag anywhere in a window moves it; ⌃⌥ + right-drag resizes it.
    /// Returns true if a window is under the pointer (the click is then Monorail's).
    func beginModifierDrag(at point: CGPoint, resize: Bool) -> Bool {
        guard isRunning, !isPaused, settings.modifierDrag, let id = topWindow(at: point), let window = windows[id],
            let frame = window.element.frame
        else { return false }
        animator.cancel()
        modifierDrag = ModifierDrag(id: id, start: point, frame: frame, resize: resize)
        focus(id, warpMouse: false)
        return true
    }

    func continueModifierDrag(to point: CGPoint) {
        guard let drag = modifierDrag, let window = windows[drag.id] else { return }
        let dx = point.x - drag.start.x, dy = point.y - drag.start.y
        var frame = drag.frame
        if drag.resize {
            frame.size.width = max(160, drag.frame.width + dx)
            frame.size.height = max(120, drag.frame.height + dy)
            if settings.resizeHUD { onResizeHUD(frame) }
        } else {
            frame.origin.x += dx
            frame.origin.y += dy
        }
        writer.set(frame, of: drag.id, element: window.element, pid: window.pid, sizeChanged: drag.resize)
    }

    /// Lets go: a tiled window lands where it was dropped (or takes its new
    /// width), like a drag by the title bar.
    func endModifierDrag() {
        guard let drag = modifierDrag, let window = windows[drag.id] else {
            modifierDrag = nil
            return
        }
        modifierDrag = nil
        onResizeHUD(nil)
        guard let key = window.key, let display = display(for: key) else { return }
        // Give the last write a moment to land, then settle the strip.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            if drag.resize, let frame = window.element.frame {
                if var strip = self.strips[key], let (c, _) = strip.locate(window.id), strip.columns[c].windows.count > 1 {
                    let column = strip.columnFrames(config: self.layoutConfig(for: display), viewport: self.viewport(of: display))[c].frame
                    _ = strip.resizeTile(window.id, toFraction: (
                        width: Double(frame.width) / max(column.width, 1), height: Double(frame.height) / max(column.height, 1)))
                    self.strips[key] = strip
                } else {
                    let fraction = self.layoutConfig(for: display).fraction(
                        forColumnWidth: Double(frame.width), viewportWidth: self.viewport(of: display).width)
                    self.strips[key]?.setWidth(fraction, of: window.id)
                }
                window.lastApplied = nil
                self.layout(animated: true)
                self.scheduleSave()
            } else {
                self.finishUserMove(window, resized: false)
            }
        }
    }

    var isModifierDragging: Bool { modifierDrag != nil }

    // MARK: - Title bar swipes

    /// The managed window whose title bar is under `point`, if any.
    func titleBarWindow(at point: CGPoint) -> WindowID? {
        guard isRunning, !isPaused, settings.titleBarSwipes, let id = topWindow(at: point), let window = windows[id],
            let frame = window.element.frame, point.y - frame.minY < 30
        else { return nil }
        return id
    }

    enum Swipe { case left, right, up, down }

    /// A two-finger swipe on a title bar: left and right move the window's
    /// slide, up toggles full width, down minimises.
    func titleBarSwipe(_ swipe: Swipe, on id: WindowID) {
        guard let window = windows[id] else { return }
        if window.key == nil {
            // A floating window snaps to that side instead.
            let element = window.element
            switch swipe {
            case .left: snap(element, to: .leftHalf)
            case .right: snap(element, to: .rightHalf)
            case .up: snap(element, to: .maximize)
            case .down: minimizeWindow(id)
            }
            return
        }
        if swipe == .down {
            minimizeWindow(id)
            return
        }
        guard let key = window.key, var strip = strips[key] else { return }
        recordHistory()
        strip.focus(id)
        // Left and right are what you see, also on a right-to-left strip.
        let mirrored = settings.layout.direction == .rightToLeft
        switch swipe {
        case .left: strip.moveFocused(mirrored ? .right : .left)
        case .right: strip.moveFocused(mirrored ? .left : .right)
        default: strip.toggleFullWidth()
        }
        commit(strip, key)
        focus(id, warpMouse: false)
        haptic()
    }

    // MARK: - Remembered widths, centred and growing windows

    /// The width the user last gave each app's windows.
    private var appWidths: [String: Double] = [:]

    private func rememberedWidth(_ window: ManagedWindow) -> Double? {
        settings.rememberWidths ? appWidths[Self.appKey(window)] : nil
    }

    /// A lone window centred at a comfortable width, and the focused one of
    /// two windows in a slide growing a little.
    private func applyComfortTweaks(_ targets: inout [WindowID: (from: Rect, to: Rect)]) {
        guard !showingDesktop, settings.centerLoneWindow > 0 || settings.autoGrowFocus > 0 else { return }
        let focused = settings.autoGrowFocus > 0 ? focusedWindowID() : nil
        for display in displays {
            let key = currentKey(display)
            guard let strip = strips[key] else { continue }
            let area = viewport(of: display)
            if settings.centerLoneWindow > 0, strip.columns.count == 1, let column = strip.columns.first,
                column.windows.count == 1, !column.isFullWidth, let id = column.windows.first, var target = targets[id]
            {
                let width = (area.width * min(max(settings.centerLoneWindow, 0.3), 1)).rounded()
                target.to = Rect(x: area.x + ((area.width - width) / 2).rounded(), y: target.to.y, width: width, height: target.to.height)
                targets[id] = target
            }
            guard settings.autoGrowFocus > 0, let focused, let (c, _) = strip.locate(focused) else { continue }
            let column = strip.columns[c]
            guard column.windows.count == 2, !column.isTabbed, column.arrangement != .accordion,
                let a = targets[column.windows[0]], let b = targets[column.windows[1]]
            else { continue }
            let share = min(max(settings.autoGrowFocus, 0.5), 0.8)
            let gap = layoutConfig(for: display).gap
            let sideBySide = abs(a.to.y - b.to.y) < 1
            let ordered = column.windows.sorted { sideBySide ? targets[$0]!.to.x < targets[$1]!.to.x : targets[$0]!.to.y < targets[$1]!.to.y }
            let first = targets[ordered[0]]!.to, second = targets[ordered[1]]!.to
            let firstShare = ordered[0] == focused ? share : 1 - share
            if sideBySide {
                let total = first.width + second.width
                let left = (total * firstShare).rounded()
                targets[ordered[0]]!.to = Rect(x: first.x, y: first.y, width: left, height: first.height)
                targets[ordered[1]]!.to = Rect(x: first.x + left + gap, y: second.y, width: total - left, height: second.height)
            } else {
                let total = first.height + second.height
                let top = (total * firstShare).rounded()
                targets[ordered[0]]!.to = Rect(x: first.x, y: first.y, width: first.width, height: top)
                targets[ordered[1]]!.to = Rect(x: second.x, y: first.y + top + gap, width: second.width, height: total - top)
            }
        }
    }

    // MARK: - Projects

    /// Where each project's windows gather.
    private var projectHomes: [String: StripKey] = [:]
    private var projectPlaced: Set<WindowID> = []

    /// A window whose title names a project (often only once its document
    /// loads) joins that project's workspace.
    private func gatherProject(_ window: ManagedWindow) {
        guard isRunning, !isPaused, !projectPlaced.contains(window.id), let key = window.key,
            let project = ProjectMatcher.project(in: window.title, projects: settings.projects)
        else { return }
        projectPlaced.insert(window.id)
        guard let home = projectHomes[project], home.screen == key.screen, home != key,
            home.workspace / Self.profileStride == activeProfile
        else {
            projectHomes[project] = key
            return
        }
        moveWindow(window.id, toWorkspace: home.workspace - base)
        onNotice("\(window.appName) joined \(project) in \(settings.workspaceName(home.workspace - base))")
    }

    // MARK: - Hints, resize mode, recent slides

    /// The windows on screen now, with their frames (Accessibility coordinates), for window hints.
    func visibleWindowFrames() -> [(id: WindowID, frame: CGRect, app: String)] {
        var result: [(id: WindowID, frame: CGRect, app: String)] = []
        for display in displays {
            let key = currentKey(display)
            guard let strip = strips[key] else { continue }
            for placement in strip.layout(config: layoutConfig(for: display), viewport: viewport(of: display))
            where !placement.isParked && !placement.isHiddenTab {
                guard let window = windows[placement.window], let frame = window.lastApplied else { continue }
                let visible = CGRect(frame).intersection(display.frame)
                guard visible.width > 60, visible.height > 60 else { continue }
                result.append((placement.window, visible, window.appName))
            }
        }
        for window in windows.values where window.key == nil {
            if let frame = window.element.frame, displays.contains(where: { $0.frame.intersects(frame) }) {
                result.append((window.id, frame, window.appName))
            }
        }
        return result.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
    }

    /// A key in resize mode: ← → width, ↑ ↓ the main share, 1–9 a tenth of the
    /// screen each, 0 full width. Returns false for keys that end the mode.
    func resizeKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case KeyCode.left: perform(.narrower)
        case KeyCode.right: perform(.wider)
        case KeyCode.up: perform(.mainLarger)
        case KeyCode.down: perform(.mainSmaller)
        case let code where KeyCode.digits.contains(code):
            let tenths = (KeyCode.digits.firstIndex(of: code) ?? 0) + 1
            guard let id = focusedWindowID(), let key = windows[id]?.key, var strip = strips[key] else { return true }
            recordHistory()
            strip.setWidth(Double(tenths) / 10, of: id)
            commit(strip, key)
        case KeyCode.zero: perform(.toggleFullWidth)
        default: return false
        }
        return true
    }

    /// Slides you were on recently, most recent first: a title and a window to go to.
    func recentSlides(_ limit: Int = 8) -> [(title: String, window: WindowID)] {
        var seen: [String] = []
        var result: [(title: String, window: WindowID)] = []
        for id in focusHistory.reversed() {
            guard let key = windows[id]?.key, let strip = strips[key], let (c, _) = strip.locate(id) else { continue }
            let mark = "\(key.display)|\(key.workspace)|\(strip.columns[c].windows.sorted())"
            guard !seen.contains(mark) else { continue }
            seen.append(mark)
            var names: [String] = []
            for name in strip.columns[c].windows.compactMap({ windows[$0]?.appName }) where !names.contains(name) { names.append(name) }
            result.append((names.joined(separator: " + "), id))
            if result.count == limit { break }
        }
        return result
    }

    /// Workspaces as a vertical stack: the next one slides up from below.
    func switchWorkspaceVertically(next: Bool) {
        guard let (_, key) = activeContext() else { return }
        let current = key.workspace - base
        let target = current + (next ? 1 : -1)
        guard target >= 0, target < visibleWorkspaceCount(on: key.screen) else {
            haptic()
            return
        }
        switchWorkspace(to: target, slide: next ? 1 : -1)
    }

    // MARK: - Moving tabs

    /// A tab dragged out of its tab bar and dropped over another slide joins it.
    func dropTab(_ id: WindowID, at point: CGPoint) {
        guard let window = windows[id], let source = window.key else { return }
        for display in displays where display.frame.contains(point) {
            let key = currentKey(display)
            guard let strip = strips[key] else { continue }
            let frames = strip.columnFrames(config: layoutConfig(for: display), viewport: viewport(of: display))
            guard let target = frames.indices.first(where: { CGRect(frames[$0].frame).contains(point) }) else {
                // Dropped between slides: a slide of its own.
                let slot = frames.indices.first { CGRect(frames[$0].frame).minX > point.x } ?? frames.count
                overviewMove(id, to: key, newColumnAt: slot)
                return
            }
            if source == key, strip.locate(id)?.column == target { return }
            overviewMove(id, to: key, column: target)
            return
        }
    }

    // MARK: - Presentation mode

    /// While presenting, Monorail's own overlays and notices stay out of sight.
    private(set) var isPresenting = false

    func setPresenting(_ on: Bool) {
        guard on != isPresenting else { return }
        // Say so before the notices go quiet, or after they come back.
        if on { onNotice("Presentation mode · overlays hidden") }
        isPresenting = on
        if !on { onNotice("Presentation mode off") }
        updateOverlays()
        onStateChange()
    }

    // MARK: - Recording a slide

    private var recorder: Process?
    var isRecording: Bool { recorder?.isRunning == true }

    /// Records the focused slide to a movie on the Desktop; again to stop.
    private func toggleRecording() {
        if let recorder, recorder.isRunning {
            recorder.interrupt()
            self.recorder = nil
            onNotice("Recording saved to the Desktop")
            onStateChange()
            return
        }
        guard let (display, key) = activeContext(), let strip = strips[key], !strip.isEmpty else { return }
        let frames = strip.columnFrames(config: layoutConfig(for: display), viewport: viewport(of: display))
        guard frames.indices.contains(strip.focusedColumn) else { return }
        let rect = frames[strip.focusedColumn].frame
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
        let file = desktop.appendingPathComponent("Monorail slide \(formatter.string(from: Date())).mov")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-v", "-x", "-k", "-R", "\(Int(rect.x)),\(Int(rect.y)),\(Int(rect.width)),\(Int(rect.height))", file.path]
        process.terminationHandler = { [weak self] _ in DispatchQueue.main.async { self?.onStateChange() } }
        do {
            try process.run()
            recorder = process
            onNotice("Recording the slide · ⌃⌥⇧V again to stop")
            onStateChange()
        } catch {
            onNotice("Couldn’t start recording")
        }
    }

    // MARK: - Templates

    /// Opens a template: an empty workspace (if it asks), each app with its
    /// files and links, then one window of each in a new slide.
    func runTemplate(_ template: WorkspaceTemplate) {
        guard isRunning, !isPaused, !template.items.isEmpty else { return }
        if template.emptyWorkspace, let (_, key) = activeContext(),
            let empty = (0..<workspaceLimit).first(where: { strips[StripKey(screen: key.screen, workspace: base + $0)]?.isEmpty ?? true })
        {
            switchWorkspace(to: empty)
        }
        var bundleIDs: [String] = []
        for item in template.items {
            if !bundleIDs.contains(item.bundleID) { bundleIDs.append(item.bundleID) }
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleID) else { continue }
            let urls = item.targets.compactMap { target -> URL? in
                if target.contains("://") { return URL(string: target) }
                return URL(fileURLWithPath: (target as NSString).expandingTildeInPath)
            }
            let configuration = NSWorkspace.OpenConfiguration()
            if urls.isEmpty {
                NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            } else {
                NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration)
            }
        }
        openPair(AppPair(id: template.id, name: template.name, bundleIDs: bundleIDs, arrangement: template.arrangement),
                 launch: false)
    }

    /// Puts these windows together in a new slide (for the API and AI assistants).
    @discardableResult
    func pairWindows(_ ids: [WindowID], arrangement: Arrangement) -> Bool {
        let tiled = Array(ids.filter { windows[$0]?.key != nil }.prefix(Column.maximumWindows))
        guard tiled.count >= 2, let key = windows[tiled[0]]?.key else { return false }
        recordHistory()
        for id in tiled { if let window = windows[id] { removeFromStrip(window) } }
        var strip = strips[key] ?? Strip()
        strip.insertSlide(tiled, width: 1, arrangement: arrangement, position: .afterFocused, focus: true, custom: true)
        for id in tiled { windows[id]?.key = key }
        commit(strip, key)
        focus(tiled[0], warpMouse: false)
        onStateChange()
        return true
    }

    /// Every managed window, for the API: where it is and what it shows.
    func windowList() -> [[String: Any]] {
        windows.values.map { window in
            var entry: [String: Any] = ["id": Int(window.id), "app": window.appName, "title": displayTitle(window),
                                        "floating": window.key == nil]
            if let bundleID = window.bundleID { entry["bundleID"] = bundleID }
            if let key = window.key {
                entry["workspace"] = key.workspace % Self.profileStride + 1
                entry["profile"] = settings.profiles.indices.contains(key.workspace / Self.profileStride)
                    ? settings.profiles[key.workspace / Self.profileStride] : "Default"
                if let (c, _) = strips[key]?.locate(window.id) { entry["slide"] = c + 1 }
                entry["visible"] = displays.contains { currentKey($0) == key }
            }
            return entry
        }.sorted { ($0["id"] as? Int ?? 0) < ($1["id"] as? Int ?? 0) }
    }

    // MARK: - Practice windows

    /// Monorail's own practice windows (the welcome tour), tiled like any other.
    private var demoWindows: Set<WindowID> = []

    func adoptDemoWindow(_ number: Int) {
        let id = WindowID(number)
        demoWindows.insert(id)
        guard let element = AXUIElement.application(ownPID).windows.first(where: { $0.windowID == id }) else { return }
        if adopt(element, pid: ownPID, focus: true, force: true) { layout(animated: true) }
    }

    func forgetDemoWindows() {
        for id in demoWindows { forget(id) }
        demoWindows.removeAll()
        layout(animated: true)
    }

    // MARK: - 0.9: displays, slides and rescue

    /// Where each app's floating windows were last put.
    private var floatingFrames: [String: CGRect] = [:]

    private func focusNextDisplay() {
        guard displays.count > 1, let (display, _) = activeContext(),
            let index = displays.firstIndex(where: { $0.uuid == display.uuid })
        else { return }
        let next = displays[(index + 1) % displays.count]
        if let target = strips[currentKey(next)]?.focusedWindow {
            focusAndReveal(target)
        } else {
            CGWarpMouseCursorPosition(CGPoint(x: next.frame.midX, y: next.frame.midY))
        }
    }

    /// The whole workspace (every slide) moves to the next display.
    private func moveWorkspaceToNextDisplay() {
        guard displays.count > 1, let (display, key) = activeContext(), let strip = strips[key], !strip.isEmpty,
            let index = displays.firstIndex(where: { $0.uuid == display.uuid })
        else { return }
        recordHistory()
        let next = displays[(index + 1) % displays.count]
        let target = currentKey(next)
        var into = strips[target] ?? Strip()
        into.replaceColumns(into.columns + strip.columns, keepingFocusOn: strip.focusedWindow)
        strips[target] = into
        strips[key] = Strip()
        for id in into.allWindows {
            windows[id]?.key = target
            windows[id]?.lastApplied = nil
        }
        layout(animated: true)
        if let id = strip.focusedWindow { focus(id, warpMouse: true) }
        scheduleSave()
        onNotice("Moved \(settings.workspaceName(key.workspace - base)) to \(next.name)")
    }

    /// The first two displays trade their workspaces.
    private func swapDisplays() {
        guard displays.count > 1 else { return }
        recordHistory()
        let a = currentKey(displays[0]), b = currentKey(displays[1])
        let first = strips[a] ?? Strip(), second = strips[b] ?? Strip()
        strips[a] = second
        strips[b] = first
        for id in second.allWindows { windows[id]?.key = a; windows[id]?.lastApplied = nil }
        for id in first.allWindows { windows[id]?.key = b; windows[id]?.lastApplied = nil }
        layout(animated: true)
        scheduleSave()
        onNotice("Swapped displays")
    }

    private func moveFocusedToPointerDisplay() {
        guard let pointer = displayUnderMouse(), let id = focusedWindowID(), let window = windows[id], let key = window.key,
            key.display != pointer.uuid
        else { return }
        recordHistory()
        let width = strips[key].flatMap { strip in strip.locate(id).map { strip.columns[$0.column].width } }
        removeFromStrip(window)
        place(window, in: currentKey(pointer), display: pointer, focus: true, width: width, restoring: false)
        window.lastApplied = nil
        layout(animated: true)
        focus(id, warpMouse: false)
    }

    /// The next window of the same app, in strip order, across workspaces.
    private func cycleAppWindows() {
        guard let id = focusedWindowID(), let window = windows[id] else { return }
        let app = Self.appKey(window)
        let ordered = strips.sorted { ($0.key.display, $0.key.workspace) < ($1.key.display, $1.key.workspace) }
            .flatMap(\.value.allWindows).filter { windows[$0].map(Self.appKey) == app }
        guard ordered.count > 1, let index = ordered.firstIndex(of: id) else {
            onNotice("No other \(window.appName) window")
            return
        }
        focusAndReveal(ordered[(index + 1) % ordered.count])
    }

    /// The focused window and the one before it trade places.
    private func swapWithRecent() {
        guard let id = focusedWindowID(), let key = windows[id]?.key,
            let other = focusHistory.reversed().first(where: { $0 != id && windows[$0]?.key == key }),
            var strip = strips[key]
        else {
            onNotice("No earlier window on this strip")
            return
        }
        recordHistory()
        strip.swapWindows(id, other)
        commit(strip, key)
    }

    /// Widens the focused slide to fill whatever the other slides on screen leave free.
    private func expandToFill(_ strip: inout Strip, display: Display) {
        let config = layoutConfig(for: display)
        let area = viewport(of: display)
        let frames = strip.columnFrames(config: config, viewport: area)
        let others = frames.indices.filter { index in
            index != strip.focusedColumn && strip.columns[index].pin == nil
                && frames[index].frame.x >= area.x - 1 && frames[index].frame.x + frames[index].frame.width <= area.x + area.width + 1
        }
        let used = others.reduce(0.0) { $0 + frames[$1].frame.width + config.gap }
        let free = area.width - used - config.edgeGap * 2
        guard free > 100, let id = strip.focusedWindow else { return }
        strip.setWidth(config.fraction(forColumnWidth: free, viewportWidth: area.width), of: id)
    }

    /// Every window of the focused app (up to six on this screen) into one slide.
    private func gatherFocusedApp() {
        guard let id = focusedWindowID(), let window = windows[id], let key = window.key else { return }
        let app = Self.appKey(window)
        let mine = [id] + windows.values.filter { $0.id != id && $0.key?.screen == key.screen && Self.appKey($0) == app }.map(\.id)
        guard mine.count > 1 else {
            onNotice("\(window.appName) has one window here")
            return
        }
        pairWindows(Array(mine.prefix(Column.maximumWindows)), arrangement: mine.count > 2 ? .grid : .columns)
        onNotice("Gathered \(min(mine.count, Column.maximumWindows)) \(window.appName) windows")
    }

    private func tileAllFloating() {
        let floating = windows.values.filter { $0.key == nil && $0.id != scratchpad && !demoWindows.contains($0.id) }
        guard !floating.isEmpty else {
            onNotice("No floating windows")
            return
        }
        recordHistory()
        for window in floating { tile(window) }
        onNotice("Tiled \(floating.count) floating windows")
    }

    /// When something goes wrong: every window of every app back on screen, then a fresh layout.
    func rescueWindows() {
        animator.finishNow()
        showingDesktop = false
        guard let main = displays.first else { return }
        var moved = 0
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            for element in AXUIElement.application(app.processIdentifier).windows {
                guard let frame = element.frame, element.role == kAXWindowRole else { continue }
                let onScreen = displays.contains { $0.frame.intersection(frame).area > frame.area * 0.5 }
                // Tiled windows waiting in other workspaces are off screen on purpose; the retile handles them.
                let waiting = element.windowID.flatMap { windows[$0]?.key } != nil
                if !onScreen, !waiting {
                    let size = CGSize(width: min(frame.width, main.visibleFrame.width * 0.8), height: min(frame.height, main.visibleFrame.height * 0.8))
                    element.setFrame(CGRect(x: main.visibleFrame.midX - size.width / 2, y: main.visibleFrame.midY - size.height / 2,
                                            width: size.width, height: size.height))
                    moved += 1
                }
            }
        }
        retile()
        onNotice(moved > 0 ? "Brought \(moved) windows back on screen" : "Every window is on screen")
    }

    // MARK: Solo

    private var soloHidden: [pid_t] = []

    /// Hides every app except the ones in the focused slide; again to bring them back.
    private func toggleSolo() {
        if !soloHidden.isEmpty {
            for pid in soloHidden { NSRunningApplication(processIdentifier: pid)?.unhide() }
            soloHidden.removeAll()
            onNotice("Solo off")
            return
        }
        guard let id = focusedWindowID(), let key = windows[id]?.key, let strip = strips[key], let (c, _) = strip.locate(id) else { return }
        let keep = Set(strip.columns[c].windows.compactMap { windows[$0]?.pid } + [ownPID])
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !keep.contains(app.processIdentifier) && !app.isHidden {
            if app.hide() { soloHidden.append(app.processIdentifier) }
        }
        onNotice("Solo · \(soloHidden.count) apps hidden · again to bring them back")
    }

    // MARK: Gaps

    private var gapsBeforeZen: (gap: Double, edge: Double)?

    private func adjustGaps(_ action: Action) {
        switch action {
        case .toggleGaps:
            if settings.layout.gap > 0 || settings.layout.edgeGap > 0 {
                gapsBeforeZen = (settings.layout.gap, settings.layout.edgeGap)
                onAdjustSettings { $0.layout.gap = 0; $0.layout.edgeGap = 0 }
                onNotice("No gaps")
            } else {
                let back = gapsBeforeZen ?? (LayoutConfig().gap, LayoutConfig().edgeGap)
                onAdjustSettings { $0.layout.gap = back.gap; $0.layout.edgeGap = back.edge }
                onNotice("Gaps back")
            }
        default:
            let step = action == .biggerGaps ? 4.0 : -4.0
            onAdjustSettings { settings in
                settings.layout.gap = min(max(settings.layout.gap + step, 0), 40)
                settings.layout.edgeGap = min(max(settings.layout.edgeGap + step, 0), 40)
            }
        }
    }

    private func centerFocusedFloating() {
        guard let app = NSWorkspace.shared.frontmostApplication,
            let element = AXUIElement.application(app.processIdentifier).focusedWindow, let frame = element.frame,
            let display = display(containing: frame)
        else { return }
        if let id = element.windowID, windows[id]?.key != nil {
            onNotice("Tiled windows stay on the strip · ⌃⌥T floats one")
            return
        }
        let area = display.visibleFrame
        element.setPosition(CGPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2))
    }

    /// Floats a window and makes it exactly `size`, centred (for recordings and screenshots).
    func setFloatingSize(_ id: WindowID, _ size: CGSize) {
        guard let window = windows[id] else { return }
        if window.key != nil {
            removeFromStrip(window)
            window.lastApplied = nil
            layout(animated: true)
        }
        guard let display = display(containing: window.element.frame ?? .zero) ?? displays.first else { return }
        let area = display.visibleFrame
        let fitted = CGSize(width: min(size.width, area.width), height: min(size.height, area.height))
        window.element.setFrame(CGRect(x: area.midX - fitted.width / 2, y: area.midY - fitted.height / 2,
                                       width: fitted.width, height: fitted.height))
        focus(id, warpMouse: false)
    }

    /// Stops managing a window (the app gets a float rule from the caller).
    func release(_ id: WindowID) {
        guard let window = windows[id] else { return }
        if window.key != nil {
            removeFromStrip(window)
            window.lastApplied = nil
            layout(animated: true)
        }
    }

    // MARK: Slide names and locks

    func slideName(of id: WindowID) -> String? {
        guard let key = windows[id]?.key, let strip = strips[key], let (c, _) = strip.locate(id) else { return nil }
        return strip.columns[c].name
    }

    func nameSlide(_ id: WindowID, _ name: String) {
        guard let key = windows[id]?.key, var strip = strips[key] else { return }
        strip.setName(name, ofSlideWith: id)
        strips[key] = strip
        scheduleSave()
        onStateChange()
    }

    func isSlideLocked(_ id: WindowID) -> Bool {
        guard let key = windows[id]?.key, let strip = strips[key], let (c, _) = strip.locate(id) else { return false }
        return strip.columns[c].isLocked
    }

    func toggleLock(_ id: WindowID) {
        guard let key = windows[id]?.key, var strip = strips[key] else { return }
        let locked = strip.toggleLock(ofSlideWith: id)
        strips[key] = strip
        scheduleSave()
        onStateChange()
        onNotice(locked ? "Slide locked · smart pairs and new windows leave it alone" : "Slide unlocked")
    }

    // MARK: For Settings and diagnostics

    var wholeSlideApps: [String] { roomyApps.sorted() }

    func forgetWholeSlideApp(_ app: String) {
        roomyApps.remove(app)
        scheduleSave()
    }

    /// A short report for bug reports: no window titles, nothing private.
    func diagnostics() -> String {
        var lines: [String] = []
        lines.append("Displays: " + displays.map { "\($0.name) \(Int($0.frame.width))×\(Int($0.frame.height))" }.joined(separator: ", "))
        lines.append("Managed windows: \(windows.count) (\(windows.values.filter { $0.key == nil }.count) floating)")
        lines.append("Strips: \(strips.filter { !$0.value.isEmpty }.count), slides on screen: \(slideCount)")
        lines.append("Apps: " + Set(windows.values.map(\.appName)).sorted().joined(separator: ", "))
        lines.append("Whole-slide apps: " + (roomyApps.isEmpty ? "none" : roomyApps.sorted().joined(separator: ", ")))
        lines.append("Paused: \(isPaused), profile: \(profileName), focus mode: \(isFocusMode)")
        return lines.joined(separator: "\n")
    }

    // MARK: - Haptics

    /// A light tap on Force Touch trackpads as the strip lands on a slide.
    private func haptic() {
        if settings.slideSound { Self.click?.play() }
        guard settings.hapticFeedback else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// A soft click for slide changes.
    private static let click: NSSound? = {
        let sound = NSSound(named: "Tink")
        sound?.volume = 0.25
        return sound
    }()

    // MARK: - Snapping floating windows

    /// Where a snapped window was before, so "restore" can put it back.
    private var snapOrigins: [WindowID: (frame: CGRect, key: StripKey?, slot: Strip.Slot?)] = [:]

    private func snap(_ position: SnapPosition) {
        guard let app = NSWorkspace.shared.frontmostApplication,
            let element = AXUIElement.application(app.processIdentifier).focusedWindow
        else { return }
        snap(element, to: position)
    }

    /// Snaps a window dropped on the snap layouts picker.
    func snapWindow(_ id: WindowID, to position: SnapPosition) {
        guard isRunning, !isPaused, let window = windows[id] else { return }
        recordHistory()
        snap(window.element, to: position)
        focus(id, warpMouse: false)
    }

    private func snap(_ element: AXUIElement, to position: SnapPosition) {
        guard let id = element.windowID, let frame = element.frame,
            let display = display(containing: frame) ?? displays.first
        else { return }
        if snapOrigins[id] == nil {
            let window = windows[id]
            let slot = window?.key.flatMap { strips[$0]?.slot(of: id) }
            snapOrigins[id] = (frame, window?.key, slot)
        }
        if let window = windows[id], window.key != nil {
            // Snapping floats a tiled window; restore tiles it again.
            removeFromStrip(window)
            window.lastApplied = nil
            layout(animated: true)
        }
        let target = position.frame(in: display.viewport, gap: layoutConfig(for: display).gap)
        element.setFrame(CGRect(target))
    }

    private func snapRestore() {
        guard let app = NSWorkspace.shared.frontmostApplication,
            let element = AXUIElement.application(app.processIdentifier).focusedWindow,
            let id = element.windowID, let origin = snapOrigins.removeValue(forKey: id)
        else { return }
        if let key = origin.key, let slot = origin.slot, let window = windows[id] {
            var strip = strips[key] ?? Strip()
            strip.restore(id, to: slot)
            strips[key] = strip
            window.key = key
            window.lastApplied = nil
            layout(animated: true)
        } else {
            element.setFrame(origin.frame)
        }
    }
}

private func axObserverCallback(
    _ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    Unmanaged<Engine>.fromOpaque(refcon).takeUnretainedValue().handle(notification as String, element: element)
}

extension Rect {
    init(_ rect: CGRect) {
        self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }
}

extension CGRect {
    init(_ rect: Rect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    var area: CGFloat { isNull ? 0 : width * height }
}
#endif
