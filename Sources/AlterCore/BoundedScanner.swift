import Foundation
import Darwin

/// Physical, streaming traversal: one worker, one dirent at a time, depth <= 24.
/// No file contents, recursive arrays, Spotlight, downloads or directory symlink following.
public struct BoundedScanner: Sendable {
    public let home: String
    public let limits: ScanLimits
    public init(home: String = FileManager.default.homeDirectoryForCurrentUser.path, limits: ScanLimits = ScanLimits()) {
        self.home = home; self.limits = limits
    }
    public func scan(root: String, mode: EntryKind, cancellation: CancellationFlag, now: Date = Date()) -> ScanReport {
        var report = ScanReport()
        let start = ProcessInfo.processInfo.systemUptime
        let rootFD: Int32
        do { rootFD = try FileSafety.openDirectory(root) }
        catch { report.incomplete = true; report.messages = [error.localizedDescription]; return report }
        var rootInfo = stat()
        guard fstat(rootFD, &rootInfo) == 0 else { close(rootFD); report.incomplete = true; return report }
        var resultLimitReached = false
        func add(_ entry: ScanEntry) {
            if report.entries.count < limits.maxResults { report.entries.append(entry) }
            else {
                resultLimitReached = true
                if let smallest = report.entries.indices.min(by: { report.entries[$0].bytes < report.entries[$1].bytes }), entry.bytes > report.entries[smallest].bytes { report.entries[smallest] = entry }
            }
        }
        func stopped() -> Bool {
            cancellation.isCancelled || report.visited >= limits.maxEntries || ProcessInfo.processInfo.systemUptime - start >= limits.seconds
        }
        func walk(_ fd: Int32, _ path: String, _ depth: Int) -> Int64 {
            guard let dir = fdopendir(fd) else { close(fd); report.incomplete = true; return 0 }
            defer { closedir(dir) }
            var bytes: Int64 = 0
            while !stopped() {
                errno = 0
                guard let raw = readdir(dir) else { if errno != 0 { report.incomplete = true }; break }
                let name = withUnsafePointer(to: &raw.pointee.d_name) { ptr in
                    ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                report.visited += 1
                let pathToItem = path + "/" + name
                if !FileSafety.validPath(pathToItem) || name.hasPrefix(".") { continue }
                var info = stat()
                guard fstatat(dirfd(dir), name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { report.incomplete = true; continue }
                guard info.st_dev == rootInfo.st_dev else { continue }
                if FileSafety.directory(info) {
                    // Bundles, cloud libraries and other volumes are not traversed by broad disk scans.
                    let suffix = URL(fileURLWithPath: name).pathExtension.lowercased()
                    if mode != .application && ["app", "photoslibrary", "photolibrary", "bundle", "framework", "sparsebundle"].contains(suffix) { continue }
                    if depth >= limits.maxDepth { report.incomplete = true; continue }
                    let child = openat(dirfd(dir), name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                    guard child >= 0 else { report.incomplete = true; continue }
                    let size = walk(child, pathToItem, depth + 1)
                    bytes += size
                    if (mode == .cache && depth == 0) || (mode == .application && suffix == "app") {
                        add(ScanEntry(path: pathToItem, kind: mode, bytes: size, identity: FileSafety.identity(info), note: "只读统计；不自动移除"))
                    }
                } else if FileSafety.regular(info) {
                    // Allocated size does not force cloud-file downloads. Hardlinks are excluded from estimates.
                    let size = info.st_nlink > 1 ? 0 : max(0, Int64(info.st_blocks) * 512)
                    bytes += size
                    if mode == .installer && FileSafety.installerEligible(path: pathToItem, home: home, info: info, now: now) {
                        add(ScanEntry(path: pathToItem, kind: .installer, bytes: size, identity: FileSafety.identity(info), note: "等待 Mole 保护规则复核"))
                    } else if mode == .largeFile && size >= 100 * 1024 * 1024 {
                        add(ScanEntry(path: pathToItem, kind: mode, bytes: size, identity: FileSafety.identity(info), note: "个人文件，只读查看"))
                    }
                }
            }
            if stopped() { report.incomplete = true }
            return bytes
        }
        report.bytes = walk(rootFD, root, 0)
        report.entries.sort { $0.bytes > $1.bytes }
        report.elapsed = ProcessInfo.processInfo.systemUptime - start
        if cancellation.isCancelled { report.messages.append("扫描已取消；当前结果不完整。") }
        else if report.incomplete { report.messages.append("已达到扫描预算，或部分路径无法读取；这里只显示部分结果。") }
        if resultLimitReached { report.messages.append("仅显示体积最大的 \(limits.maxResults) 项。") }
        return report
    }
}
