#if os(macOS)
/// How the app is named wherever people see it.
enum Brand {
    /// The app's own name (its bundle, menus like "Quit Monorail").
    static let name = "Monorail"
    /// The maker, with the registered mark.
    static let maker = "by Ashforde®"
    /// The full brand: "Monorail by Ashforde®".
    static let full = "\(name) \(maker)"
}
#endif
