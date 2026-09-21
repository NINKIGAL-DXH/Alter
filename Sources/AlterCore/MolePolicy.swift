import Foundation
import Darwin
import CryptoKit

/// The bundled Mole core runs inside a write-denying, network-denying OS sandbox.
/// Only protection predicates are called. Never executes clean/uninstall/optimize.
public struct MolePolicy: Sendable {
    public let root: URL
    public let home: String
    public init(root: URL, home: String = FileManager.default.homeDirectoryForCurrentUser.path) { self.root = root; self.home = home }
    public func review(_ paths: [String], cancellation: CancellationFlag) throws -> [Bool] {
        guard geteuid() != 0, !paths.isEmpty, paths.count <= 64, paths.allSatisfy(FileSafety.validPath) else { throw AlterError.refused("Mole 输入超出安全范围。") }
        let data = try Data(contentsOf: root.appendingPathComponent("UPSTREAM.json"))
        struct Manifest: Decodable { let sha256: [String: String] }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        let files = ["lib/core/base.sh", "lib/core/app_protection.sh", "lib/core/app_protection_data.sh", "lib/core/timeout.sh", "lib/core/timeouts.sh"]
        for name in files {
            let hash = SHA256.hash(data: try Data(contentsOf: root.appendingPathComponent(name))).map { String(format: "%02x", $0) }.joined()
            guard hash == manifest.sha256[name] else { throw AlterError.refused("Mole 内核校验失败，已停止。") }
        }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-f", root.appendingPathComponent("policy.sb").path, "/bin/bash", "--noprofile", "--norc", root.appendingPathComponent("alter-policy.sh").path, root.path] + paths
        process.environment = ["HOME": home, "PATH": "/usr/bin:/bin", "LC_ALL": "C", "NO_COLOR": "1", "MOLE_TEST_NO_AUTH": "1", "MOLE_DRY_RUN": "1"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let started = ProcessInfo.processInfo.systemUptime
        while process.isRunning {
            var taskInfo = proc_taskinfo()
            let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let measured = proc_pidinfo(process.processIdentifier, PROC_PIDTASKINFO, 0, &taskInfo, infoSize) == infoSize
            if cancellation.isCancelled || (measured && taskInfo.pti_resident_size > 128 * 1024 * 1024) || ProcessInfo.processInfo.systemUptime - started > 10 {
                // This is a dedicated fixed-program worker, never a user app.
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                throw AlterError.refused("Mole 保护检查已取消或超时；项目保持不变。")
            }
            usleep(20_000)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw AlterError.refused("Mole 保护检查未完成；项目保持只读。") }
        // Output is a fixed one-word response for at most 64 arguments (< 1 KB).
        let output = try pipe.fileHandleForReading.read(upToCount: 4096) ?? Data()
        let lines = String(decoding: output, as: UTF8.self).split(separator: "\n").map(String.init)
        guard lines.count == paths.count, lines.allSatisfy({ $0 == "review" || $0 == "protected" }) else { throw AlterError.refused("Mole 返回值无法验证；项目保持只读。") }
        return lines.map { $0 == "review" }
    }
}
