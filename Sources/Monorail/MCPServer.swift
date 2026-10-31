#if os(macOS)
import Foundation

/// `Monorail --mcp`: a Model Context Protocol server on stdin/stdout, so AI
/// assistants (Claude Desktop, Claude Code and others) can see and arrange
/// your windows. It talks to the running app through the local API.
///
/// Claude Desktop config:
///     "monorail": { "command": "/Applications/Monorail.app/Contents/MacOS/Monorail", "args": ["--mcp"] }
enum MCPServer {
    private struct Tool {
        var name: String
        var description: String
        var properties: [String: [String: Any]]
        var required: [String]
        /// HTTP method and path for the local API, from the arguments.
        var route: ([String: Any]) -> (String, String, [String: Any])
    }

    private static let tools: [Tool] = [
        Tool(name: "get_state", description: "The current workspace, profile, slide and focused window.",
             properties: [:], required: []) { _ in ("GET", "/state", [:]) },
        Tool(name: "list_windows", description: "Every window Monorail manages: id, app, title, workspace and slide.",
             properties: [:], required: []) { _ in ("GET", "/windows", [:]) },
        Tool(name: "list_workspaces", description: "Workspaces with their names and slides.",
             properties: [:], required: []) { _ in ("GET", "/workspaces", [:]) },
        Tool(name: "focus_window", description: "Go to a window (scrolls the strip to show it).",
             properties: ["id": ["type": "integer", "description": "Window id from list_windows"]], required: ["id"]) { args in
            ("POST", "/focus", args)
        },
        Tool(name: "move_window", description: "Move a window to a workspace (1-based).",
             properties: ["id": ["type": "integer"], "workspace": ["type": "integer"]], required: ["id", "workspace"]) { args in
            ("POST", "/move", args)
        },
        Tool(name: "pair_windows",
             description: "Put 2–6 windows together in one slide. layout: columns (side by side), stack, grid, mainLeft, mainTop, spiral or accordion.",
             properties: ["ids": ["type": "array", "items": ["type": "integer"]], "layout": ["type": "string"]],
             required: ["ids"]) { args in ("POST", "/pair", args) },
        Tool(name: "switch_workspace", description: "Show a workspace (1-based).",
             properties: ["number": ["type": "integer"]], required: ["number"]) { args in ("POST", "/workspace", args) },
        Tool(name: "perform_action",
             description: "Run any Monorail action by name, e.g. focus-left, move-right, cycle-width, overview, regroup, focus-mode, balance, undo.",
             properties: ["action": ["type": "string"]], required: ["action"]) { args in ("POST", "/action", args) },
        Tool(name: "apply_layout", description: "Apply a saved layout by name.",
             properties: ["name": ["type": "string"]], required: ["name"]) { args in ("POST", "/layout", args) },
        Tool(name: "open_app_pair", description: "Open a saved app pair by name.",
             properties: ["name": ["type": "string"]], required: ["name"]) { args in ("POST", "/pair-name", args) },
        Tool(name: "run_template", description: "Start a workspace template by name.",
             properties: ["name": ["type": "string"]], required: ["name"]) { args in ("POST", "/template", args) },
    ]

    static func run() -> Never {
        while let line = readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8),
                let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let method = message["method"] as? String
            else { continue }
            let id = message["id"]
            let params = message["params"] as? [String: Any] ?? [:]
            // Notifications (no id) need no answer.
            guard let id else { continue }
            switch method {
            case "initialize":
                reply(id, result: [
                    "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                    "capabilities": ["tools": [String: Any]()],
                    "serverInfo": ["name": "monorail", "title": "Monorail by Ashforde®", "version": version],
                    "instructions": "Monorail arranges Mac windows on a scrolling strip of slides. List windows first, then pair, move or focus them by id.",
                ])
            case "ping":
                reply(id, result: [:])
            case "tools/list":
                reply(id, result: ["tools": tools.map { tool in
                    [
                        "name": tool.name, "description": tool.description,
                        "inputSchema": ["type": "object", "properties": tool.properties, "required": tool.required],
                    ] as [String: Any]
                }])
            case "tools/call":
                let name = params["name"] as? String ?? ""
                let arguments = params["arguments"] as? [String: Any] ?? [:]
                guard let tool = tools.first(where: { $0.name == name }) else {
                    reply(id, error: (-32602, "Unknown tool \(name)"))
                    continue
                }
                let (httpMethod, path, body) = tool.route(arguments)
                switch call(httpMethod, path, body) {
                case .success(let text):
                    reply(id, result: ["content": [["type": "text", "text": text]], "isError": false])
                case .failure(let message):
                    reply(id, result: ["content": [["type": "text", "text": message]], "isError": true])
                }
            default:
                reply(id, error: (-32601, "Method not found: \(method)"))
            }
        }
        exit(0)
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private enum Outcome { case success(String), failure(String) }

    /// One request to the running app's local API.
    private static func call(_ method: String, _ path: String, _ body: [String: Any]) -> Outcome {
        guard let port = (try? String(contentsOf: LocalAPI.portURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines),
            let url = URL(string: "http://127.0.0.1:\(port)\(path)")
        else {
            return .failure("Monorail isn't running with its local API on. Open Monorail ▸ Settings ▸ Automation and turn on the local API.")
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = method
        request.setValue("Bearer \(LocalAPI.token())", forHTTPHeaderField: "Authorization")
        if method != "GET" {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let done = DispatchSemaphore(value: 0)
        var outcome = Outcome.failure("No answer from Monorail")
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { done.signal() }
            if let error {
                outcome = .failure("Couldn't reach Monorail: \(error.localizedDescription)")
                return
            }
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            outcome = ok ? .success(text) : .failure(text)
        }.resume()
        done.wait()
        return outcome
    }

    private static func reply(_ id: Any, result: [String: Any]) {
        send(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private static func reply(_ id: Any, error: (Int, String)) {
        send(["jsonrpc": "2.0", "id": id, "error": ["code": error.0, "message": error.1]])
    }

    private static func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object), var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        FileHandle.standardOutput.write(Data(line.utf8))
    }
}
#endif
