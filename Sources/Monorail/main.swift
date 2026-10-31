#if os(macOS)
import AppKit

// `Monorail --mcp` runs the MCP server for AI assistants instead of the app.
if CommandLine.arguments.contains("--mcp") { MCPServer.run() }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
#else
print("Monorail is a macOS app. Only MonorailCore builds on this platform.")
#endif
