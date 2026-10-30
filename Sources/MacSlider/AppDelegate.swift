#if os(macOS)
import AppKit
import MacSliderCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = SettingsStore()
    private lazy var engine = Engine(settings: store.settings)
    private let input = InputMonitor()
    private let trackpad = TrackpadSwipe.shared
    private let switcher = SwitcherController()
    private lazy var overview = OverviewController(engine: engine)
    private let updater = Updater()
    private let practice = PracticeTracker()
    private let sliderBar = SliderBarController()
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

        Accessibility.setGlobalTimeout(0.5)
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
        sliderBar.hideAll(animated: false)
        input.stop()
        trackpad.stop()
        engine.shutdown()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch url.host?.lowercased() {
            case "settings": showSettings()
            case "welcome": showWelcome()
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
            self?.updateStatusItem()
            self?.sliderBar.update()
        }
        sliderBar.mapsProvider = { [weak self] in self?.engine.miniMaps() ?? [] }
        sliderBar.actions = SliderBarController.Actions(
            slide: { [weak self] x, uuid in self?.engine.slide(to: x, displayUUID: uuid) },
            endSlide: { [weak self] in self?.engine.endSlide() },
            focus: { [weak self] id in self?.engine.focusAndReveal(id) },
            switchWorkspace: { [weak self] index in self?.engine.switchWorkspace(to: index) },
            showOverview: { [weak self] in self?.overview.show() }
        )
        engine.onShowSwitcher = { [weak self] in self?.switcher.toggle() }
        engine.onShowOverview = { [weak self] in self?.overview.toggle() }

        input.isPaused = { [weak self] in self?.engine.isPaused ?? false }
        input.onAction = { [weak self] action in
            self?.practice.record(action)
            self?.engine.perform(action)
        }
        input.onScroll = { [weak self] delta in self?.engine.swipe(by: delta) }
        input.onScrollEnd = { [weak self] in self?.engine.endSwipe() }
        input.onStep = { [weak self] forward in self?.engine.step(forward: forward) }
        input.isOverMenuBar = { point in Self.isOverMenuBar(point) }
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
    }

    /// Polls until the user grants Accessibility, then starts.
    private func waitForPermission() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard Accessibility.isTrusted(prompt: false) else { return }
            self?.startEngine()
        }
    }

    private func apply(_ settings: AppSettings) {
        engine.settings = settings
        input.keymap = settings.keymap
        input.modifierSwipe = settings.modifierSwipe
        input.scrollModifier = settings.scrollModifier
        input.scrollOverMenuBar = settings.scrollOverMenuBar
        input.slideTrigger = settings.slideTrigger
        updateArrowItems(visible: settings.showNavigationArrows)
        updater.setAutomatic(settings.checkForUpdates)
        sliderBar.mode = settings.sliderBar
        sliderBar.edge = settings.sliderBarEdge
        sliderBar.update()

        trackpad.fingers = settings.swipeFingers.rawValue
        if settings.swipeFingers == .off { trackpad.stop() } else if engine.isRunning { trackpad.start() }

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

    @objc private func stepLeft() { engine.step(forward: false, honourReverse: false) }
    @objc private func stepRight() { engine.step(forward: true, honourReverse: false) }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let symbol = engine.isPaused ? "pause.rectangle" : "rectangle.split.3x1"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MacSlider")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        if store.settings.showColumnIndicator, !engine.isPaused, let status = engine.status() {
            let position = "\(status.focusedColumn)/\(status.columnCount)"
            button.title = store.settings.workspaceCount > 1 ? " \(status.workspace) · \(position)" : " \(position)"
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
            item(engine.isPaused ? "Resume Tiling" : "Pause Tiling", #selector(togglePause), action: .togglePause))
        menu.addItem(item("Overview", #selector(showOverview), action: .overview))
        menu.addItem(item("Search Windows…", #selector(showSwitcher), action: .windowSwitcher))
        menu.addItem(item("Group Windows by App", #selector(regroup), action: .regroup))
        menu.addItem(item("Retile Windows", #selector(retile), action: .retile))

        if store.settings.workspaceCount > 1 {
            let workspaces = NSMenu()
            let current = engine.status()?.workspace
            for n in 1...store.settings.workspaceCount {
                let action = Action.allCases.first { $0.workspaceNumber == n }!
                let entry = item("Workspace \(n)", #selector(switchWorkspaceFromMenu(_:)), action: action)
                entry.tag = n
                entry.state = current == n ? .on : .off
                workspaces.addItem(entry)
            }
            let parent = NSMenuItem(title: "Workspaces", action: nil, keyEquivalent: "")
            parent.submenu = workspaces
            menu.addItem(parent)
        }

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettingsFromMenu), key: ","))
        menu.addItem(shortcutsMenu())
        menu.addItem(item("Welcome Tour…", #selector(showWelcomeFromMenu)))
        menu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        menu.addItem(item("About MacSlider", #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(item("Quit MacSlider", #selector(quit), key: "q"))
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
        menu.addItem(item("Change Shortcuts…", #selector(showShortcuts)))
        let parent = NSMenuItem(title: "Keyboard Shortcuts", action: nil, keyEquivalent: "")
        parent.submenu = menu
        return parent
    }

    @objc private func performFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = Action(rawValue: raw) else { return }
        // Let the menu close and focus return to the previous app first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.engine.perform(action) }
    }

    @objc private func switchWorkspaceFromMenu(_ sender: NSMenuItem) {
        engine.switchWorkspace(to: sender.tag - 1)
    }

    @objc private func showOverview() { overview.show() }
    @objc private func regroup() { engine.perform(.regroup) }
    @objc private func checkForUpdates() { updater.check(userInitiated: true) }

    private func headerTitle(trusted: Bool) -> String {
        if !trusted { return "MacSlider needs Accessibility access" }
        if engine.isPaused { return "MacSlider is paused" }
        if let status = engine.status() {
            let workspace = store.settings.workspaceCount > 1 ? "Workspace \(status.workspace) · " : ""
            if status.columnCount == 0 { return "\(workspace)No windows yet" }
            return "\(workspace)Slide \(status.focusedColumn) of \(status.columnCount)"
        }
        return "MacSlider is running"
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

    @objc private func togglePause() { engine.togglePause() }
    @objc private func retile() { engine.retile() }
    @objc private func showSwitcher() { switcher.show() }
    @objc private func showSettingsFromMenu() { showSettings() }
    @objc private func showWelcomeFromMenu() { showWelcome() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func focusWindowFromMenu(_ sender: NSMenuItem) {
        engine.focusAndReveal(WindowID(sender.tag))
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
                isPaused: { [weak self] in self?.engine.isPaused ?? false },
                setPaused: { [weak self] in self?.engine.setPaused($0) }
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "MacSlider Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        present(settingsWindow!)
    }

    private func showWelcome() {
        if welcomeWindow == nil {
            let view = WelcomeView(store: store, practice: practice) { [weak self] in
                guard let self else { return }
                self.store.settings.hasCompletedOnboarding = true
                self.welcomeWindow?.close()
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Welcome to MacSlider"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            welcomeWindow = window
        }
        present(welcomeWindow!)
    }

    private func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
#endif
