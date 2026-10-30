#if os(macOS)
import AppKit
import MonorailCore

/// A connected display, with frames in Accessibility coordinates
/// (origin at the top-left of the primary display, y growing downward).
struct Display: Equatable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    let frame: CGRect
    /// The frame minus the menu bar and Dock.
    let visibleFrame: CGRect

    static func all() -> [Display] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        let primaryHeight = primary.frame.height
        func flip(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
        }
        return screens.compactMap { screen in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(number.uint32Value)
            return Display(
                id: id,
                uuid: uuidString(for: id),
                name: screen.localizedName,
                frame: flip(screen.frame),
                visibleFrame: flip(screen.visibleFrame)
            )
        }
    }

    static func uuidString(for id: CGDirectDisplayID) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
            let string = CFUUIDCreateString(nil, uuid) as String?
        else { return "display-\(id)" }
        return string
    }

    var viewport: Rect {
        Rect(x: visibleFrame.minX, y: visibleFrame.minY, width: visibleFrame.width, height: visibleFrame.height)
    }
}

/// Mission Control Spaces, through the private SkyLight API. Looked up at
/// runtime so that, if Apple ever removes a symbol, Monorail falls back to
/// treating every display as having a single Space instead of crashing.
enum Spaces {
    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias CurrentSpaceFn = @convention(c) (Int32, CFString) -> UInt64
    private typealias SpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        ?? dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    private static let mainConnection = symbol("CGSMainConnectionID", as: MainConnectionFn.self)
    private static let currentSpaceFn = symbol("CGSManagedDisplayGetCurrentSpace", as: CurrentSpaceFn.self)
    private static let spacesForWindowsFn = symbol("CGSCopySpacesForWindows", as: SpacesForWindowsFn.self)
    private static let connection: Int32 = mainConnection?() ?? 0

    /// The Space currently shown on the display, or 0 if unknown.
    static func current(displayUUID: String) -> UInt64 {
        guard let currentSpaceFn, connection != 0 else { return 0 }
        return currentSpaceFn(connection, displayUUID as CFString)
    }

    /// The Spaces a window is on. Empty if unknown.
    static func spaces(of window: CGWindowID) -> [UInt64] {
        guard let spacesForWindowsFn, connection != 0 else { return [] }
        let allSpacesMask: Int32 = 0x7
        let ids = [NSNumber(value: window)] as CFArray
        guard let array = spacesForWindowsFn(connection, allSpacesMask, ids)?.takeRetainedValue() else { return [] }
        return (array as? [NSNumber])?.map(\.uint64Value) ?? []
    }
}
#endif
