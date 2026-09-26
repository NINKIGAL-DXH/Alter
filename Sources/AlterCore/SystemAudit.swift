import Foundation
import Darwin
import Security

public struct AuditFinding: Identifiable, Sendable {
    public let id: String, title: String, detail: String
    public let verified: Bool
}
public enum SystemAudit {
    public static func protections(cancellation: CancellationFlag) -> [AuditFinding] {
        let checks = [("sip","系统完整性保护","/usr/bin/csrutil",["status"]),
                      ("gatekeeper","Gatekeeper","/usr/sbin/spctl",["--status"]),
                      ("filevault","FileVault 磁盘加密","/usr/bin/fdesetup",["status"]),
                      ("firewall","应用防火墙","/usr/libexec/ApplicationFirewall/socketfilterfw",["--getglobalstate"])]
        return checks.map { id,title,command,args in
            do { return AuditFinding(id:id,title:title,detail:try LocalProbe.run(command,args,cancellation:cancellation),verified:true) }
            catch { return AuditFinding(id:id,title:title,detail:"未能确认：" + error.localizedDescription,verified:false) }
        }
    }
    public static func signature(_ path: String) throws -> AuditFinding {
        guard path.lowercased().hasSuffix(".app"), FileSafety.validPath(path) else { throw AlterError.refused("请选择应用包。") }
        var code: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(URL(fileURLWithPath:path) as CFURL, [], &code)
        guard created == errSecSuccess, let code else { return AuditFinding(id:path,title:URL(fileURLWithPath:path).lastPathComponent,detail:"无法读取签名（OSStatus \(created)）；不代表已确认恶意软件。",verified:false) }
        let valid = SecStaticCodeCheckValidity(code,SecCSFlags(rawValue:kSecCSCheckAllArchitectures | kSecCSStrictValidate),nil)
        var info: CFDictionary?
        _ = SecCodeCopySigningInformation(code,SecCSFlags(rawValue:kSecCSSigningInformation),&info)
        let fields = info as? [String:Any] ?? [:]
        let team = fields[kSecCodeInfoTeamIdentifier as String] as? String ?? "无团队标识（可能为临时签名）"
        let identifier = fields[kSecCodeInfoIdentifier as String] as? String ?? "未知"
        return AuditFinding(id:path,title:URL(fileURLWithPath:path).lastPathComponent,detail:"\(valid == errSecSuccess ? "签名内容校验通过" : "签名校验未通过（OSStatus \(valid)）")\n团队：\(team)\n标识：\(identifier)\n签名有效性不等同于安全或公证结论。",verified:valid == errSecSuccess)
    }
}
/// Small fixed probes. Callers provide fixed executables/argument structures, never shell strings.
enum LocalProbe {
    static func run(_ executable: String, _ args: [String], cancellation: CancellationFlag, mutation: Bool = false) throws -> String {
        let job = URL(fileURLWithPath:"/private/tmp/alter-probe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at:job,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]); defer { MoleReader.clearJob(job) }
        let data = try BoundedProcess.run(executable:executable,arguments:args,environment:["HOME":FileManager.default.homeDirectoryForCurrentUser.path,"PATH":"/usr/bin:/bin:/usr/sbin:/sbin","LC_ALL":"C","TMPDIR":job.path],directory:job,cancellation:cancellation,seconds:30,mutation:mutation)
        return String(decoding:data,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
    }
}
public struct StartupItem: Identifiable, Sendable {
    public var id: String { path }
    public let path: String, label: String, program: String
    public let userAgent: Bool, disabled: Bool?
    public let identity: FileIdentity
}
public struct StartupPlan: Sendable {
    public let item: StartupItem, disable: Bool, created: Date
    public init(item: StartupItem, disable: Bool) { self.item=item; self.disable=disable; self.created=Date() }
}
public enum StartupManager {
    public static func scan(home: String, cancellation: CancellationFlag) throws -> [StartupItem] {
        let domain = "gui/\(getuid())"
        let disabled = try? LocalProbe.run("/bin/launchctl",["print-disabled",domain],cancellation:cancellation)
        var items: [StartupItem] = []
        for folder in [home + "/Library/LaunchAgents","/Library/LaunchAgents","/Library/LaunchDaemons"] {
            guard let walker = FileManager.default.enumerator(at:URL(fileURLWithPath:folder),includingPropertiesForKeys:nil,options:[.skipsSubdirectoryDescendants]) else { continue }
            for case let url as URL in walker where url.pathExtension == "plist" {
                guard !cancellation.isCancelled, items.count < 2000 else { throw AlterError.refused("启动项扫描已停止或达到预算。") }
                guard let s = try? FileSafety.metadata(url.path), FileSafety.regular(s), s.st_size <= 1_048_576,
                      let plist = try? readBoundedPlist(url),
                      let label = plist["Label"] as? String else { continue }
                let program = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first ?? "未提供可执行文件"
                let lines = disabled?.components(separatedBy:"\n") ?? []
                let line = lines.first { $0.contains("\"" + label + "\" =>") }
                let state: Bool? = disabled == nil ? nil : line?.contains("true") ?? false
                items.append(StartupItem(path:url.path,label:label,program:program,userAgent:folder == home + "/Library/LaunchAgents",disabled:state,identity:FileSafety.identity(s)))
            }
        }
        return items.sorted { $0.label < $1.label }
    }
    public static func apply(_ plan: StartupPlan, home: String, cancellation: CancellationFlag) throws {
        let item = plan.item
        guard geteuid() != 0, Date().timeIntervalSince(plan.created) >= 0, Date().timeIntervalSince(plan.created) < 300,
              item.userAgent, URL(fileURLWithPath:item.path).deletingLastPathComponent().path == home + "/Library/LaunchAgents",
              item.label.range(of:"^[A-Za-z0-9][A-Za-z0-9._-]{0,255}$",options:.regularExpression) != nil,
              !item.label.hasPrefix("com.apple."), !item.label.lowercased().contains("alter"), item.disabled != nil else { throw AlterError.refused("此启动项需在系统设置中管理，或预览已过期。") }
        try ProtectionStore(home:home).requireUnprotected(item.path)
        let fd = try FileSafety.openDirectory(URL(fileURLWithPath:item.path).deletingLastPathComponent().path); defer { close(fd) }
        let s = try FileSafety.metadata(item.path)
        guard FileSafety.identity(s) == item.identity else { throw AlterError.refused("启动项配置已变化，请重新预览。") }
        _ = try LocalProbe.run("/bin/launchctl",[plan.disable ? "disable" : "enable","gui/\(getuid())/" + item.label],cancellation:cancellation,mutation:true)
        let current = try scan(home:home,cancellation:cancellation)
        guard current.first(where: { $0.path == item.path })?.disabled == plan.disable else { throw AlterError.refused("请求已发出，但未能核实当前状态；请刷新或检查系统设置。") }
    }
}
