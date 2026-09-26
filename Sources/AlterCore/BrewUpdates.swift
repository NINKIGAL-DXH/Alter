import Foundation
import Darwin

public struct BrewUpdate: Identifiable, Sendable {
    public var id: String { token }
    public let token: String, installed: String, available: String
}
public struct BrewUpdatePlan: Sendable {
    public let update: BrewUpdate, appPaths: [String], created: Date
    public let receiptHash: String
}
public enum BrewUpdates {
    static var executable: String? { ["/opt/homebrew/bin/brew","/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath:$0) } }
    private static func run(_ args: [String], mutation: Bool = false, cancellation: CancellationFlag) throws -> Data {
        guard geteuid() != 0, let executable else { throw AlterError.refused("未找到 Homebrew。可使用应用自身更新器或 App Store。") }
        let job = URL(fileURLWithPath:"/private/tmp/alter-brew-" + UUID().uuidString)
        try FileManager.default.createDirectory(at:job,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]); defer { MoleReader.clearJob(job) }
        let env = ["HOME":FileManager.default.homeDirectoryForCurrentUser.path,"PATH":"/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin","TMPDIR":job.path,"LC_ALL":"C","HOMEBREW_NO_AUTO_UPDATE":"1","HOMEBREW_NO_ANALYTICS":"1","HOMEBREW_NO_INSTALL_CLEANUP":"1","HOMEBREW_NO_ENV_HINTS":"1","NONINTERACTIVE":"1"]
        return try BoundedProcess.run(executable:executable,arguments:args,environment:env,directory:job,cancellation:cancellation,seconds:mutation ? 900 : 120,mutation:mutation)
    }
    private static func valid(_ token: String) -> Bool { token.range(of:"^[a-z0-9][a-z0-9+@._-]{0,127}$",options:.regularExpression) != nil }
    public static func check(cancellation: CancellationFlag) throws -> [BrewUpdate] {
        let data = try run(["outdated","--cask","--greedy","--json=v2"],cancellation:cancellation)
        guard let json = try JSONSerialization.jsonObject(with:data) as? [String:Any], let rows = json["casks"] as? [[String:Any]], rows.count <= 2000 else { throw AlterError.refused("Homebrew 返回格式无法验证。") }
        return rows.compactMap { row in
            guard let token = row["name"] as? String, valid(token), let versions = row["installed_versions"] as? [String], let available = row["current_version"] as? String else { return nil }
            return BrewUpdate(token:token,installed:versions.joined(separator:", "),available:available)
        }
    }
    /// The GUI's automated path is restricted to official tap app-bundle casks.
    /// Script/pkg installers still use their owner-provided installer UI.
    public static func preview(_ update: BrewUpdate, cancellation: CancellationFlag) throws -> BrewUpdatePlan {
        guard valid(update.token) else { throw AlterError.refused("无效 Homebrew 标识。") }
        let data = try run(["info","--cask","--json=v2",update.token],cancellation:cancellation)
        return try parsePreview(update, data:data)
    }
    static func parsePreview(_ update: BrewUpdate, data: Data) throws -> BrewUpdatePlan {
        guard valid(update.token) else { throw AlterError.refused("无效 Homebrew 标识。") }
        guard let json = try JSONSerialization.jsonObject(with:data) as? [String:Any], let casks = json["casks"] as? [[String:Any]], casks.count == 1,
              let cask = casks.first, cask["token"] as? String == update.token, cask["tap"] as? String == "homebrew/cask",
              cask["version"] as? String == update.available, cask["installed"] as? String == update.installed,
              cask["container"] == nil || cask["container"] is NSNull,
              let artifacts = cask["artifacts"] as? [[String:Any]] else { throw AlterError.refused("cask 来源或版本变化，请重新检查。") }
        if let deps = cask["depends_on"] as? [String:Any], deps.keys.contains(where: { $0 != "macos" && $0 != "arch" }) { throw AlterError.refused("此 cask 会联动安装依赖，请使用所属更新器。") }
        var paths: [String] = []
        for artifact in artifacts {
            guard artifact.keys.allSatisfy({ ["app","zap"].contains($0) }) else { throw AlterError.refused("此 cask 包含脚本、系统安装器或其他安装动作。请在应用自身更新器中检查，Alter 不会静默运行安装钩子。") }
            if let app = artifact["app"] as? [Any], let name = app.first as? String, app.count == 1, name.hasSuffix(".app"), !name.contains("/") { paths.append("/Applications/" + name) }
            else if artifact["app"] != nil { throw AlterError.refused("此 cask 使用自定义目标，需要应用自身更新器。") }
        }
        guard !paths.isEmpty else { throw AlterError.refused("未识别到应用包。") }
        // Canonical sorted JSON avoids false invalidation from key order differences.
        let receipt = try JSONSerialization.data(withJSONObject:cask,options:[.sortedKeys])
        return BrewUpdatePlan(update:update,appPaths:paths,created:Date(),receiptHash:receipt.base64EncodedString())
    }
    public static func execute(_ plan: BrewUpdatePlan, cancellation: CancellationFlag) throws -> String {
        guard Date().timeIntervalSince(plan.created) >= 0, Date().timeIntervalSince(plan.created) < 300 else { throw AlterError.refused("更新预览已过期。") }
        let fresh = try preview(plan.update,cancellation:cancellation)
        guard fresh.receiptHash == plan.receiptHash else { throw AlterError.refused("Homebrew 安装信息变化，请重新确认。") }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for path in plan.appPaths { try ProtectionStore(home:home).requireUnprotected(path) }
        let result = try run(["upgrade","--cask",plan.update.token],mutation:true,cancellation:cancellation)
        let verification = try run(["info","--cask","--json=v2",plan.update.token],cancellation:cancellation)
        guard let json = try JSONSerialization.jsonObject(with:verification) as? [String:Any], let rows = json["casks"] as? [[String:Any]],
              rows.count == 1, rows[0]["token"] as? String == plan.update.token, rows[0]["installed"] as? String == plan.update.available else { throw AlterError.refused("更新进程已返回，但安装版本未核实为目标版本。请检查 Homebrew 状态。") }
        // An exit status alone does not establish which version is now installed.
        let remaining = try check(cancellation:cancellation)
        guard !remaining.contains(where: { $0.token == plan.update.token }) else { throw AlterError.refused("Homebrew 已返回，但仍报告此应用有更新。请查看实际安装版本。") }
        return String(decoding:result,as:UTF8.self)
    }
}
