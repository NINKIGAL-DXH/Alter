import Foundation
import Darwin

public struct TrashRecord: Codable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let originalPath: String
    public let trashName: String
    public let bytes: Int64
    public let identity: FileIdentity
    public var restored: Bool = false
}
public struct RemovalPlan: Sendable {
    public let created: Date
    public let entries: [ScanEntry]
    public init(entries: [ScanEntry], now: Date = Date()) throws {
        guard !entries.isEmpty, entries.count <= 20, entries.allSatisfy({ $0.canTrash && $0.kind == .installer }), Set(entries.map(\.path)).count == entries.count else { throw AlterError.refused("每次请选择 1–20 个已复核的安装包。") }
        guard entries.reduce(Int64(0), { $0 + $1.bytes }) <= 25 * 1024 * 1024 * 1024 else { throw AlterError.refused("单次整理上限为 25 GB，请减少选择。") }
        self.created = now; self.entries = entries
    }
}
public struct TrashService: Sendable {
    public let home: String
    public init(home: String = FileManager.default.homeDirectoryForCurrentUser.path) { self.home = home }
    private func checkedTrash() throws -> Int32 {
        let fd = try FileSafety.openDirectory(home + "/.Trash")
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { close(fd); throw AlterError.refused("废纸篓的所有权或权限不符合要求。") }
        return fd
    }
    public func move(_ entry: ScanEntry, planCreated: Date, now: Date = Date()) throws -> TrashRecord {
        guard geteuid() != 0, entry.canTrash, entry.kind == .installer, now.timeIntervalSince(planCreated) >= 0, now.timeIntervalSince(planCreated) <= 300 else { throw AlterError.refused("确认已过期或项目不可整理，请重新扫描。") }
        let url = URL(fileURLWithPath: entry.path)
        let parent = try FileSafety.openDirectory(url.deletingLastPathComponent().path)
        defer { close(parent) }
        var info = stat()
        guard fstatat(parent, url.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0,
              FileSafety.identity(info) == entry.identity,
              FileSafety.installerEligible(path: entry.path, home: home, info: info, now: now) else { throw AlterError.refused("文件或路径已变化，已跳过 \(entry.name)。") }
        var parentInfo = stat()
        guard fstat(parent, &parentInfo) == 0, parentInfo.st_uid == getuid(), parentInfo.st_mode & 0o022 == 0 else { throw AlterError.refused("来源目录允许其他用户写入，已拒绝整理。") }
        let destination = try checkedTrash()
        defer { close(destination) }
        let id = UUID()
        let trashName = "Alter-" + id.uuidString + "." + url.pathExtension
        // Atomic, descriptor-relative, no overwriting and no copy/delete fallback.
        // EXDEV fails closed: we never copy file contents or recursively delete.
        guard renameatx_np(parent, url.lastPathComponent, destination, trashName, UInt32(RENAME_EXCL)) == 0 else { throw AlterError.refused("无法安全移入废纸篓；文件保持原位。") }
        var moved = stat()
        guard fstatat(destination, trashName, &moved, AT_SYMLINK_NOFOLLOW) == 0 else { throw AlterError.refused("已移动，但无法核实结果；请检查废纸篓。") }
        return TrashRecord(id: id, date: now, originalPath: entry.path, trashName: trashName, bytes: entry.bytes, identity: FileSafety.identity(moved))
    }
    public func restore(_ record: TrashRecord) throws {
        guard geteuid() != 0, !record.restored, record.trashName.hasPrefix("Alter-"), !record.trashName.contains("/"), record.originalPath.hasPrefix(home + "/Downloads/"), FileSafety.validPath(record.originalPath) else { throw AlterError.refused("恢复记录无效。") }
        let trash = try checkedTrash(); defer { close(trash) }
        var info = stat()
        guard fstatat(trash, record.trashName, &info, AT_SYMLINK_NOFOLLOW) == 0, FileSafety.regular(info), info.st_uid == getuid(), info.st_nlink == 1, FileSafety.identity(info) == record.identity else { throw AlterError.refused("废纸篓项目已变化或已移除，无法自动恢复。") }
        let original = URL(fileURLWithPath: record.originalPath)
        let parent = try FileSafety.openDirectory(original.deletingLastPathComponent().path); defer { close(parent) }
        var parentInfo = stat()
        guard fstat(parent, &parentInfo) == 0, parentInfo.st_uid == getuid(), parentInfo.st_mode & 0o022 == 0 else { throw AlterError.refused("恢复目录权限已变化。") }
        guard renameatx_np(trash, record.trashName, parent, original.lastPathComponent, UInt32(RENAME_EXCL)) == 0 else { throw AlterError.refused("原位置已有同名文件、目录不可用或跨卷；不会覆盖。") }
    }
}
