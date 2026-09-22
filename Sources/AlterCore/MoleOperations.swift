import Foundation
import Darwin
import CryptoKit

public enum MoleFeature: String, CaseIterable, Sendable { case clean, installer, purge, uninstall }
public struct MoleCandidate: Identifiable, Sendable {
    public var id: String { path }
    public let category: String, path: String, bytes: Int64, note: String
    public init(category: String, path: String, bytes: Int64, note: String) { self.category = category; self.path = path; self.bytes = bytes; self.note = note }
}
public struct MoleDiscovery: Sendable { public let candidates: [MoleCandidate]; public let notices: [String] }
public struct OptimizeTask: Identifiable, Sendable {
    public let id: String, title: String, detail: String
}
public struct OptimizePreview: Sendable { public let task: OptimizeTask; public let outcome: String, output: String; public let created: Date }

public struct MoleOperations: Sendable {
    public let resources: URL, home: String
    public init(resources: URL, home: String = FileManager.default.homeDirectoryForCurrentUser.path) { self.resources = resources; self.home = home }
    public func discover(_ feature: MoleFeature, path: String? = nil, cancellation: CancellationFlag) throws -> MoleDiscovery {
        if let path, !FileSafety.validPath(path) { throw AlterError.refused("请输入有效的绝对路径。") }
        let rows = try invoke(feature.rawValue, arguments: path.map { [$0] } ?? [], cancellation: cancellation, seconds: 900)
        var candidates: [MoleCandidate] = [], notices: [String] = [], seen: Set<String> = []
        for row in rows {
            if row[0] == "notice" { notices.append(row[3].replacingOccurrences(of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)); continue }
            guard FileSafety.validPath(row[1]), !seen.contains(row[1]), candidates.count < 5000,
                  let bytes = Int64(row[2]), bytes >= 0 else { continue }
            seen.insert(row[1]); candidates.append(MoleCandidate(category: row[0], path: row[1], bytes: bytes, note: row[3]))
        }
        if rows.filter({ $0[0] != "notice" }).count > 5000 { notices.append("候选项目超过 5,000 项显示预算；这是部分结果，请改用较小的目录。") }
        return MoleDiscovery(candidates: candidates, notices: notices)
    }
    public func review(_ paths: [String], cancellation: CancellationFlag) throws -> [Bool] {
        guard paths.count <= 64, paths.allSatisfy(FileSafety.validPath) else { throw AlterError.refused("复核路径无效。") }
        let rows = try invoke("policy", arguments: paths, cancellation: cancellation, seconds: 60)
        guard rows.count == paths.count, zip(rows, paths).allSatisfy({ $0.0[1] == $0.1 && ["protected", "review"].contains($0.0[0]) }) else { throw AlterError.refused("Mole 路径复核未完成。") }
        return rows.map { $0[0] == "review" && ReviewedRemoval.allowedScope($0[1], home: home) }
    }
    public func optimizeTasks(cancellation: CancellationFlag) throws -> [OptimizeTask] {
        try invoke("optimize-list", arguments: [], cancellation: cancellation, seconds: 30).map { OptimizeTask(id: $0[0], title: $0[1], detail: $0[3]) }
    }
    public func preview(_ task: OptimizeTask, cancellation: CancellationFlag) throws -> OptimizePreview {
        let rows = try invoke("optimize-preview", arguments: [task.id], cancellation: cancellation, seconds: 180)
        guard rows.count == 1, rows[0][1] == task.id else { throw AlterError.refused("维护预览未完成。") }
        return OptimizePreview(task: task, outcome: rows[0][0], output: rows[0][3], created: Date())
    }
    public func verify() throws {
        let root = resources.appendingPathComponent("MoleFull")
        struct Manifest: Decodable { let commit: String; let sha256: [String: String] }
        let m = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: root.appendingPathComponent("UPSTREAM.json")))
        guard m.commit == "69ab325d4f05af0ea21aeeeae544046c9f04a76b" else { throw AlterError.refused("Mole 版本校验失败。") }
        for (name, expected) in m.sha256 where name.hasSuffix(".sh") {
            let data = try Data(contentsOf: root.appendingPathComponent(name))
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == expected else { throw AlterError.refused("Mole 源码校验失败：" + name) }
        }
    }
    public func execute(_ preview: OptimizePreview, cancellation: CancellationFlag) throws -> String {
        guard Date().timeIntervalSince(preview.created) >= 0, Date().timeIntervalSince(preview.created) < 300 else { throw AlterError.refused("维护预览已过期，请重新检查。") }
        return try executeTask(preview.task.id, authority: "user", expires: Int(preview.created.timeIntervalSince1970) + 300, cancellation: cancellation)
    }
    public func executeTask(_ id: String, authority: String, expires: Int, cancellation: CancellationFlag) throws -> String {
        try verify()
        guard geteuid() != 0, ["user", "admin"].contains(authority), id.range(of: "^[a-z0-9_]+$", options: .regularExpression) != nil,
              expires > Int(Date().timeIntervalSince1970), expires <= Int(Date().timeIntervalSince1970) + 300 else { throw AlterError.refused("维护授权无效或过期。") }
        let job = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("alter-maintain-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { MoleReader.clearJob(job) }
        let env = ["HOME": home, "USER": NSUserName(), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TMPDIR": job.path, "LC_ALL": "C"]
        let data = try BoundedProcess.run(executable: "/bin/bash", arguments: ["--noprofile", "--norc", resources.appendingPathComponent("mole-optimize-run.sh").path, resources.appendingPathComponent("MoleFull").path, id, job.path, authority, String(expires)], environment: env, directory: job, cancellation: cancellation, seconds: 600, mutation: true)
        let result = String(decoding: data, as: UTF8.self)
        guard result.contains("ALTER_OUTCOME=") else { throw AlterError.refused("维护结果不完整，可能已有部分更改；请检查系统状态。") }
        return result
    }
    private func invoke(_ action: String, arguments: [String], cancellation: CancellationFlag, seconds: Double) throws -> [[String]] {
        guard geteuid() != 0, arguments.allSatisfy({ !$0.contains("\0") }) else { throw AlterError.refused("不允许以管理员身份启动 Alter。") }
        try verify()
        let job = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("alter-plan-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { MoleReader.clearJob(job) }
        let environment = ["HOME": home, "USER": NSUserName(), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TMPDIR": job.path, "LC_ALL": "C", "MOLE_DRY_RUN": "1", "MOLE_TEST_NO_AUTH": "1", "MO_NO_OPLOG": "1"]
        // macOS refuses the set-id /bin/ps executable inside Seatbelt. Capture a
        // fresh read-only table outside it; the unchanged Mole guard still decides
        // whether an owner is live, unknown, or idle. Never print this private table.
        if ["clean", "policy", "uninstall", "optimize-preview"].contains(action) {
            let probe = job.appendingPathComponent("process-probe")
            try FileManager.default.createDirectory(at: probe, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let table = try BoundedProcess.run(executable: "/bin/ps", arguments: ["-axo", "pid,ppid,comm,args"], environment: environment, directory: probe, cancellation: cancellation, seconds: 10)
            guard !table.isEmpty else { throw AlterError.refused("无法确认运行中的应用，已停止生成清理计划。") }
            try table.write(to: job.appendingPathComponent("process-table"), options: .withoutOverwriting)
        }
        let data = try BoundedProcess.run(executable: "/usr/bin/sandbox-exec", arguments: ["-D", "JOB=" + job.path, "-f", resources.appendingPathComponent("mole-preview.sb").path, "/bin/bash", "--noprofile", "--norc", resources.appendingPathComponent("mole-adapter.sh").path, resources.appendingPathComponent("MoleFull").path, action, job.path] + arguments, environment: environment, directory: job, cancellation: cancellation, seconds: seconds)
        let fields = data.split(separator: 0, omittingEmptySubsequences: false)
        guard fields.last?.isEmpty == true, (fields.count - 1) % 4 == 0, fields.count <= 40001 else { throw AlterError.refused("Mole 预览返回不完整或超过预算。") }
        return stride(from: 0, to: fields.count - 1, by: 4).map { index in (0..<4).map { String(decoding: fields[index + $0], as: UTF8.self) } }
    }
}
