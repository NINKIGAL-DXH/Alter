import Foundation
import Darwin

public struct DiskEntry: Codable, Sendable, Identifiable, Equatable {
    public var id: String { path }
    public let name: String, path: String
    public let size: Int64
    public let isDir: Bool
    enum CodingKeys: String, CodingKey { case name, path, size; case isDir = "is_dir" }
    public init(name: String, path: String, size: Int64, isDir: Bool) {
        self.name = name; self.path = path; self.size = max(0, size); self.isDir = isDir
    }
}
public struct DiskSnapshot: Decodable, Sendable {
    public let path: String
    public let entries: [DiskEntry]
    public let totalSize: Int64, totalFiles: Int64
    public let childCount: Int
    enum CodingKeys: String, CodingKey { case path, entries; case totalSize = "total_size", totalFiles = "total_files", childCount = "child_count" }
    public init(path: String, entries: [DiskEntry], totalSize: Int64, totalFiles: Int64, childCount: Int? = nil) {
        self.path = path; self.entries = entries; self.totalSize = totalSize; self.totalFiles = totalFiles; self.childCount = childCount ?? entries.count
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        entries = try c.decodeIfPresent([DiskEntry].self, forKey: .entries) ?? []
        totalSize = try c.decode(Int64.self, forKey: .totalSize)
        totalFiles = try c.decodeIfPresent(Int64.self, forKey: .totalFiles) ?? 0
        childCount = try c.decodeIfPresent(Int.self, forKey:.childCount) ?? entries.count
        guard totalSize >= 0, totalFiles >= 0, entries.count <= 50_000,
              entries.allSatisfy({ $0.size >= 0 && $0.path.hasPrefix("/") }),
              Set(entries.map(\.path)).count == entries.count else {
            throw AlterError.refused("目录结果超出显示预算或格式无效，请选择更小的子目录。")
        }
    }
}

/// Fixed, sandboxed read workers. No shell interpolation, no inherited authentication,
/// no writes outside a fresh private job folder, no user file content copied into RAM.
public struct MoleReader: Sendable {
    public let resources: URL
    public init(resources: URL) { self.resources = resources }
    public func analyze(_ path: String, cancellation: CancellationFlag) throws -> DiskSnapshot {
        // Resolve aliases only for read-only browsing. This never weakens write validation.
        guard FileSafety.validPath(path) else { throw AlterError.refused("请输入有效的绝对目录路径。") }
        let canonical = try FileSafety.physicalReadPath(path)
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical, isDirectory: &directory), directory.boolValue else {
            throw AlterError.refused("目录不存在或无法访问。请重新选择目录。")
        }
        let result = try run(command: "analyze", arguments: ["--json", canonical], cancellation: cancellation)
        let snapshot = try JSONDecoder().decode(DiskSnapshot.self, from: result)
        guard snapshot.path == canonical else { throw AlterError.refused("Mole 返回的目录与选择不一致。") }
        return snapshot
    }
    public func index(_ path: String, cancellation: CancellationFlag) throws -> DiskIndex {
        guard FileSafety.validPath(path) else { throw AlterError.refused("请输入有效目录路径。") }
        let canonical = try FileSafety.physicalReadPath(path)
        var result: DiskIndex?
        _ = try run(command: "analyze", arguments: ["--json", canonical], cancellation: cancellation, indexed: true) { job in
            result = try DiskIndex(root: canonical, stream: job.appendingPathComponent("index.ndjson"), cancellation: cancellation)
        }
        guard let result else { throw AlterError.refused("未生成空间索引。") }; return result
    }
    public func status(cancellation: CancellationFlag) throws -> Data {
        try run(command: "status", arguments: ["--json"], cancellation: cancellation, seconds: 60)
    }
    private func run(command: String, arguments: [String], cancellation: CancellationFlag, seconds: Double = 900, indexed: Bool = false, consume: ((URL) throws -> Void)? = nil) throws -> Data {
        guard geteuid() != 0, ["analyze", "status"].contains(command) else { throw AlterError.refused("读取内核不允许提权运行。") }
        let executable = resources.appendingPathComponent("Kernel/" + command)
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw AlterError.refused("未找到 Mole 分析内核，请使用完整构建的 Alter.app。") }
        let job = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("alter-read-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        // Remove only this invocation's private scratch files, never a caller's path.
        defer { Self.clearJob(job) }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var env = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": home, "TMPDIR": job.path,
                   "ALTER_MOLE_CACHE_DIR": job.appendingPathComponent("cache").path, "GOMAXPROCS": "2", "GOMEMLIMIT": "256MiB", "NO_COLOR": "1", "LC_ALL": "C"]
        if indexed { env["ALTER_MOLE_INDEX"] = "1" }
        if command == "status" {
            let snapshots = job.appendingPathComponent("processes")
            try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let queries = [("processes", ["-Aceo", "pid=,ppid=,state=,pcpu=,pmem=,rss=,comm=", "-r"]), ("fallback", ["aux"]), ("cpu", ["-Aceo", "pcpu"])]
            for (name, arguments) in queries {
                let probe = job.appendingPathComponent("probe-" + name)
                try FileManager.default.createDirectory(at: probe, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                let table = try BoundedProcess.run(executable: "/bin/ps", arguments: arguments, environment: env, directory: probe, cancellation: cancellation, seconds: 10)
                try table.write(to: snapshots.appendingPathComponent(name), options: .withoutOverwriting)
            }
            env["ALTER_MOLE_PROCESS_DIR"] = snapshots.path
        }
        let result = try BoundedProcess.run(executable: "/usr/bin/sandbox-exec", arguments: ["-D", "JOB=" + job.path, "-f", resources.appendingPathComponent("read-worker.sb").path, "/bin/bash", "--noprofile", "--norc", resources.appendingPathComponent("read-worker.sh").path, executable.path] + arguments,
                                      environment: env, directory: job, cancellation: cancellation, seconds: seconds)
        try consume?(job)
        return result
    }
    static func clearJob(_ job: URL) {
        // Walk only our freshly created directory without following symlinks.
        guard let enumerator = FileManager.default.enumerator(at: job, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) else { return }
        var directories: [String] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { enumerator.skipDescendants(); unlink(url.path) }
            else if values?.isDirectory == true { directories.append(url.path) }
            else { unlink(url.path) }
        }
        for path in directories.reversed() { rmdir(path) }
        rmdir(job.path)
    }
}

enum BoundedProcess {
    static func run(executable: String, arguments: [String], environment: [String: String], directory: URL,
                    cancellation: CancellationFlag, seconds: Double, maxOutput: Int64 = 8 * 1024 * 1024, mutation: Bool = false) throws -> Data {
        if cancellation.isCancelled { throw AlterError.refused("读取已取消。") }
        let out = directory.appendingPathComponent("stdout"), err = directory.appendingPathComponent("stderr")
        var actions: posix_spawn_file_actions_t?, attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0, posix_spawnattr_init(&attributes) == 0 else { throw AlterError.refused("无法准备受限进程。") }
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        let changeDirectory: Int32
        if #available(macOS 26, *) { changeDirectory = posix_spawn_file_actions_addchdir(&actions, directory.path) }
        else { changeDirectory = posix_spawn_file_actions_addchdir_np(&actions, directory.path) }
        guard changeDirectory == 0,
              posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
              posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, out.path, O_WRONLY | O_CREAT | O_EXCL, 0o600) == 0,
              posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, err.path, O_WRONLY | O_CREAT | O_EXCL, 0o600) == 0,
              posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0 else { throw AlterError.refused("无法隔离读取进程。") }
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup($0.key + "=" + $0.value) } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var pid: pid_t = 0
        let code = argv.withUnsafeBufferPointer { a in envp.withUnsafeBufferPointer { e in posix_spawn(&pid, executable, &actions, &attributes, a.baseAddress!, e.baseAddress!) } }
        guard code == 0 else { throw AlterError.refused("无法启动 Mole 读取内核（\(code)）。") }
        let start = ProcessInfo.processInfo.systemUptime
        var status: Int32 = 0
        var failure: String?
        var lastResourceSample = 0.0
        while true {
            let waited = waitpid(pid, &status, WNOHANG)
            if waited == pid { break }
            if waited == -1 {
                if errno == EINTR { continue }
                failure = "无法确认 Mole 进程状态，操作已停止。"; break
            }
            var outputInfo = stat(), errorInfo = stat()
            _ = lstat(out.path, &outputInfo); _ = lstat(err.path, &errorInfo)
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastResourceSample > 0.5 {
                lastResourceSample = now
                var pids = [pid_t](repeating: 0, count: 65)
                let capacity = pids.count * MemoryLayout<pid_t>.size
                let used = pids.withUnsafeMutableBytes { proc_listpgrppids(pid, $0.baseAddress, Int32(capacity)) }
                if used >= capacity { failure = "Mole 子进程数量达到预算，已停止。" }
                else if used > 0 {
                    var resident: UInt64 = 0
                    for child in pids.prefix(Int(used) / MemoryLayout<pid_t>.size) where child > 0 {
                        var info = proc_taskinfo()
                        let size = Int32(MemoryLayout<proc_taskinfo>.size)
                        if proc_pidinfo(child, PROC_PIDTASKINFO, 0, &info, size) == size { resident += info.pti_resident_size }
                    }
                    if resident > 512 * 1024 * 1024 { failure = "Mole 工作进程组达到 512 MB 预算，已停止；维护可能已有部分更改。" }
                }
            }
            if cancellation.isCancelled { failure = mutation ? "维护已停止，可能已有部分更改；请检查系统状态。" : "读取已取消；没有修改所分析的文件。" }
            else if outputInfo.st_size > maxOutput || errorInfo.st_size > maxOutput { failure = "结果超过 8 MB 预算，请分析更小的子目录。" }
            else if ProcessInfo.processInfo.systemUptime - start > seconds { failure = mutation ? "维护超时，已停止；可能已有部分更改，请检查系统状态。" : "读取超时，已停止；可改为分析其中的子目录。" }
            if failure != nil { kill(-pid, SIGKILL); while waitpid(pid, &status, 0) == -1 && errno == EINTR {}; break }
            usleep(40_000)
        }
        // Descendants belong to this dedicated process group, never user applications.
        kill(-pid, SIGKILL)
        if let failure { throw AlterError.refused(failure) }
        guard status == 0 else {
            let handle = try? FileHandle(forReadingFrom: err)
            let data = (try? handle?.read(upToCount: 4096)) ?? Data(); try? handle?.close()
            var detail = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if mutation, let output = try? FileHandle(forReadingFrom: out) {
                let text = (try? output.read(upToCount: 16_384)) ?? Data(); try? output.close()
                detail += "\n" + String(decoding: text, as: UTF8.self)
            }
            throw AlterError.refused((mutation ? "维护未完成，可能已有部分更改。\n" : "Mole 读取未完成。请查看具体原因；若 macOS 拒绝访问，可在隐私设置中授予目录权限。\n") + detail)
        }
        let handle = try FileHandle(forReadingFrom: out); defer { try? handle.close() }
        let data = try handle.read(upToCount: Int(maxOutput) + 1) ?? Data()
        guard data.count <= maxOutput else { throw AlterError.refused("读取结果超过内存预算。") }
        return data
    }
}
