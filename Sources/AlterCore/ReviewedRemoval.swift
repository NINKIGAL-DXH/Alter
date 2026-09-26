import Foundation
import Darwin
import CryptoKit

public struct ReviewedItem: Identifiable, Sendable {
    public var id: String { path }
    public let path: String, category: String, note: String
    public let bytes: Int64, count: Int
    public let identity: FileIdentity
    public let fingerprint: String
    public let directory: Bool
}
public struct ReviewedPlan: Sendable {
    public let items: [ReviewedItem]
    public let created: Date
    public init(items: [ReviewedItem]) throws {
        guard !items.isEmpty, items.count <= 64, Set(items.map(\.path)).count == items.count else { throw AlterError.refused("每批请选择 1–64 个项目。") }
        for item in items {
            guard !items.contains(where: { $0.path != item.path && item.path.hasPrefix($0.path + "/") }) else { throw AlterError.refused("选择包含父子目录，请只保留其中一层，避免重复处理。") }
        }
        self.items = items; self.created = Date()
    }
}

/// Snapshots metadata only, using descriptors and no symlink traversal. Directory
/// snapshots are bounded; changed children invalidate the confirmation.
public enum ReviewedRemoval {
    static func allowedScope(_ path: String, home: String) -> Bool {
        guard FileSafety.validPath(path), path != home, path != "/", !["/Applications", "/Library", "/System", "/Users", "/Volumes", "/private"].contains(path) else { return false }
        let protected = [home + "/.Trash", home + "/Library", home + "/Library/Application Support", home + "/Library/Preferences", home + "/Library/Caches", home + "/Library/Containers", home + "/.config", home + "/.ssh", home + "/.gnupg", home + "/.codex", home + "/Library/Application Support/Alter"]
        guard !protected.contains(path), ![home + "/.Trash", home + "/.ssh", home + "/.gnupg", home + "/.codex", home + "/Library/Application Support/Alter"].contains(where: { path.hasPrefix($0 + "/") }) else { return false }
        // Arbitrary system paths stay browseable, but are never recursive move roots.
        return path.hasPrefix(home + "/") || (path.hasPrefix("/Applications/") && URL(fileURLWithPath: path).deletingLastPathComponent().path == "/Applications" && path.lowercased().hasSuffix(".app")) || path.hasPrefix("/Volumes/")
    }
    public static func snapshot(_ candidate: MoleCandidate, home: String, cancellation: CancellationFlag) throws -> ReviewedItem {
        try ProtectionStore(home: home).requireUnprotected(candidate.path)
        guard allowedScope(candidate.path, home: home) else { throw AlterError.refused("此位置保持只读：" + candidate.path) }
        let url = URL(fileURLWithPath: candidate.path)
        let parent = try FileSafety.openDirectory(url.deletingLastPathComponent().path); defer { close(parent) }
        var info = stat()
        guard fstatat(parent, url.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0,
              FileSafety.regular(info) || FileSafety.directory(info),
              !FileSafety.regular(info) || info.st_nlink == 1,
              info.st_flags & UInt32(UF_IMMUTABLE | SF_IMMUTABLE | UF_APPEND | SF_APPEND | SF_RESTRICTED) == 0 else { throw AlterError.refused("项目已变化、是链接或受系统保护：" + candidate.path) }
        var count = 0, bytes: Int64 = 0
        var accumulator = [UInt8](repeating: 0, count: 32)
        let start = ProcessInfo.processInfo.systemUptime
        func add(_ relative: String, _ s: stat) {
            let record = "\(relative)\0\(s.st_dev):\(s.st_ino):\(s.st_size):\(s.st_mode):\(s.st_mtimespec.tv_sec):\(s.st_mtimespec.tv_nsec):\(s.st_ctimespec.tv_sec):\(s.st_ctimespec.tv_nsec)"
            for (i, value) in SHA256.hash(data: Data(record.utf8)).enumerated() { accumulator[i] ^= value }
            count += 1
            if FileSafety.regular(s) { let next = bytes.addingReportingOverflow(s.st_size); bytes = next.overflow ? Int64.max : next.partialValue }
        }
        func walk(_ fd: Int32, _ relative: String, _ depth: Int) throws {
            guard depth < 128, let stream = fdopendir(dup(fd)) else { throw AlterError.refused("目录层级过深或无法检查。") }
            defer { closedir(stream) }
            while true {
                errno = 0
                guard let raw = readdir(stream) else { if errno != 0 { throw AlterError.refused("目录检查不完整。") }; break }
                let name = withUnsafePointer(to: &raw.pointee.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: Int(raw.pointee.d_namlen) + 1) { String(cString: $0) } }
                if name == "." || name == ".." { continue }
                guard !cancellation.isCancelled, count < 400_000, ProcessInfo.processInfo.systemUptime - start < 120 else { throw AlterError.refused("预览检查已取消或达到预算；可减少选择后重试。") }
                var child = stat()
                guard fstatat(fd, name, &child, AT_SYMLINK_NOFOLLOW) == 0, child.st_dev == info.st_dev else { throw AlterError.refused("目录中存在不可访问项目或其他挂载卷。") }
                let relativeChild = relative + "/" + name
                add(relativeChild, child)
                if FileSafety.directory(child) {
                    let next = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                    guard next >= 0 else { throw AlterError.refused("子目录已变化。") }
                    defer { close(next) }
                    try walk(next, relativeChild, depth + 1)
                }
            }
        }
        add("", info)
        if FileSafety.directory(info) {
            let fd = openat(parent, url.lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw AlterError.refused("目录已变化。") }; defer { close(fd) }
            try walk(fd, "", 0)
        }
        return ReviewedItem(path: candidate.path, category: candidate.category, note: candidate.note, bytes: bytes, count: count, identity: FileSafety.identity(info), fingerprint: accumulator.map { String(format: "%02x", $0) }.joined(), directory: FileSafety.directory(info))
    }
    public static func move(_ item: ReviewedItem, home: String, created: Date, cancellation: CancellationFlag) throws -> TrashRecord {
        guard geteuid() != 0, Date().timeIntervalSince(created) >= 0, Date().timeIntervalSince(created) < 300 else { throw AlterError.refused("确认已过期，请重新预览。") }
        let current = try snapshot(MoleCandidate(category: item.category, path: item.path, bytes: item.bytes, note: item.note), home: home, cancellation: cancellation)
        guard current.identity == item.identity, current.fingerprint == item.fingerprint, current.count == item.count, !cancellation.isCancelled else { throw AlterError.refused("项目内容已变化，已停止：" + item.path) }
        let url = URL(fileURLWithPath: item.path)
        let parent = try FileSafety.openDirectory(url.deletingLastPathComponent().path); defer { close(parent) }
        let trash = try FileSafety.openDirectory(home + "/.Trash"); defer { close(trash) }
        var t = stat(), p = stat(), s = stat()
        guard fstat(trash, &t) == 0, t.st_uid == getuid(), t.st_mode & 0o077 == 0,
              fstat(parent, &p) == 0, p.st_mode & 0o002 == 0,
              fstatat(parent, url.lastPathComponent, &s, AT_SYMLINK_NOFOLLOW) == 0, FileSafety.identity(s) == item.identity else { throw AlterError.refused("目录权限或文件身份发生变化。") }
        let id = UUID(), name = "Alter-" + UUID().uuidString + "-" + String(url.lastPathComponent.prefix(100))
        guard renameatx_np(parent, url.lastPathComponent, trash, name, UInt32(RENAME_EXCL)) == 0 else { throw AlterError.refused("移动失败（权限不足或跨卷），已保留原文件：" + item.path) }
        var moved = stat()
        guard fstatat(trash, name, &moved, AT_SYMLINK_NOFOLLOW) == 0 else { throw AlterError.refused("已移动但结果无法核实，请查看废纸篓。") }
        return TrashRecord(id: id, date: Date(), originalPath: item.path, trashName: name, bytes: item.bytes, identity: FileSafety.identity(moved), reviewed: true)
    }
}
