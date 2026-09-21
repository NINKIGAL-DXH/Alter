import Foundation
import Darwin

public struct HistoryStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    private func validateDirectory() throws {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let fd = try FileSafety.openDirectory(directory.path); defer { close(fd) }
        var s = stat()
        guard fstat(fd, &s) == 0, s.st_uid == getuid() else { throw AlterError.refused("操作记录目录无法验证。") }
    }
    public func load() throws -> [TrashRecord] {
        try validateDirectory()
        let url = directory.appendingPathComponent("history.json")
        if !FileManager.default.fileExists(atPath: url.path) { return [] }
        let s = try FileSafety.metadata(url.path)
        guard FileSafety.regular(s), s.st_uid == getuid(), s.st_size <= 262_144 else { throw AlterError.refused("操作记录超出大小限制或文件类型不符。") }
        return Array(try JSONDecoder().decode([TrashRecord].self, from: Data(contentsOf: url)).prefix(200))
    }
    public func save(_ records: [TrashRecord]) throws {
        try validateDirectory()
        let data = try JSONEncoder().encode(Array(records.prefix(200)))
        guard data.count <= 262_144 else { throw AlterError.refused("操作记录已满，请保留当前记录后再继续。") }
        let file = directory.appendingPathComponent("history.json")
        if FileManager.default.fileExists(atPath: file.path) {
            let s = try FileSafety.metadata(file.path)
            guard FileSafety.regular(s), s.st_uid == getuid(), s.st_nlink == 1 else { throw AlterError.refused("操作记录路径不安全。") }
        }
        try data.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
