import Foundation
import Darwin

public enum FileSafety {
    /// POSIX physical path for read-only scanning. Foundation may rewrite /private/tmp
    /// back to the /tmp alias, which is intentionally refused by write validation.
    public static func physicalReadPath(_ path: String) throws -> String {
        guard validPath(path), let resolved = realpath(path, nil) else { throw AlterError.refused("目录或文件不存在，或无法解析其真实路径。") }
        defer { free(resolved) }; return String(cString: resolved)
    }
    public static func metadata(_ path: String) throws -> stat {
        var info = stat()
        guard lstat(path, &info) == 0 else { throw AlterError.refused("文件已变化或不可访问。") }
        return info
    }
    public static func identity(_ s: stat) -> FileIdentity {
        FileIdentity(device: UInt64(s.st_dev), inode: UInt64(s.st_ino), size: s.st_size,
                     modified: Int64(s.st_mtimespec.tv_sec), changed: Int64(s.st_ctimespec.tv_sec),
                     modifiedNanos: Int64(s.st_mtimespec.tv_nsec), changedNanos: Int64(s.st_ctimespec.tv_nsec))
    }
    public static func regular(_ s: stat) -> Bool { s.st_mode & S_IFMT == S_IFREG }
    public static func directory(_ s: stat) -> Bool { s.st_mode & S_IFMT == S_IFDIR }
    public static func validPath(_ path: String) -> Bool {
        path.hasPrefix("/") && path.utf8.count <= 4096 && !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) &&
        !path.split(separator: "/", omittingEmptySubsequences: false).contains("..") && !path.contains("//")
    }
    // Open every ancestor via a pinned fd. No symlink, root-device or path-string fallback.
    public static func openDirectory(_ path: String) throws -> Int32 {
        guard validPath(path) else { throw AlterError.refused("路径格式不受支持。") }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw AlterError.refused("无法打开根目录。") }
        for part in path.split(separator: "/") {
            let next = openat(fd, String(part), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(fd)
            guard next >= 0 else { throw AlterError.refused("目录不可访问或包含符号链接：\(part)，errno=\(errno)。") }
            fd = next
        }
        return fd
    }
    public static func installerEligible(path: String, home: String, info: stat, now: Date = Date()) -> Bool {
        guard geteuid() != 0, validPath(path), path.hasPrefix(home + "/Downloads/") else { return false }
        let relative = String(path.dropFirst((home + "/Downloads/").count))
        guard relative.split(separator: "/").count <= 2, !relative.split(separator: "/").contains(where: { $0.hasPrefix(".") }),
              ["dmg", "pkg", "iso", "xip"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()),
              regular(info), info.st_uid == getuid(), info.st_nlink == 1,
              info.st_flags & UInt32(UF_IMMUTABLE | SF_IMMUTABLE | UF_APPEND | SF_APPEND | SF_RESTRICTED | UF_COMPRESSED) == 0,
              info.st_size > 0, info.st_size <= 25 * 1024 * 1024 * 1024 else { return false }
        // ctime catches recently replaced, renamed, linked, and chmod-ed files too.
        let newest = max(info.st_mtimespec.tv_sec, max(info.st_ctimespec.tv_sec, info.st_birthtimespec.tv_sec))
        return now.timeIntervalSince1970 - Double(newest) >= 30 * 86400
    }
}
