#if os(macOS)
import AppKit
import Combine
import MonorailCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = SettingsStore()
    private lazy var engine = Engine(settings: store.settings)
    private let input = InputMonitor()
    private let trackpad = TrackpadSwipe.shared
    private let switcher = SwitcherController()
    private lazy var overview = OverviewController(engine: engine)
    private let updater = Updater()
    private var subscriptions: [AnyCancellable] = []
    private let practice = PracticeTracker()
    private let sliderBar = SliderBarController()
    private let resizeAssist = ResizeAssist()
    private let toast = Toast()
    private let hotEdges = HotEdges()
    private let coach = CoachTips()
    private let popover = SliderPopover()
    private let snapPicker = SnapPicker()
    private let palette = CommandPalette()
    private let stats = UsageStats()
    private let autoRules = AutoRules()
    private let pictureInPicture = PictureInPicture()
    private let radial = RadialMenu()
    private let resizeHUD = ResizeHUD()
    private let integrations = Integrations()
    private let hints = WindowHints()
    private let stripZoom = StripZoom()
    private let meetings = MeetingHelper()
    private let api = LocalAPI()
    private let scripts = ScriptHost()
    private var resizeModeTimer: Timer?
    private let cheatSheet = CheatSheet()
    private let workspaceHUD = WorkspaceHUD()
    private var demoWindows: [NSWindow] = []
    private var statsTimer: Timer?
    private var apiStarted = false
    private var capsLockOn = false
    private let whatsNew = WhatsNew()
    private let weekly = WeeklySummary()
    private var scriptsOn = false
    private let statusMenu = NSMenu()
    private let navigation = SettingsNavigation()
    private var statusItem: NSStatusItem!
    private var arrowItems: [NSStatusItem] = []
    private let slideHUD = SlideHUD()
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var permissionTimer: Timer?
    private var mouseMonitor: Any?
    private var signalSources: [DispatchSourceSignal] = []

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier,
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1
        {
            // Another copy is running; let it handle things.
            NSApp.terminate(nil)
            return
        }

        // The main thread never waits long on a busy app; window moves run in
        // the background with their own, longer allowance (see WindowWriter).
        Accessibility.setGlobalTimeout(0.25)
        setUpStatusItem()
        wireUp()
        handleTerminationSignals()

        if Accessibility.isTrusted(prompt: false) {
            startEngine()
        } else {
            waitForPermission()
        }
        if !store.settings.hasCompletedOnboarding || !Accessibility.isTrusted(prompt: false) {
            showWelcome()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stats.save()
        // Give Caps Lock back to macOS while Monorail isn't running.
        if store.settings.capsLockKey { CapsLockKey.set(false) }
        sliderBar.hideAll(animated: false)
        input.stop()
        trackpad.stop()
        engine.shutdown()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.isFileURL {
            openSharedFile(url)
        }
        for url in urls where !url.isFileURL {
            // monorail://layout/Coding, pair/…, snapshot/…, profile/…, workspace/2, launch/t
            let argument = url.pathComponents.dropFirst().joined(separator: "/").removingPercentEncoding ?? ""
            switch url.host?.lowercased() {
            case "settings": showSettings()
            case "welcome": showWelcome()
            case "palette": palette.show()
            case "layout": engine.applyLayout(named: argument)
            case "snapshot": engine.restoreSnapshot(named: argument)
            case "save-snapshot": engine.saveSnapshot(named: argument.isEmpty ? Self.snapshotName() : argument)
            case "pair":
                if let pair = store.settings.appPairs.first(where: { $0.name.caseInsensitiveCompare(argument) == .orderedSame }) {
                    engine.openPair(pair)
                }
            case "profile":
                if let index = store.settings.profiles.firstIndex(where: { $0.caseInsensitiveCompare(argument) == .orderedSame })
                    ?? Int(argument).map({ $0 - 1 })
                {
                    engine.switchProfile(to: index)
                }
            case "workspace":
                if let n = Int(argument) { engine.switchWorkspace(to: n - 1) }
            case "launch": engine.quickLaunch(argument)
            case "template":
                if let template = store.settings.templates.first(where: { $0.name.caseInsensitiveCompare(argument) == .orderedSame }) {
                    engine.runTemplate(template)
                }
            case "presentation-mode" where argument == "on" || argument == "off":
                engine.setPresenting(argument == "on")
            case "focus-mode" where argument == "on" || argument == "off":
                engine.setFocusMode(argument == "on")
            default:
                if let action = Action(url: url.absoluteString) {
                    engine.perform(action)
                } else {
                    log.error("Unknown URL: \(url.absoluteString)")
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    private func wireUp() {
        store.onChange = { [weak self] settings in self?.apply(settings) }
        store.onRecordingChange = { [weak self] recording in self?.input.isSuspended = recording }

        engine.onStateChange = { [weak self] in
            guard let self else { return }
            self.integrations.update({ [weak self] in self?.currentState() }, settings: self.store.settings)
            self.updateStatusItem()
            self.sliderBar.update()
            self.popover.refresh()
        }
        popover.mapProvider = { [weak self] in
            guard let maps = self?.engine.miniMaps(), !maps.isEmpty else { return nil }
            let mouse = NSEvent.mouseLocation
            return maps.first { map in
                map.screenFrame.minX <= mouse.x && mouse.x < map.screenFrame.maxX
            } ?? maps.first
        }
        popover.controls = SliderPopover.Controls(
            isPaused: { [weak self] in self?.engine.isPaused ?? false },
            resetPairs: { [weak self] in self?.engine.perform(.regroup) },
            togglePause: { [weak self] in self?.engine.togglePause() },
            openSettings: { [weak self] in self?.showSettings() }
        )
        sliderBar.mapsProvider = { [weak self] in
            guard let self, !self.engine.isPresenting else { return [] }
            return self.engine.miniMaps()
        }
        sliderBar.actions = SliderBarController.Actions(
            slide: { [weak self] x, uuid in self?.engine.slide(to: x, displayUUID: uuid) },
            endSlide: { [weak self] in self?.engine.endSlide() },
            focus: { [weak self] id in
                self?.engine.endPeek(keep: true)
                self?.engine.focusAndReveal(id)
            },
            switchWorkspace: { [weak self] index in self?.engine.switchWorkspace(to: index) },
            showOverview: { [weak self] in self?.overview.show() }
        )
        let commands = windowCommands()
        sliderBar.actions.commands = commands
        sliderBar.actions.renameWorkspace = { [weak self] index in self?.overview.showRenaming(index) }
        sliderBar.actions.peek = { [weak self] column, uuid in self?.engine.peek(column: column, displayUUID: uuid) }
        sliderBar.actions.endPeek = { [weak self] in self?.engine.endPeek() }
        sliderBar.actions.park = { [weak self] index in self?.engine.parkWorkspace(index) }
        sliderBar.actions.unpark = { [weak self] index in self?.engine.unparkWorkspace(index) }
        overview.commands = commands
        overview.setWorkspaceName = { [weak self] index, name in
            self?.store.settings.setWorkspaceName(name, at: index)
        }
        overview.setWorkspaceNote = { [weak self] index, note in
            let trimmed = note.trimmingCharacters(in: .whitespaces)
            self?.store.settings.workspaceNotes[String(index)] = trimmed.isEmpty ? nil : trimmed
        }
        overview.toggleFit = { [weak self] key in
            guard let self else { return }
            self.store.settings.setFit(!self.store.settings.isFit(key.workspace), for: key.workspace)
        }
        popover.actions = sliderBar.actions
        updater.$available
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &subscriptions)
        popover.updater = updater
        engine.onShowSwitcher = { [weak self] in self?.switcher.toggle() }
        engine.onShowOverview = { [weak self] in self?.overview.toggle() }
        engine.onNotice = { [weak self] text in
            guard let self, !self.engine.isPresenting, !self.store.settings.quietMode else { return }
            self.toast.show(text)
        }
        engine.onAdjustSettings = { [weak self] change in
            guard let self else { return }
            var settings = self.store.settings
            change(&settings)
            self.store.settings = settings
        }
        engine.onWorkspaceShown = { [weak self] name, index, count in
            guard let self, self.store.settings.workspaceHUD, !self.engine.isPresenting else { return }
            self.workspaceHUD.show(name: name, note: self.engine.workspaceNote(index), index: index, count: count)
        }
        engine.onAskForSlideName = { [weak self] id, current in self?.askForSlideName(id, current: current) }
        engine.onCheatSheet = { [weak self] in self?.cheatSheet.toggle() }
        engine.onAnnounce = { [weak self] text in
            guard self?.store.settings.announceChanges == true else { return }
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
        cheatSheet.keymap = { [weak self] in self?.store.settings.keymap ?? .default }
        input.onKeyActivity = { [weak self] in self?.cheatSheet.keyWasPressed() }
        NotificationCenter.default.addObserver(forName: .monorailCopyDiagnostics, object: nil, queue: .main) { [weak self] _ in
            self?.copyDiagnostics()
        }
        NotificationCenter.default.addObserver(forName: .monorailForgetWholeSlideApp, object: nil, queue: .main) { [weak self] note in
            if let app = note.object as? String { self?.engine.forgetWholeSlideApp(app) }
        }
        WholeSlideApps.list = { [weak self] in self?.engine.wholeSlideApps ?? [] }
        engine.onWindowHints = { [weak self] in self?.showHints() }
        engine.onResizeMode = { [weak self] on in self?.setResizeMode(on) }
        engine.onStripZoom = { [weak self] in self?.stripZoom.toggle() }
        engine.onWindowOpened = { [weak self] id, app, title in
            self?.scripts.emit("windowOpened", ["id": Int(id), "app": app, "title": title])
        }
        stripZoom.mapProvider = { [weak self] in
            guard let maps = self?.engine.miniMaps(), !maps.isEmpty else { return nil }
            let mouse = NSEvent.mouseLocation
            return maps.first { $0.screenFrame.minX <= mouse.x && mouse.x < $0.screenFrame.maxX } ?? maps.first
        }
        stripZoom.focus = { [weak self] id in self?.engine.focusAndReveal(id) }
        input.onPinchProgress = { [weak self] total, ended in self?.stripZoom.pinch(total, ended: ended) }
        trackpad.onVerticalSwipe = { [weak self] up in self?.engine.switchWorkspaceVertically(next: up) }
        meetings.onMeeting = { [weak self] title, link in self?.joinMeeting(title, link) }
        api.handler = { [weak self] method, path, body in self?.handleAPI(method, path, body) }
        scripts.bridge = scriptBridge()
        integrations.onEvent = { [weak self] event, state in
            let payload: [String: Any] = event == "workspaceChanged"
                ? ["index": state.workspace, "name": state.workspaceName, "profile": state.profile]
                : ["app": state.app ?? "", "title": state.title ?? ""]
            self?.scripts.emit(event, payload)
        }
        NotificationCenter.default.addObserver(forName: .monorailReloadScripts, object: nil, queue: .main) { [weak self] _ in
            self?.reloadScripts()
        }
        NotificationCenter.default.addObserver(forName: .monorailRunTemplate, object: nil, queue: .main) { [weak self] note in
            guard let self, let id = note.object as? String,
                let template = self.store.settings.templates.first(where: { $0.id == id })
            else { return }
            self.engine.runTemplate(template)
        }
        engine.onAskForLetter = { [weak self] action in self?.readMarkLetter(for: action) }
        engine.onShowPalette = { [weak self] in self?.palette.toggle() }
        engine.onAskForSnapshotName = { [weak self] in self?.takeSnapshot() }
        engine.onUsage = { [weak self] event in self?.stats.record(event) }
        engine.onLayoutsSaved = { [weak self] in
            if self?.store.settings.syncThroughICloud == true { self?.store.pushToCloud() }
        }
        engine.onPictureInPicture = { [weak self] id in self?.showPictureInPicture(id) }
        store.onLayoutsChanged = { [weak self] in self?.engine.reloadLayouts() }
        palette.commands = { [weak self] in self?.paletteCommands() ?? [] }
        stats.onSuggestion = { [weak self] pair in
            let names = pair.split(separator: "|").map { UsageStats.appName(String($0)) }.joined(separator: " + ")
            self?.toast.show("You often use \(names) together · save them as an app pair in Settings → Insights")
        }
        autoRules.fire = { [weak self] rule in self?.run(rule) }
        pictureInPicture.focus = { [weak self] id in self?.engine.focusAndReveal(id) }
        pictureInPicture.onNeedsPermission = { [weak self] in
            self?.toast.show("Picture in picture needs Screen Recording · turn on live previews in the overview")
        }
        trackpad.onThreeFingerTap = { [weak self] in self?.overview.toggle() }
        radial.preview = { [weak self] position in self?.engine.snapPreview(position) }
        radial.apply = { [weak self] position in self?.engine.snapFocused(position) }
        engine.onRadialMenu = { [weak self] in self?.radial.toggle() }
        engine.onResizeHUD = { [weak self] frame in self?.resizeHUD.show(frame) }
        engine.onShowAppOverview = { [weak self] app in
            let name = self?.engine.allWindowSummaries().first { $0.id == self?.engine.focusedWindowID() }?.appName
            self?.overview.show(onlyApp: app, appName: name)
        }
        input.onFlagsChanged = { [weak self] modifiers in
            guard let self else { return }
            self.radial.modifiersChanged(modifiers)
            self.cheatSheet.modifiersChanged(modifiers, enabled: self.store.settings.cheatSheetOnHold && !self.radial.isShown)
        }
        input.onDragBegin = { [weak self] point, resize in self?.engine.beginModifierDrag(at: point, resize: resize) ?? false }
        input.onDragMove = { [weak self] point in self?.engine.continueModifierDrag(to: point) }
        input.onDragEnd = { [weak self] in self?.engine.endModifierDrag() }
        input.titleBarWindow = { [weak self] point in self?.engine.titleBarWindow(at: point) }
        input.onTitleBarSwipe = { [weak self] swipe, id in self?.engine.titleBarSwipe(swipe, on: id) }
        engine.onWindowDrag = { [weak self] id in self?.snapPicker.windowDragStarted(id) }
        snapPicker.snap = { [weak self] id, position in self?.engine.snapWindow(id, to: position) }
        engine.onResized = { [weak self] id, frame, name, hasOthers in
            self?.resizeAssist.show(for: id, frame: frame, appName: name, hasOthers: hasOthers)
        }
        resizeAssist.actions = ResizeAssist.Actions(
            ownSlide: { [weak self] id in self?.engine.giveOwnSlide(id) },
            othersOut: { [weak self] id in self?.engine.moveOthersOut(keeping: id) },
            undo: { [weak self] in self?.engine.undo() }
        )

        input.isPaused = { [weak self] in self?.engine.isPaused ?? false }
        input.onAction = { [weak self] action in
            self?.practice.record(action)
            self?.engine.perform(action)
        }
        input.onScroll = { [weak self] delta in self?.engine.swipe(by: delta) }
        input.onScrollEnd = { [weak self] in self?.engine.endSwipe() }
        input.onStep = { [weak self] forward in self?.engine.step(forward: forward) }
        input.isOverMenuBar = { [weak self] point in
            // Scrolling over the menu bar or a visible slider bar slides the strip.
            guard !Self.isOverMenuBar(point) else { return true }
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            return self?.sliderBar.contains(CGPoint(x: point.x, y: primaryHeight - point.y)) ?? false
        }
        input.onPinch = { [weak self] open in
            if open { self?.overview.show() } else { self?.overview.close() }
        }
        input.onSlideModeChange = { [weak self] on in
            if on { self?.slideHUD.show() } else { self?.slideHUD.hide() }
        }

        trackpad.onScroll = { [weak self] fraction in
            guard let self else { return }
            // Map trackpad-width fractions to roughly a screen's width per full swipe.
            let width = Double(NSScreen.main?.visibleFrame.width ?? 1440)
            self.engine.swipe(by: -fraction * width * 1.5)
        }
        trackpad.onEnd = { [weak self] in self?.engine.endSwipe() }

        switcher.windows = { [weak self] in self?.engine.allWindowSummaries() ?? [] }
        switcher.choose = { [weak self] id in self?.engine.focusAndReveal(id) }
    }

    private func startEngine() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        input.start()
        engine.start()
        apply(store.settings)
        updateStatusItem()
        store.startCloudSync()
        store.watchFile()
        autoRules.start()
        // After an update: what changed. (Not on a first install.)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        if store.settings.hasCompletedOnboarding, !version.isEmpty, store.settings.lastSeenVersion != version {
            if !store.settings.lastSeenVersion.isEmpty || store.settings.hasCompletedOnboarding {
                whatsNew.show(version: version)
            }
        }
        if store.settings.lastSeenVersion != version { store.settings.lastSeenVersion = version }
        weekly.stats = stats
        weekly.workspaceTitle = { [weak self] index in self?.engine.workspaceTitle(index) ?? "" }
        weekly.isEnabled = { [weak self] in self?.store.settings.weeklySummary ?? false }
        weekly.start()
        // Once a minute, note which apps share slides (for Insights).
        statsTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, self.engine.isRunning, !self.engine.isPaused else { return }
            self.stats.sample(slides: self.engine.slideApps(), slideCount: self.engine.slideCount)
            if let state = self.currentState() {
                self.stats.addMinute(workspace: state.workspaceName, app: state.app)
            }
        }
    }

    /// Polls until the user grants Accessibility, then starts.
    private func waitForPermission() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard Accessibility.isTrusted(prompt: false) else { return }
            self?.startEngine()
        }
    }

    private func apply(_ settings: AppSettings) {
        let syncWasOn = engine.settings.syncThroughICloud
        let liveReloadWasOn = engine.settings.liveReloadSettings
        engine.settings = settings
        WorkspaceColor.theme = settings.theme
        stats.isEnabled = settings.collectStats
        autoRules.rules = settings.autoRules
        if settings.syncThroughICloud != syncWasOn { store.startCloudSync() }
        input.keymap = settings.keymap
        input.modifierSwipe = settings.modifierSwipe
        input.scrollModifier = settings.scrollModifier
        input.scrollOverMenuBar = settings.scrollOverMenuBar
        input.slideTrigger = settings.slideTrigger
        input.pinchForOverview = settings.pinchForOverview
        input.modifierDrag = settings.modifierDrag
        if settings.capsLockKey != capsLockOn {
            capsLockOn = settings.capsLockKey
            CapsLockKey.set(settings.capsLockKey)
            input.capsLockKey = settings.capsLockKey
        }
        updater.betaChannel = settings.betaUpdates
        input.pinchZoomsStrip = settings.pinchZoomsStrip
        trackpad.detectsVertical = settings.verticalWorkspaceSwipes
        meetings.isEnabled = settings.meetingHelper
        Localization.choose(settings.language)
        if settings.localAPI != engine.settings.localAPI || settings.apiPort != engine.settings.apiPort || !apiStarted {
            apiStarted = true
            if settings.localAPI { api.start(port: settings.apiPort) } else { api.stop() }
        }
        if settings.scripts != scriptsOn {
            scriptsOn = settings.scripts
            if settings.scripts { scripts.load() } else { scripts.unload() }
        }
        input.titleBarSwipes = settings.titleBarSwipes
        if settings.liveReloadSettings != liveReloadWasOn { store.watchFile() }
        snapPicker.isEnabled = settings.snapPicker
        updateArrowItems(visible: settings.showNavigationArrows)
        updater.setAutomatic(settings.checkForUpdates)
        updater.installAutomatically = settings.installUpdatesAutomatically
        hotEdges.onSlide = { [weak self] right in self?.engine.step(forward: right, honourReverse: false, visual: true) }
        hotEdges.setEnabled(settings.hotEdges && engine.isRunning)
        sliderBar.compact = settings.compactSlider
        sliderBar.showTitles = settings.sliderTitles
        sliderBar.peekEnabled = settings.peekWithOption
        popover.peekEnabled = settings.peekWithOption
        sliderBar.edge = settings.sliderBarEdge
        sliderBar.update()

        trackpad.fingers = settings.swipeFingers.rawValue
        trackpad.detectsTap = settings.threeFingerTapOverview
        if settings.swipeFingers == .off && !settings.threeFingerTapOverview {
            trackpad.stop()
        } else if engine.isRunning {
            trackpad.start()
        }

        if settings.focusFollowsMouse, mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                let location = NSEvent.mouseLocation
                let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
                self?.engine.mouseMoved(to: CGPoint(x: location.x, y: primaryHeight - location.y))
            }
        } else if !settings.focusFollowsMouse, let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        updateStatusItem()
    }

    /// Quitting from the terminal (or a logout) still puts windows back.
    private func handleTerminationSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: - Menu bar

    /// Left-click opens the slider popover; right-click or ⌃-click opens the menu.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu || !store.settings.iconOpensSlider || !engine.isRunning {
            // Pop the menu up directly: this returns only after the user picks an
            // item (or dismisses it), so the chosen action is always delivered.
            menuNeedsUpdate(statusMenu)
            statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 5), in: sender)
        } else {
            popover.toggle(relativeTo: sender)
        }
    }

    /// True for points (Accessibility coordinates) on any display's menu bar.
    private static func isOverMenuBar(_ point: CGPoint) -> Bool {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return false }
        let cocoa = CGPoint(x: point.x, y: primaryHeight - point.y)
        return NSScreen.screens.contains { screen in
            let frame = screen.frame
            let menuBarHeight = max(frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
            return cocoa.x >= frame.minX && cocoa.x < frame.maxX
                && cocoa.y <= frame.maxY && cocoa.y >= frame.maxY - menuBarHeight
        }
    }

    /// The ‹ › buttons next to the menu bar icon. Created after the main item,
    /// so they sit to its left.
    private func updateArrowItems(visible: Bool) {
        if !visible {
            arrowItems.forEach { NSStatusBar.system.removeStatusItem($0) }
            arrowItems.removeAll()
            return
        }
        guard arrowItems.isEmpty else { return }
        for (symbol, selector, label) in [
            ("chevron.right", #selector(stepRight), "Next window"),
            ("chevron.left", #selector(stepLeft), "Previous window"),
        ] {
            let item = NSStatusBar.system.statusItem(withLength: 22)
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            image?.isTemplate = true
            item.button?.image = image
            item.button?.toolTip = label
            item.button?.target = self
            item.button?.action = selector
            arrowItems.append(item)
        }
    }

    /// Window commands shared by the slider-bar previews, popover and overview.
    private func windowCommands() -> WindowCommands {
        var commands = WindowCommands()
        commands.focus = { [weak self] id in self?.engine.focusAndReveal(id) }
        commands.close = { [weak self] id in self?.engine.closeWindow(id) }
        commands.minimize = { [weak self] id in self?.engine.minimizeWindow(id) }
        commands.fullScreen = { [weak self] id in self?.engine.toggleFullScreen(id) }
        commands.ownSlide = { [weak self] id in self?.engine.giveOwnSlide(id) }
        commands.rename = { [weak self] id in self?.renameWindow(id) }
        commands.moveToWorkspace = { [weak self] id, index in self?.engine.moveWindow(id, toWorkspace: index) }
        commands.workspaceNames = { [weak self] in
            guard let self else { return [] }
            return (0..<self.engine.workspaceCount).map(self.store.settings.workspaceName)
        }
        commands.currentWorkspace = { [weak self] id in self?.engine.workspaceIndex(of: id) }
        commands.setLayout = { [weak self] id, arrangement in self?.engine.setSlideLayout(of: id, to: arrangement) }
        commands.currentLayout = { [weak self] id in self?.engine.slideLayout(of: id) ?? nil }
        commands.customLayouts = { [weak self] in self?.store.settings.customLayouts ?? [] }
        commands.setCustomLayout = { [weak self] id, rows in self?.engine.setSlideLayout(of: id, to: .custom, rows: rows) }
        commands.currentRows = { [weak self] id in self?.engine.slideRows(of: id) }
        commands.saveAppPair = { [weak self] id in self?.saveAppPair(from: id) }
        commands.isSticky = { [weak self] id in self?.engine.isSticky(id) ?? false }
        commands.toggleSticky = { [weak self] id in self?.engine.toggleSticky(id) }
        commands.pictureInPicture = { [weak self] id in self?.showPictureInPicture(id) }
        commands.nameSlide = { [weak self] id in self?.askForSlideName(id, current: self?.engine.slideName(of: id) ?? "") }
        commands.isSlideLocked = { [weak self] id in self?.engine.isSlideLocked(id) ?? false }
        commands.toggleLock = { [weak self] id in self?.engine.toggleLock(id) }
        commands.neverManage = { [weak self] id in self?.neverManage(id) }
        commands.setSize = { [weak self] id, size in self?.engine.setFloatingSize(id, size) }
        return commands
    }

    /// Marks: after the shortcut, the next key typed is the mark's letter.
    /// Marks and quick launch: after the shortcut, the next key typed is the letter.
    private func readMarkLetter(for action: Action) {
        switch action {
        case .setMark: toast.show("Mark this window: type a letter")
        case .quickLaunch: toast.show("Quick launch: type an app’s letter")
        default: toast.show("Jump to mark: type its letter")
        }
        input.captureNextKey = { [weak self] letter in
            guard let self, let letter else { return }
            switch action {
            case .setMark: self.engine.setMark(letter)
            case .quickLaunch: self.engine.quickLaunch(letter)
            default: self.engine.jumpToMark(letter)
            }
        }
    }

    private func showPictureInPicture(_ id: WindowID) {
        let title = engine.allWindowSummaries().first { $0.id == id }.map { $0.title.isEmpty ? $0.appName : $0.title } ?? ""
        pictureInPicture.toggle(id, title: title)
    }

    static func snapshotName() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }

    private func takeSnapshot() {
        guard let name = TextPrompt.ask(
            title: "Take a session snapshot",
            message: "Saves every workspace of every profile and which apps are open. Restore it from Snapshots in the menu bar, even after a restart: Monorail reopens the apps and puts their windows back.",
            initial: Self.snapshotName(), placeholder: "Before the weekend", button: "Save")
        else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        engine.saveSnapshot(named: trimmed.isEmpty ? Self.snapshotName() : trimmed)
    }

    // MARK: - 0.8: hints, resize mode, templates, meetings, sharing, API, scripts, practice

    @objc private func redoLayout() { afterMenu { $0.engine.redo() } }
    @objc private func undoToStep(_ sender: NSMenuItem) {
        let steps = sender.tag
        afterMenu { $0.engine.undo(steps: steps) }
    }
    @objc private func toggleFitFromMenu() { afterMenu { $0.engine.perform(.toggleFitMode) } }
    @objc private func rescueFromMenu() { afterMenu { $0.engine.rescueWindows() } }

    private func askForSlideName(_ id: WindowID, current: String) {
        guard let name = TextPrompt.ask(
            title: "Name this slide",
            message: "Shown in the slider, the overview and the command palette. Leave empty for no name.",
            initial: current, placeholder: "Writing, Review, Call…", button: "Name")
        else { return }
        engine.nameSlide(id, name)
    }

    /// Floats the window's app from now on (a rule in Settings → Apps).
    private func neverManage(_ id: WindowID) {
        guard let window = engine.allWindowSummaries().first(where: { $0.id == id }),
            let bundleID = engine.windowList().first(where: { ($0["id"] as? Int) == Int(id) })?["bundleID"] as? String
        else { return }
        engine.release(id)
        if let index = store.settings.appRules.firstIndex(where: { $0.bundleID == bundleID && !$0.isTitleRule }) {
            store.settings.appRules[index].float = true
        } else {
            store.settings.appRules.append(AppRule(bundleID: bundleID, name: window.appName, float: true))
        }
        toast.show("Monorail leaves \(window.appName) alone now · change it in Settings → Apps")
    }

    private func copyDiagnostics() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        var text = "\(Brand.full) \(version) on macOS \(os)\n"
        text += "Accessibility: \(Accessibility.isTrusted(prompt: false) ? "allowed" : "not allowed"), "
        text += "Screen Recording: \(WindowThumbnails.isAllowed ? "allowed" : "not allowed")\n"
        text += engine.diagnostics()
        text += "\nSettings: grouping \(store.settings.groupByApp), \(store.settings.tilesPerSlide) per slide, "
        text += "\(store.settings.workspaceCount) workspaces, slider bar \(store.settings.sliderBar.rawValue), "
        text += "gaps \(Int(store.settings.layout.gap))/\(Int(store.settings.layout.edgeGap))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        toast.show("Diagnostics copied · paste them into a bug report")
    }

    // MARK: AppleScript

    func scriptPerform(_ name: String) -> Bool {
        guard let action = Action(rawValue: name) else { return false }
        engine.perform(action)
        return true
    }

    func scriptOpen(_ kind: String, _ name: String) -> Bool {
        switch kind {
        case "layout": engine.applyLayout(named: name)
        case "pair":
            guard let pair = store.settings.appPairs.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return false }
            engine.openPair(pair)
        case "template":
            guard let template = store.settings.templates.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return false }
            engine.runTemplate(template)
        case "snapshot": engine.restoreSnapshot(named: name)
        default: return false
        }
        return true
    }

    func scriptState() -> String {
        guard let state = currentState(), let data = try? JSONEncoder().encode(state) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func scriptWindows() -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: engine.windowList(), options: [.sortedKeys]) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    @objc private func togglePresentation() { afterMenu { $0.engine.setPresenting(!$0.engine.isPresenting) } }
    @objc private func stopRecording() { afterMenu { $0.engine.perform(.recordSlide) } }

    private func showHints() {
        let map = hints.show(engine.visibleWindowFrames())
        guard !map.isEmpty else {
            toast.show("No windows on screen")
            return
        }
        input.captureNextKey = { [weak self] letter in
            self?.hints.hide()
            guard let letter, let id = map[letter] else { return }
            self?.engine.focusAndReveal(id)
        }
    }

    /// Resize mode: ← → width, ↑ ↓ the main share, 1–9 tenths, 0 full width; esc or return ends it.
    private func setResizeMode(_ on: Bool) {
        resizeModeTimer?.invalidate()
        guard on else {
            input.keyInterceptor = nil
            return
        }
        toast.show("Resize mode · ← → width · ↑ ↓ split · 1–9 tenths · 0 full · esc when done")
        let restart = { [weak self] in
            self?.resizeModeTimer?.invalidate()
            self?.resizeModeTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { _ in self?.setResizeMode(false) }
        }
        restart()
        input.keyInterceptor = { [weak self] keyCode, modifiers in
            guard let self else { return false }
            if keyCode == KeyCode.escape || keyCode == KeyCode.returnKey {
                DispatchQueue.main.async { self.setResizeMode(false) }
                return true
            }
            guard modifiers.isEmpty || modifiers == [.shift] else { return false }
            // The event tap runs on the main thread, so the engine can be asked directly.
            let handled = self.engine.resizeKey(keyCode)
            DispatchQueue.main.async { if handled { restart() } else { self.setResizeMode(false) } }
            return handled
        }
    }

    /// Templates ▸ each template to start.
    private func templatesMenu() -> NSMenuItem {
        let menu = NSMenu()
        for template in store.settings.templates {
            let entry = item(template.name, #selector(runTemplateFromMenu(_:)))
            entry.representedObject = template.id
            menu.addItem(entry)
        }
        let parent = NSMenuItem(title: L("Templates"), action: nil, keyEquivalent: "")
        parent.submenu = menu
        return parent
    }

    @objc private func runTemplateFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
            let template = store.settings.templates.first(where: { $0.id == id })
        else { return }
        afterMenu { $0.engine.runTemplate(template) }
    }

    private func joinMeeting(_ title: String, _ link: URL) {
        if let profile = store.settings.meetingProfile { engine.switchProfile(to: profile) }
        NSWorkspace.shared.open(link)
        toast.show("Joining “\(title)”")
    }

    // MARK: Sharing layouts

    /// A shared layout or template file (.monorail).
    struct SharedFile: Codable {
        var kind: String
        var layout: SavedLayout?
        var template: WorkspaceTemplate?
        var appPair: AppPair?
    }

    @objc private func shareLayout(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let layout = engine.layouts.first(where: { $0.name == name })
        else { return }
        export(SharedFile(kind: "layout", layout: layout), suggested: name)
    }

    func shareTemplate(_ template: WorkspaceTemplate) {
        export(SharedFile(kind: "template", template: template), suggested: template.name)
    }

    private func export(_ file: SharedFile, suggested: String) {
        afterMenu { _ in
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "\(suggested).monorail"
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? encoder.encode(file).write(to: url, options: .atomic)
        }
    }

    /// Double-clicking a .monorail file: a layout is saved and applied, a template added and started.
    private func openSharedFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(SharedFile.self, from: data) else {
            toast.show("That isn’t a Monorail layout file")
            return
        }
        if let layout = file.layout {
            engine.importLayout(layout)
            engine.applyLayout(named: layout.name)
        } else if let template = file.template {
            store.settings.templates.removeAll { $0.name == template.name }
            store.settings.templates.append(template)
            engine.runTemplate(template)
        } else if let pair = file.appPair {
            store.settings.appPairs.removeAll { $0.name == pair.name }
            store.settings.appPairs.append(pair)
            engine.openPair(pair)
        }
    }

    // MARK: Local API

    private func handleAPI(_ method: String, _ path: [String], _ body: [String: Any]) -> Any? {
        func int(_ key: String) -> Int? { (body[key] as? Int) ?? (body[key] as? String).flatMap { Int($0) } }
        func text(_ key: String) -> String? { body[key] as? String }
        switch (method, path.first ?? "") {
        case ("GET", "state"):
            guard let state = currentState(), let data = try? JSONEncoder().encode(state),
                let object = try? JSONSerialization.jsonObject(with: data)
            else { return [String: Any]() }
            return object
        case ("GET", "windows"):
            return engine.windowList()
        case ("GET", "workspaces"):
            let windows = engine.windowList()
            return (0..<engine.workspaceCount).map { index -> [String: Any] in
                ["number": index + 1, "name": store.settings.workspaceName(index),
                 "windows": windows.filter { ($0["workspace"] as? Int) == index + 1 }.count]
            }
        case ("GET", "layouts"):
            return engine.layouts.map(\.name)
        case ("GET", "pairs"):
            return store.settings.appPairs.map(\.name)
        case ("GET", "templates"):
            return store.settings.templates.map(\.name)
        case ("GET", "snapshots"):
            return engine.snapshots.map(\.name)
        case ("GET", "actions"):
            return Action.allCases.map { ["name": $0.rawValue, "title": $0.title] }
        case ("POST", "action"):
            guard let name = text("action") ?? path.dropFirst().first, let action = Action(rawValue: name) else {
                return ["error": "Unknown action"]
            }
            engine.perform(action)
            return ["ok": true]
        case ("POST", "focus"):
            guard let id = int("id") else { return ["error": "Needs id"] }
            engine.focusAndReveal(WindowID(id))
            return ["ok": true]
        case ("POST", "move"):
            guard let id = int("id"), let workspace = int("workspace") else { return ["error": "Needs id and workspace"] }
            engine.moveWindow(WindowID(id), toWorkspace: workspace - 1)
            return ["ok": true]
        case ("POST", "pair"):
            let ids = (body["ids"] as? [Int] ?? []).map { WindowID($0) }
            let arrangement = text("layout").flatMap(Arrangement.init(rawValue:)) ?? .columns
            return ["ok": engine.pairWindows(ids, arrangement: arrangement)]
        case ("POST", "workspace"):
            guard let number = int("number") else { return ["error": "Needs number"] }
            engine.switchWorkspace(to: number - 1)
            return ["ok": true]
        case ("POST", "layout"):
            engine.applyLayout(named: text("name") ?? "")
            return ["ok": true]
        case ("POST", "pair-name"):
            guard let pair = store.settings.appPairs.first(where: { $0.name.caseInsensitiveCompare(text("name") ?? "") == .orderedSame })
            else { return ["error": "No such app pair"] }
            engine.openPair(pair)
            return ["ok": true]
        case ("POST", "template"):
            guard let template = store.settings.templates.first(where: { $0.name.caseInsensitiveCompare(text("name") ?? "") == .orderedSame })
            else { return ["error": "No such template"] }
            engine.runTemplate(template)
            return ["ok": true]
        case ("POST", "snapshot"):
            engine.restoreSnapshot(named: text("name") ?? "")
            return ["ok": true]
        default:
            return nil
        }
    }

    // MARK: Scripts

    private func scriptBridge() -> ScriptHost.Bridge {
        ScriptHost.Bridge(
            perform: { [weak self] name in if let action = Action(rawValue: name) { self?.engine.perform(action) } },
            focus: { [weak self] id in self?.engine.focusAndReveal(id) },
            moveToWorkspace: { [weak self] id, index in self?.engine.moveWindow(id, toWorkspace: index) },
            park: { [weak self] index in self?.engine.parkWorkspace(index) },
            openPair: { [weak self] name in
                guard let self, let pair = self.store.settings.appPairs.first(where: { $0.name == name }) else { return }
                self.engine.openPair(pair)
            },
            applyLayout: { [weak self] name in self?.engine.applyLayout(named: name) },
            notify: { [weak self] text in self?.toast.show(text) },
            windows: { [weak self] in self?.engine.windowList() ?? [] },
            state: { [weak self] in
                guard let state = self?.currentState(), let data = try? JSONEncoder().encode(state),
                    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return [:] }
                return object
            })
    }

    func reloadScripts() {
        guard store.settings.scripts else { return }
        scripts.load()
        toast.show("Scripts reloaded")
    }

    // MARK: Practice windows

    /// Three of Monorail's own windows to try the moves on, tiled like real ones.
    func openDemoWindows() {
        closeDemoWindows()
        let colours: [NSColor] = [.systemBlue, .systemPink, .systemOrange]
        for (index, colour) in colours.enumerated() {
            let window = NSWindow(
                contentRect: NSRect(x: 200 + index * 40, y: 200, width: 640, height: 480),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Practice window \(index + 1)"
            window.isReleasedWhenClosed = false
            let label = NSTextField(labelWithString: "Practice window \(index + 1)\n\nTry ⌃⌥← ⌃⌥→ to move between windows,\n⌃⌥R for width, ⌃⌥O for the overview.")
            label.alignment = .center
            label.font = .systemFont(ofSize: 18, weight: .semibold)
            label.textColor = .white
            let view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = colour.withAlphaComponent(0.85).cgColor
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            demoWindows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            for window in self?.demoWindows ?? [] { self?.engine.adoptDemoWindow(window.windowNumber) }
        }
    }

    func closeDemoWindows() {
        engine.forgetDemoWindows()
        demoWindows.forEach { $0.close() }
        demoWindows.removeAll()
    }

    /// What status bars and scripts see (state.json, the event script).
    private func currentState() -> Integrations.State? {
        guard let status = engine.status() else { return nil }
        let focused = engine.focusedWindowID().flatMap { id in engine.allWindowSummaries().first { $0.id == id } }
        return Integrations.State(
            workspace: status.workspace, workspaceName: store.settings.workspaceName(status.workspace - 1),
            workspaceCount: engine.workspaceCount, profile: engine.profileName,
            slide: status.focusedColumn, slides: status.columnCount,
            app: focused?.appName, title: focused?.title, focusMode: engine.isFocusMode)
    }

    /// Runs an auto rule: its profile, then its layout.
    private func run(_ rule: AutoRule) {
        if let profile = rule.profile { engine.switchProfile(to: profile) }
        if let layout = rule.layout, !layout.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.engine.applyLayout(named: layout) }
        }
        toast.show("Auto rule · \(rule.name)")
    }

    /// Everything the command palette offers, built fresh each time it opens.
    private func paletteCommands() -> [PaletteCommand] {
        var list: [PaletteCommand] = []
        let settings = store.settings
        for window in engine.allWindowSummaries() {
            list.append(PaletteCommand(
                id: "window-\(window.id)", title: window.title.isEmpty ? window.appName : window.title,
                subtitle: "Go to window · \(window.appName)", symbol: "macwindow", keywords: "focus go window \(window.appName)"
            ) { [weak self] in self?.engine.focusAndReveal(window.id) })
        }
        for index in 0..<engine.workspaceCount {
            let name = settings.workspaceName(index)
            list.append(PaletteCommand(
                id: "ws-\(index)", title: "Go to \(name)", subtitle: "Workspace \(index + 1)", symbol: "square.stack",
                keywords: "workspace switch"
            ) { [weak self] in self?.engine.switchWorkspace(to: index) })
            list.append(PaletteCommand(
                id: "move-ws-\(index)", title: "Move window to \(name)", subtitle: "Workspace \(index + 1)",
                symbol: "arrow.right.square", keywords: "workspace send"
            ) { [weak self] in
                if let id = self?.engine.focusedWindowID() { self?.engine.moveWindow(id, toWorkspace: index) }
            })
            let parked = engine.isParked(index)
            list.append(PaletteCommand(
                id: "park-\(index)", title: "\(parked ? "Bring back" : "Park") \(name)",
                subtitle: parked ? "Restore its windows from the Dock" : "Minimise its windows to the Dock",
                symbol: "parkingsign.circle", keywords: "park unpark dock"
            ) { [weak self] in
                if parked { self?.engine.unparkWorkspace(index) } else { self?.engine.parkWorkspace(index) }
            })
        }
        for pair in settings.appPairs {
            list.append(PaletteCommand(
                id: "pair-\(pair.id)", title: "Open pair \(pair.name)", subtitle: "App pair", symbol: "rectangle.split.2x1",
                keywords: "pair apps \(pair.bundleIDs.map(UsageStats.appName).joined(separator: " "))"
            ) { [weak self] in self?.engine.openPair(pair) })
        }
        for layout in engine.layouts {
            list.append(PaletteCommand(
                id: "layout-\(layout.name)", title: "Apply layout \(layout.name)", subtitle: "Saved layout",
                symbol: "square.grid.2x2", keywords: "layout"
            ) { [weak self] in self?.engine.applyLayout(named: layout.name) })
        }
        for (title, size) in standardSizes {
            list.append(PaletteCommand(
                id: "size-\(title)", title: "Size window to \(title)", subtitle: "Floats it, centred · for recordings",
                symbol: "rectangle.dashed", keywords: "size resize record screenshot"
            ) { [weak self] in
                if let id = self?.engine.focusedWindowID() { self?.engine.setFloatingSize(id, size) }
            })
        }
        for template in settings.templates {
            list.append(PaletteCommand(
                id: "template-\(template.id)", title: "Start template \(template.name)", subtitle: "Workspace template",
                symbol: "square.on.square", keywords: "template start"
            ) { [weak self] in self?.engine.runTemplate(template) })
        }
        for slide in engine.recentSlides().dropFirst() {
            list.append(PaletteCommand(
                id: "recent-\(slide.window)", title: "Back to \(slide.title)", subtitle: "Recent slide",
                symbol: "clock.arrow.circlepath", keywords: "recent slide back"
            ) { [weak self] in self?.engine.focusAndReveal(slide.window) })
        }
        for snapshot in engine.snapshots {
            list.append(PaletteCommand(
                id: "snapshot-\(snapshot.name)", title: "Restore snapshot \(snapshot.name)", subtitle: "Session snapshot",
                symbol: "camera.viewfinder", keywords: "snapshot session restore"
            ) { [weak self] in self?.engine.restoreSnapshot(named: snapshot.name) })
        }
        for (index, profile) in settings.profiles.enumerated() where settings.profiles.count > 1 {
            list.append(PaletteCommand(
                id: "profile-\(index)", title: "Switch to profile \(profile)", subtitle: "Profile",
                symbol: "person.crop.rectangle.stack", keywords: "profile"
            ) { [weak self] in self?.engine.switchProfile(to: index) })
        }
        for (letter, bundleID) in settings.launchSlots.sorted(by: { $0.key < $1.key }) {
            list.append(PaletteCommand(
                id: "launch-\(letter)", title: "Open \(UsageStats.appName(bundleID))", subtitle: "Quick launch · \(letter.uppercased())",
                symbol: "app.badge", keywords: "launch app"
            ) { [weak self] in self?.engine.quickLaunch(letter) })
        }
        for action in Action.allCases where action.columnNumber == nil && action.workspaceNumber == nil
            && action.moveToWorkspaceNumber == nil && action != .commandPalette
        {
            let keys = settings.keymap.shortcuts(for: action).first?.displayString ?? ""
            list.append(PaletteCommand(
                id: "action-\(action.rawValue)", title: action.title, subtitle: keys, symbol: "keyboard",
                keywords: action.rawValue.replacingOccurrences(of: "-", with: " ")
            ) { [weak self] in self?.engine.perform(action) })
        }
        list.append(PaletteCommand(id: "settings", title: "Open Settings", symbol: "gearshape") { [weak self] in
            self?.showSettings()
        })
        return list
    }

    private func saveAppPair(from id: WindowID) {
        guard var pair = engine.appPair(from: id) else {
            toast.show("A pair needs windows of at least two apps in one slide")
            return
        }
        guard let name = TextPrompt.ask(
            title: "Save app pair",
            message: "Open these apps side by side in one slide any time, from App Pairs in the menu bar.",
            initial: pair.name, placeholder: pair.name, button: "Save")
        else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { pair.name = trimmed }
        store.settings.appPairs.removeAll { $0.name == pair.name }
        store.settings.appPairs.append(pair)
        toast.show("Saved app pair “\(pair.name)”")
    }

    private func renameWindow(_ id: WindowID) {
        let current = engine.allWindowSummaries().first { $0.id == id }
        guard let name = TextPrompt.ask(
            title: "Rename window",
            message: "Shown in Monorail’s previews, overview and menus. Leave empty to use the window’s own title.",
            initial: engine.customName(of: id) ?? "",
            placeholder: current?.title ?? "")
        else { return }
        engine.rename(id, to: name)
    }

    @objc private func stepLeft() { engine.step(forward: false, honourReverse: false, visual: true) }
    @objc private func stepRight() { engine.step(forward: true, honourReverse: false, visual: true) }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusMenu.delegate = self
        statusMenu.autoenablesItems = false
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.toolTip = Brand.full
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        button.image = StatusIcon.image(paused: engine.isPaused, badge: updater.available != nil)
        button.imagePosition = .imageLeading
        if store.settings.showColumnIndicator, !engine.isPaused, let status = engine.status() {
            var position = "\(status.focusedColumn)/\(status.columnCount)"
            switch store.settings.menuBarStyle {
            case .dots where status.columnCount > 0 && status.columnCount <= 9:
                position = (1...status.columnCount).map { $0 == status.focusedColumn ? "●" : "○" }.joined()
            case .number:
                position = engine.workspaceCount > 1 ? "\(status.workspace)" : "\(status.focusedColumn)"
            default:
                break
            }
            var title = engine.workspaceCount > 1 && store.settings.menuBarStyle != .number
                ? " \(status.workspace) · \(position)" : " \(position)"
            if store.settings.menuBarShowsApp, let app = engine.focusedAppName { title = " \(app) ·" + title }
            if engine.isFocusMode { title = " ◉" + title }
            if engine.isRecording { title = " ● REC" + title }
            button.title = title
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)
        } else {
            button.title = ""
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let trusted = Accessibility.isTrusted(prompt: false)

        let header = NSMenuItem(title: headerTitle(trusted: trusted), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if let release = updater.available {
            let update = item("Update to Monorail \(release.version)…", #selector(installUpdate))
            update.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
            menu.addItem(update)
        }

        if !trusted {
            menu.addItem(item("Grant Accessibility Access…", #selector(showWelcomeFromMenu)))
        }

        let windows = engine.activeStripWindows()
        if !windows.isEmpty {
            menu.addItem(.separator())
            for (index, window) in windows.enumerated() {
                let title = window.title.isEmpty ? window.appName : "\(window.appName) — \(window.title)"
                let entry = item("\(index + 1). \(title)", #selector(focusWindowFromMenu(_:)))
                entry.tag = Int(window.id)
                entry.state = window.isFocused ? .on : .off
                entry.image = window.icon.map { icon in
                    let copy = icon.copy() as! NSImage
                    copy.size = NSSize(width: 16, height: 16)
                    return copy
                }
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())
        menu.addItem(
            item(engine.isPaused ? L("Resume Tiling") : L("Pause Tiling"), #selector(togglePause), action: .togglePause))
        menu.addItem(item(L("Overview"), #selector(showOverview), action: .overview))
        menu.addItem(item(L("Search Windows…"), #selector(showSwitcher), action: .windowSwitcher))
        menu.addItem(item(L("Command Palette…"), #selector(showPalette), action: .commandPalette))
        let focusItem = item(
            engine.isFocusMode ? L("End Focus Mode") : L("Focus Mode"), #selector(toggleFocusMode), action: .toggleFocusMode)
        if let ends = engine.focusEnds {
            focusItem.toolTip = "Ends at \(DateFormatter.localizedString(from: ends, dateStyle: .none, timeStyle: .short))"
        }
        menu.addItem(focusItem)
        menu.addItem(item(L("Reset to Smart Pairs"), #selector(regroup), action: .regroup))
        menu.addItem(savedLayoutsMenu())
        menu.addItem(appPairsMenu())
        menu.addItem(snapshotsMenu())
        if !store.settings.templates.isEmpty { menu.addItem(templatesMenu()) }
        let recent = engine.recentSlides()
        if recent.count > 1 {
            let list = NSMenu()
            for slide in recent.dropFirst() {
                let entry = item(slide.title, #selector(focusWindowFromMenu(_:)))
                entry.tag = Int(slide.window)
                list.addItem(entry)
            }
            let parent = NSMenuItem(title: L("Recent Slides"), action: nil, keyEquivalent: "")
            parent.submenu = list
            menu.addItem(parent)
        }
        menu.addItem(item(
            engine.isPresenting ? L("End Presentation Mode") : L("Presentation Mode"), #selector(togglePresentation),
            action: .presentationMode))
        if engine.isRecording { menu.addItem(item(L("Stop Recording"), #selector(stopRecording), action: .recordSlide)) }
        let undoItem = item(L("Undo Layout Change"), #selector(undoLayout), action: .undo)
        undoItem.isEnabled = engine.canUndo
        menu.addItem(undoItem)
        let redoItem = item("Redo Layout Change", #selector(redoLayout), action: .redo)
        redoItem.isEnabled = engine.canRedo
        menu.addItem(redoItem)
        let changes = engine.undoHistory()
        if !changes.isEmpty {
            let timeline = NSMenu()
            let time = DateFormatter()
            time.timeStyle = .short
            for (index, change) in changes.enumerated() {
                let entry = item("\(change.label) · \(time.string(from: change.date))", #selector(undoToStep(_:)))
                entry.tag = index + 1
                entry.toolTip = index == 0 ? "Undo just this change" : "Undo this change and the \(index) after it"
                timeline.addItem(entry)
            }
            let parent = NSMenuItem(title: "Undo History", action: nil, keyEquivalent: "")
            parent.submenu = timeline
            menu.addItem(parent)
        }
        let fitItem = item("Fit Every Slide on Screen", #selector(toggleFitFromMenu), action: .toggleFitMode)
        if let status = engine.status() { fitItem.state = store.settings.isFit(status.workspace - 1 + engine.activeProfile * 100) ? .on : .off }
        menu.addItem(fitItem)
        menu.addItem(item(L("Retile Windows"), #selector(retile), action: .retile))
        menu.addItem(item("Rescue Windows", #selector(rescueFromMenu), action: .rescueWindows))

        let workspaceCount = engine.workspaceCount
        if workspaceCount > 1 {
            let workspaces = NSMenu()
            workspaces.autoenablesItems = false
            let current = engine.status()?.workspace
            for n in 1...workspaceCount {
                let action = Action.allCases.first { $0.workspaceNumber == n }!
                var title = store.settings.workspaceName(n - 1)
                if engine.isParked(n - 1) { title += " (parked)" }
                let entry = item(title, #selector(switchWorkspaceFromMenu(_:)), action: action)
                entry.tag = n
                entry.state = current == n ? .on : .off
                workspaces.addItem(entry)
            }
            workspaces.addItem(.separator())
            let park = NSMenu()
            for n in 1...workspaceCount {
                let parked = engine.isParked(n - 1)
                let entry = item(
                    "\(parked ? "Bring Back" : "Park") \(store.settings.workspaceName(n - 1))",
                    #selector(toggleParkFromMenu(_:)))
                entry.tag = n
                park.addItem(entry)
            }
            let parkParent = NSMenuItem(title: L("Park Workspace"), action: nil, keyEquivalent: "")
            parkParent.submenu = park
            parkParent.toolTip = "Minimise a workspace’s windows to the Dock and bring them back to the same slides later"
            workspaces.addItem(parkParent)
            let parent = NSMenuItem(title: L("Workspaces"), action: nil, keyEquivalent: "")
            parent.submenu = workspaces
            menu.addItem(parent)
        }
        if store.settings.profiles.count > 1 {
            let profiles = NSMenu()
            for (index, name) in store.settings.profiles.enumerated() {
                let entry = item(name, #selector(switchProfileFromMenu(_:)))
                entry.tag = index
                entry.state = engine.activeProfile == index ? .on : .off
                profiles.addItem(entry)
            }
            let parent = NSMenuItem(title: "Profile: \(engine.profileName)", action: nil, keyEquivalent: "")
            parent.submenu = profiles
            menu.addItem(parent)
        }

        menu.addItem(.separator())
        menu.addItem(item(L("Settings…"), #selector(showSettingsFromMenu), key: ","))
        menu.addItem(shortcutsMenu())
        menu.addItem(item(L("Welcome Tour…"), #selector(showWelcomeFromMenu)))
        menu.addItem(item(L("Check for Updates…"), #selector(checkForUpdates)))
        menu.addItem(item("About \(Brand.full)", #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(item(L("Quit Monorail"), #selector(quit), key: "q"))
    }

    /// Every shortcut, so nobody has to remember them. Choosing one runs it.
    private func shortcutsMenu() -> NSMenuItem {
        let menu = NSMenu()
        let slide = NSMenuItem(
            title: store.settings.slideTrigger == .off
                ? "Slide mode is off"
                : "Tap \(store.settings.slideTrigger.title) for slide mode, then ← → R F C…",
            action: nil, keyEquivalent: "")
        slide.isEnabled = false
        menu.addItem(slide)
        menu.addItem(.separator())
        for action in Action.allCases where action.columnNumber == nil {
            let shortcuts = store.settings.keymap.shortcuts(for: action).map(\.displayString)
            let title = shortcuts.isEmpty ? action.title : "\(action.title)    \(shortcuts.joined(separator: "  "))"
            let entry = NSMenuItem(title: title, action: #selector(performFromMenu(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = action.rawValue
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(item(L("Change Shortcuts…"), #selector(showShortcuts)))
        let parent = NSMenuItem(title: L("Keyboard Shortcuts"), action: nil, keyEquivalent: "")
        parent.submenu = menu
        return parent
    }

    @objc private func performFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = Action(rawValue: raw) else { return }
        // Let the menu close and focus return to the previous app first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.engine.perform(action) }
    }

    @objc private func switchWorkspaceFromMenu(_ sender: NSMenuItem) {
        let index = sender.tag - 1
        afterMenu { $0.engine.switchWorkspace(to: index) }
    }

    @objc private func showOverview() { overview.show() }
    @objc private func showPalette() { afterMenu { $0.palette.show() } }
    @objc private func toggleFocusMode() { afterMenu { $0.engine.setFocusMode(!$0.engine.isFocusMode) } }

    /// Snapshots ▸ Take Snapshot…, each snapshot to restore, and Delete ▸.
    private func snapshotsMenu() -> NSMenuItem {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item(L("Take Snapshot…"), #selector(takeSnapshotFromMenu), action: .takeSnapshot))
        let snapshots = engine.snapshots
        if !snapshots.isEmpty {
            menu.addItem(.separator())
            for snapshot in snapshots {
                let entry = item(snapshot.name, #selector(restoreSnapshotFromMenu(_:)))
                entry.representedObject = snapshot.name
                entry.toolTip = "\(snapshot.windowCount) windows, \(snapshot.apps?.count ?? 0) apps"
                menu.addItem(entry)
            }
            menu.addItem(.separator())
            let delete = NSMenu()
            for snapshot in snapshots {
                let entry = item(snapshot.name, #selector(deleteLayout(_:)))
                entry.representedObject = snapshot.name
                delete.addItem(entry)
            }
            let parent = NSMenuItem(title: L("Delete"), action: nil, keyEquivalent: "")
            parent.submenu = delete
            menu.addItem(parent)
        }
        let parent = NSMenuItem(title: L("Snapshots"), action: nil, keyEquivalent: "")
        parent.submenu = menu
        return parent
    }

    @objc private func takeSnapshotFromMenu() { afterMenu { $0.takeSnapshot() } }

    @objc private func restoreSnapshotFromMenu(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        afterMenu { $0.engine.restoreSnapshot(named: name) }
    }

    @objc private func toggleParkFromMenu(_ sender: NSMenuItem) {
        let index = sender.tag - 1
        afterMenu { delegate in
            if delegate.engine.isParked(index) {
                delegate.engine.unparkWorkspace(index)
            } else {
                delegate.engine.parkWorkspace(index)
            }
        }
    }

    @objc private func switchProfileFromMenu(_ sender: NSMenuItem) {
        let index = sender.tag
        afterMenu { $0.engine.switchProfile(to: index) }
    }

    /// App Pairs ▸ each saved pair, to open its apps in one slide.
    private func appPairsMenu() -> NSMenuItem {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let pairs = store.settings.appPairs
        if pairs.isEmpty {
            let hint = NSMenuItem(
                title: "Right-click a slide’s preview ▸ Save Slide as App Pair", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }
        for pair in pairs {
            let entry = item(pair.name, #selector(openPairFromMenu(_:)))
            entry.representedObject = pair.id
            entry.image = NSImage(systemSymbolName: pair.arrangement.symbol, accessibilityDescription: nil)
            menu.addItem(entry)
        }
        if !pairs.isEmpty {
            menu.addItem(.separator())
            let delete = NSMenu()
            for pair in pairs {
                let entry = item(pair.name, #selector(deletePairFromMenu(_:)))
                entry.representedObject = pair.id
                delete.addItem(entry)
            }
            let parent = NSMenuItem(title: L("Delete"), action: nil, keyEquivalent: "")
            parent.submenu = delete
            menu.addItem(parent)
        }
        let parent = NSMenuItem(title: L("App Pairs"), action: nil, keyEquivalent: "")
        parent.submenu = menu
        return parent
    }

    @objc private func openPairFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
            let pair = store.settings.appPairs.first(where: { $0.id == id })
        else { return }
        afterMenu { $0.engine.openPair(pair) }
    }

    @objc private func deletePairFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        store.settings.appPairs.removeAll { $0.id == id }
    }
    @objc private func regroup() { afterMenu { $0.engine.perform(.regroup) } }
    @objc private func installUpdate() { afterMenu { $0.updater.installAvailable() } }

    /// Saved Layouts ▸ Save Current Layout…, each saved layout, and Delete ▸.
    private func savedLayoutsMenu() -> NSMenuItem {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item(L("Save Current Layout…"), #selector(saveLayout)))
        let layouts = engine.layouts
        if !layouts.isEmpty {
            menu.addItem(.separator())
            for layout in layouts {
                let entry = item(layout.name, #selector(applyLayout(_:)))
                entry.representedObject = layout.name
                entry.toolTip = "\(layout.windowCount) windows in \(layout.workspaces.count) workspace(s)"
                menu.addItem(entry)
            }
            menu.addItem(.separator())
            let delete = NSMenu()
            let share = NSMenu()
            for layout in layouts {
                let entry = item(layout.name, #selector(shareLayout(_:)))
                entry.representedObject = layout.name
                share.addItem(entry)
            }
            let shareParent = NSMenuItem(title: L("Share Layout…"), action: nil, keyEquivalent: "")
            shareParent.submenu = share
            menu.addItem(shareParent)
            for layout in layouts {
                let entry = item(layout.name, #selector(deleteLayout(_:)))
                entry.representedObject = layout.name
                delete.addItem(entry)
            }
            let parent = NSMenuItem(title: L("Delete"), action: nil, keyEquivalent: "")
            parent.submenu = delete
            menu.addItem(parent)
        }
        let parent = NSMenuItem(title: L("Saved Layouts"), action: nil, keyEquivalent: "")
        parent.submenu = menu
        return parent
    }

    @objc private func saveLayout() {
        afterMenu { delegate in
            guard let name = TextPrompt.ask(
                title: "Save layout",
                message: "Saves how the windows on this display are arranged in every workspace. Apply it any time from Saved Layouts.",
                initial: "", placeholder: "Coding, Writing, Meetings…", button: "Save"),
                !name.trimmingCharacters(in: .whitespaces).isEmpty
            else { return }
            delegate.engine.saveLayout(named: name.trimmingCharacters(in: .whitespaces))
        }
    }

    @objc private func applyLayout(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        afterMenu { $0.engine.applyLayout(named: name) }
    }

    @objc private func deleteLayout(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        afterMenu { $0.engine.deleteLayout(named: name) }
    }
    @objc private func undoLayout() { afterMenu { $0.engine.undo() } }

    /// Runs `work` once the menu has fully closed, so window moves and focus
    /// changes don't race the menu's own teardown.
    private func afterMenu(_ work: @escaping (AppDelegate) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            work(self)
        }
    }
    @objc private func checkForUpdates() { updater.check(userInitiated: true) }

    private func headerTitle(trusted: Bool) -> String {
        if !trusted { return "Monorail needs Accessibility access" }
        if engine.isPaused { return "Monorail is paused" }
        if let status = engine.status() {
            let workspace = engine.workspaceCount > 1
                ? "\(store.settings.workspaceName(status.workspace - 1)) · " : ""
            if status.columnCount == 0 { return "\(workspace)No windows yet" }
            return "\(workspace)Slide \(status.focusedColumn) of \(status.columnCount)"
        }
        return "Monorail is running"
    }

    private func item(_ title: String, _ selector: Selector, key: String = "", action: Action? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        if let action, let shortcut = store.settings.keymap.shortcuts(for: action).first,
            let character = menuKeyEquivalent(for: shortcut.keyCode)
        {
            item.keyEquivalent = character
            var mask: NSEvent.ModifierFlags = []
            if shortcut.modifiers.contains(.control) { mask.insert(.control) }
            if shortcut.modifiers.contains(.option) { mask.insert(.option) }
            if shortcut.modifiers.contains(.shift) { mask.insert(.shift) }
            if shortcut.modifiers.contains(.command) { mask.insert(.command) }
            item.keyEquivalentModifierMask = mask
        }
        return item
    }

    /// A menu key equivalent for display, for letter keys and Escape/Space.
    private func menuKeyEquivalent(for keyCode: UInt16) -> String? {
        if keyCode == KeyCode.escape { return "\u{1b}" }
        if keyCode == KeyCode.space { return " " }
        let name = KeyCode.name(for: keyCode)
        return name.count == 1 ? name.lowercased() : nil
    }

    @objc private func togglePause() { afterMenu { $0.engine.togglePause() } }
    @objc private func retile() { afterMenu { $0.engine.retile() } }
    @objc private func showSwitcher() { switcher.show() }
    @objc private func showSettingsFromMenu() { showSettings() }
    @objc private func showWelcomeFromMenu() { showWelcome() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func focusWindowFromMenu(_ sender: NSMenuItem) {
        let id = WindowID(sender.tag)
        afterMenu { $0.engine.focusAndReveal(id) }
    }

    @objc private func showShortcuts() {
        navigation.tab = .shortcuts
        showSettings()
    }

    @objc private func showAbout() {
        navigation.tab = .about
        showSettings()
    }

    // MARK: - Windows

    private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(
                store: store,
                navigation: navigation,
                stats: stats,
                isPaused: { [weak self] in self?.engine.isPaused ?? false },
                setPaused: { [weak self] in self?.engine.setPaused($0) }
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "\(Brand.full) — Settings"
            // Closing Settings mid-recording must not leave shortcuts paused.
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in self?.store.stopRecording() }
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        present(settingsWindow!)
    }

    private func showWelcome() {
        if welcomeWindow == nil {
            var view = WelcomeView(store: store, practice: practice) { [weak self] in
                guard let self else { return }
                self.store.settings.hasCompletedOnboarding = true
                self.closeDemoWindows()
                self.welcomeWindow?.close()
            }
            view.practiceWindows = { [weak self] open in
                if open { self?.openDemoWindows() } else { self?.closeDemoWindows() }
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Welcome to \(Brand.full)"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            welcomeWindow = window
        }
        present(welcomeWindow!)
        // Coach tips stay up while you try things out (also after the tour
        // closes), until every practice step is done or ten minutes pass.
        if practice.next != nil, Accessibility.isTrusted(prompt: false) {
            coach.start(practice)
            DispatchQueue.main.asyncAfter(deadline: .now() + 600) { [weak self] in self?.coach.stop() }
        }
    }

    private func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
#endif
