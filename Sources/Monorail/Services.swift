#if os(macOS)
import AppKit
import EventKit
import JavaScriptCore
import MonorailCore
import Network

// MARK: - Meetings

/// A minute before a calendar event with a video link, opens the link (the
/// meeting app gets a slide of its own as it opens) and switches profile.
final class MeetingHelper {
    var isEnabled = false {
        didSet { if isEnabled && !oldValue { start() } else if !isEnabled { timer?.invalidate() } }
    }
    var onMeeting: (_ title: String, _ link: URL) -> Void = { _, _ in }

    private let store = EKEventStore()
    private var timer: Timer?
    private var handled: Set<String> = []

    private func start() {
        let begin = { [weak self] in
            DispatchQueue.main.async {
                self?.timer?.invalidate()
                self?.timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in self?.check() }
                self?.check()
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, _ in if granted { begin() } }
        } else {
            store.requestAccess(to: .event) { granted, _ in if granted { begin() } }
        }
    }

    private static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com",
                                       "whereby.com", "around.co", "facetime.apple.com"]

    private func check() {
        let now = Date()
        let soon = store.predicateForEvents(withStart: now.addingTimeInterval(-60), end: now.addingTimeInterval(90), calendars: nil)
        for event in store.events(matching: soon) where !event.isAllDay {
            let id = event.eventIdentifier ?? event.title ?? ""
            let startsIn = event.startDate.timeIntervalSince(now)
            guard !handled.contains(id), startsIn < 75, startsIn > -60, let link = Self.link(in: event) else { continue }
            handled.insert(id)
            onMeeting(event.title ?? "Meeting", link)
        }
    }

    /// The first video-call link in the event's URL, location or notes.
    private static func link(in event: EKEvent) -> URL? {
        let text = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }.joined(separator: " ")
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap(\.url).first { url in
            Self.meetingHosts.contains { url.host?.hasSuffix($0) == true }
        }
    }
}

// MARK: - Local API

/// A small HTTP API on 127.0.0.1, for scripts, launchers and the MCP server.
/// Every request needs the token stored in Application Support (readable by
/// you only), so other users and web pages can't drive your windows.
final class LocalAPI {
    typealias Handler = (_ method: String, _ path: [String], _ body: [String: Any]) -> Any?

    var handler: Handler = { _, _, _ in nil }
    private var listener: NWListener?
    private(set) var port: UInt16 = 0

    static var tokenURL: URL { SettingsStore.directory.appendingPathComponent("api-token") }
    static var portURL: URL { SettingsStore.directory.appendingPathComponent("api-port") }

    /// The token, created on first use.
    static func token() -> String {
        if let existing = try? String(contentsOf: tokenURL, encoding: .utf8), existing.count >= 32 {
            return existing.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let token = (0..<4).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "") }.joined()
        try? FileManager.default.createDirectory(at: SettingsStore.directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: tokenURL.path, contents: Data(token.utf8), attributes: [.posixPermissions: 0o600])
        return token
    }

    func start(port: Int) {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: nwPort)
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters) else {
            log.error("Local API couldn't listen on port \(port)")
            return
        }
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        listener.start(queue: .main)
        self.listener = listener
        self.port = nwPort.rawValue
        try? String(port).write(to: Self.portURL, atomically: true, encoding: .utf8)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        try? FileManager.default.removeItem(at: Self.portURL)
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, done, error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                self.respond(to: request, on: connection)
            } else if done || buffer.count > 1_000_000 {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private struct Request {
        var method: String
        var path: String
        var headers: [String: String]
        var body: Data
    }

    /// A complete request, or nil while more bytes are needed.
    private static func parse(_ data: Data) -> Request? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)),
            let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8)
        else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = data[headerEnd.upperBound...]
        guard body.count >= length else { return nil }
        return Request(method: String(start[0]), path: String(start[1]), headers: headers, body: Data(body.prefix(length)))
    }

    private func respond(to request: Request, on connection: NWConnection) {
        let token = Self.token()
        let given = request.headers["authorization"]?.replacingOccurrences(of: "Bearer ", with: "")
        var status = "200 OK"
        var result: Any
        if given != token {
            status = "401 Unauthorized"
            result = ["error": "Missing or wrong token. It's in ~/Library/Application Support/Monorail/api-token."]
        } else {
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
            let path = request.path.split(separator: "?").first.map(String.init) ?? ""
            let parts = path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
            if let answer = handler(request.method, parts, body) {
                result = answer
            } else {
                status = "404 Not Found"
                result = ["error": "Unknown endpoint \(request.method) \(path)"]
            }
        }
        let json = (try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        var response = Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(json.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(json)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}

// MARK: - Scripts

/// JavaScript plugins in ~/Library/Application Support/Monorail/Scripts.
///
///     monorail.on("windowOpened", w => { if (w.app == "zoom.us") monorail.perform("toggle-pause") })
///     monorail.on("workspaceChanged", ws => monorail.notify("Now in " + ws.name))
///
/// Events: windowOpened {id, app, title}, workspaceChanged {index, name, profile},
/// focusChanged {app, title}. Calls: perform(action), focus(id), moveToWorkspace(id, n),
/// park(n), openPair(name), applyLayout(name), notify(text), windows(), state().
final class ScriptHost {
    struct Bridge {
        var perform: (String) -> Void
        var focus: (WindowID) -> Void
        var moveToWorkspace: (WindowID, Int) -> Void
        var park: (Int) -> Void
        var openPair: (String) -> Void
        var applyLayout: (String) -> Void
        var notify: (String) -> Void
        var windows: () -> [[String: Any]]
        var state: () -> [String: Any]
    }

    var bridge: Bridge?
    private var context: JSContext?
    private var handlers: [String: [JSValue]] = [:]

    static var folder: URL { SettingsStore.directory.appendingPathComponent("Scripts", isDirectory: true) }

    /// Loads (or reloads) every .js file in the Scripts folder.
    func load() {
        handlers.removeAll()
        guard let bridge, let context = JSContext() else { return }
        self.context = context
        context.exceptionHandler = { _, exception in
            log.error("Script error: \(exception?.toString() ?? "unknown")")
        }
        let api = JSValue(newObjectIn: context)!
        let on: @convention(block) (String, JSValue) -> Void = { [weak self] event, function in
            self?.handlers[event, default: []].append(function)
        }
        let perform: @convention(block) (String) -> Void = { bridge.perform($0) }
        let focus: @convention(block) (Int) -> Void = { bridge.focus(WindowID(clamping: $0)) }
        let move: @convention(block) (Int, Int) -> Void = { bridge.moveToWorkspace(WindowID(clamping: $0), $1 - 1) }
        let park: @convention(block) (Int) -> Void = { bridge.park($0 - 1) }
        let pair: @convention(block) (String) -> Void = { bridge.openPair($0) }
        let layout: @convention(block) (String) -> Void = { bridge.applyLayout($0) }
        let notify: @convention(block) (String) -> Void = { bridge.notify($0) }
        let windows: @convention(block) () -> [[String: Any]] = { bridge.windows() }
        let state: @convention(block) () -> [String: Any] = { bridge.state() }
        let functions: [(String, Any)] = [
            ("on", on), ("perform", perform), ("focus", focus), ("moveToWorkspace", move), ("park", park),
            ("openPair", pair), ("applyLayout", layout), ("notify", notify), ("windows", windows), ("state", state),
        ]
        for (name, function) in functions { api.setObject(function, forKeyedSubscript: name as NSString) }
        context.setObject(api, forKeyedSubscript: "monorail" as NSString)
        let log: @convention(block) (String) -> Void = { message in NSLog("Monorail script: %@", message) }
        let console = JSValue(newObjectIn: context)!
        console.setObject(log, forKeyedSubscript: "log" as NSString)
        context.setObject(console, forKeyedSubscript: "console" as NSString)

        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        if files.isEmpty { writeExample() }
        for file in files.filter({ $0.pathExtension == "js" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            context.evaluateScript(source, withSourceURL: file)
        }
    }

    func unload() {
        handlers.removeAll()
        context = nil
    }

    func emit(_ event: String, _ payload: [String: Any]) {
        guard let functions = handlers[event] else { return }
        for function in functions { function.call(withArguments: [payload]) }
    }

    private func writeExample() {
        let example = """
        // Monorail script. Files in this folder run when Monorail starts
        // (Settings → Automation → Reload Scripts runs them again).
        //
        // monorail.on(event, handler): "windowOpened", "workspaceChanged", "focusChanged"
        // monorail.perform("focus-left"), focus(id), moveToWorkspace(id, 2), park(3),
        // openPair("Safari + Notes"), applyLayout("Coding"), notify("Hi"), windows(), state()

        monorail.on("windowOpened", function (w) {
          // Calls get their own workspace, say workspace 3:
          // if (w.app === "zoom.us") monorail.moveToWorkspace(w.id, 3)
        })
        """
        try? example.write(to: Self.folder.appendingPathComponent("example.js"), atomically: true, encoding: .utf8)
    }
}
#endif
