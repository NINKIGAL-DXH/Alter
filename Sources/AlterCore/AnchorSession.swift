import Foundation

/// An app-wide admission gate, shared by windows and all task entry points.
/// Enter only after existing work has finished; never suspend a filesystem write midway.
public struct AnchorSession: Sendable {
    public enum Phase: Sendable { case standard, preparing, active }
    public private(set) var phase: Phase = .standard
    public var freezesTools: Bool { phase != .standard }
    public init() {}
    public mutating func prepare(busy: Bool, externalUntil: Date?, now: Date = Date()) throws {
        guard phase == .standard, !busy else { throw AlterError.refused("请等待当前任务结束，再进入 Anchor。") }
        guard externalUntil.map({ $0 <= now }) ?? true else { throw AlterError.refused("管理员维护仍在授权或运行时段内，结束后才能进入 Anchor。") }
        phase = .preparing
    }
    public mutating func activate() { if phase == .preparing { phase = .active } }
    public mutating func leave() { phase = .standard }
}

public enum AnchorText {
    public static let maximumCharacters = 8000
    /// Paginate at grapheme boundaries. No HTML, URLs, markup or executable content.
    public static func pages(_ text: String) throws -> [String] {
        guard text.utf8.count <= 131_072, text.count <= maximumCharacters else {
            throw AlterError.refused("Anchor 文字最多 8,000 字，请缩短后再保存。")
        }
        let paragraphs = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        var pages: [String] = []
        for paragraph in paragraphs {
            var rest = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            while !rest.isEmpty {
                let end = rest.index(rest.startIndex, offsetBy: 72, limitedBy: rest.endIndex) ?? rest.endIndex
                pages.append(String(rest[..<end]))
                rest = String(rest[end...])
            }
        }
        return pages
    }
}
