#if os(macOS)
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
#else
print("Monorail is a macOS app. Only MonorailCore builds on this platform.")
#endif
