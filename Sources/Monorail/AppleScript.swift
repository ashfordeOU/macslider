#if os(macOS)
import AppKit

/// AppleScript: tell application "Monorail" to perform "focus-left"
@objc(MonorailPerformCommand)
final class MonorailPerformCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let name = directParameter as? String, let delegate = NSApp.delegate as? AppDelegate else { return false }
        return delegate.scriptPerform(name)
    }
}

/// apply layout / open pair / start template / restore snapshot "Name"
@objc(MonorailOpenCommand)
final class MonorailOpenCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let name = directParameter as? String, let delegate = NSApp.delegate as? AppDelegate else { return false }
        let kinds = ["Layo": "layout", "Pair": "pair", "Tmpl": "template", "Snap": "snapshot"]
        return delegate.scriptOpen(kinds[fourCharacters(commandDescription.appleEventCode)] ?? "", name)
    }
}

/// current state / window list: JSON text.
@objc(MonorailQueryCommand)
final class MonorailQueryCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let delegate = NSApp.delegate as? AppDelegate else { return "" }
        return fourCharacters(commandDescription.appleEventCode) == "Wins" ? delegate.scriptWindows() : delegate.scriptState()
    }
}

/// "Layo" from its four-character code.
private func fourCharacters(_ code: FourCharCode) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
    return String(bytes: bytes, encoding: .macOSRoman) ?? ""
}
#endif
