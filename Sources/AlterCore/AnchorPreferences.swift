import Foundation

/// Keep user text in a stable preferences domain outside the app bundle.
/// Replacing Alter.app (including a version update) must not reset this key.
/// The app keeps the same CFBundleIdentifier. Do not open its own identifier
/// as a suite: Foundation may return nil for that suite inside the real app.
public struct AnchorPreferences {
    public static let domain = "io.github.ninkigal-dxh.Alter"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    public func loadText() -> String { defaults.string(forKey: "anchorText") ?? "" }
    public func saveText(_ text: String) throws {
        _ = try AnchorText.pages(text)
        defaults.set(text, forKey: "anchorText")
    }
}
