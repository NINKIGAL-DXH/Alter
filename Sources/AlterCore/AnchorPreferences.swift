import Foundation

/// Keep user text in a stable preferences domain outside the app bundle.
/// Replacing Alter.app (including a version update) must not reset this key.
public struct AnchorPreferences {
    public static let domain = "io.github.ninkigal-dxh.Alter"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = UserDefaults(suiteName: AnchorPreferences.domain)!) {
        self.defaults = defaults
    }
    public func loadText() -> String { defaults.string(forKey: "anchorText") ?? "" }
    public func saveText(_ text: String) throws {
        _ = try AnchorText.pages(text)
        defaults.set(text, forKey: "anchorText")
    }
}
