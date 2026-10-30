#if os(macOS)
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
#else
print("MacSlider is a macOS app. Only MacSliderCore builds on this platform.")
#endif
