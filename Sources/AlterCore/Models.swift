import Foundation

public enum EntryKind: String, Codable, Sendable { case installer, cache, largeFile, application }
public struct FileIdentity: Codable, Equatable, Sendable {
    public let device: UInt64, inode: UInt64, size: Int64, modified: Int64, changed: Int64
    public let modifiedNanos: Int64, changedNanos: Int64
}
public struct ScanEntry: Identifiable, Codable, Sendable {
    public var id: String { path }
    public let path: String, name: String, kind: EntryKind, bytes: Int64
    public let identity: FileIdentity
    public var canTrash: Bool
    public var note: String
    public init(path: String, kind: EntryKind, bytes: Int64, identity: FileIdentity, canTrash: Bool = false, note: String = "只读") {
        self.path = path; self.name = URL(fileURLWithPath: path).lastPathComponent
        self.kind = kind; self.bytes = bytes; self.identity = identity; self.canTrash = canTrash; self.note = note
    }
}
public struct ScanReport: Sendable {
    public var entries: [ScanEntry] = []
    public var visited = 0
    public var bytes: Int64 = 0
    public var incomplete = false
    public var messages: [String] = []
    public var elapsed: TimeInterval = 0
    public init() {}
}
public struct ScanLimits: Sendable {
    public var maxEntries: Int, maxResults: Int, maxDepth: Int, seconds: TimeInterval
    public init(maxEntries: Int = 100_000, maxResults: Int = 300, maxDepth: Int = 16, seconds: TimeInterval = 20) {
        self.maxEntries = max(1, min(maxEntries, 200_000)); self.maxResults = max(1, min(maxResults, 500))
        self.maxDepth = max(1, min(maxDepth, 24)); self.seconds = max(0.01, min(seconds, 60))
    }
}
public final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    public init() {}
    public func cancel() { lock.lock(); value = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
public enum AlterError: LocalizedError {
    case refused(String)
    public var errorDescription: String? { switch self { case .refused(let reason): return reason } }
}
public func byteText(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}
