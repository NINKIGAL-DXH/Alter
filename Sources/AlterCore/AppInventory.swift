import Foundation

public struct ManagedApp: Identifiable, Sendable {
    public var id: String { path }
    public let path: String, name: String, bundleID: String, version: String
    public let feed: URL?, appStore: Bool
    public let buildVersion: String?
    public init(path: String, name: String, bundleID: String, version: String, feed: URL?, appStore: Bool, buildVersion: String? = nil) {
        self.path=path; self.name=name; self.bundleID=bundleID; self.version=version; self.feed=feed; self.appStore=appStore; self.buildVersion=buildVersion
    }
}
public enum AppInventory {
    public static func read(home: String) -> [ManagedApp] {
        var apps: [ManagedApp] = []
        for folder in ["/Applications", home + "/Applications"] {
            guard let paths = try? FileManager.default.contentsOfDirectory(at:URL(fileURLWithPath:folder),includingPropertiesForKeys:nil) else { continue }
            for url in paths.prefix(2000) where url.pathExtension == "app" {
                guard let info = try? readBoundedPlist(url.appendingPathComponent("Contents/Info.plist")), let id = info["CFBundleIdentifier"] as? String else { continue }
                let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
                apps.append(ManagedApp(path:url.path,name:url.deletingPathExtension().lastPathComponent,bundleID:id,version:info["CFBundleShortVersionString"] as? String ?? "未知",feed:feed?.scheme == "https" ? feed : nil,appStore:FileManager.default.fileExists(atPath:url.appendingPathComponent("Contents/_MASReceipt/receipt").path),buildVersion:info["CFBundleVersion"] as? String))
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public static func leftovers(home: String, apps: [ManagedApp]) throws -> [MoleCandidate] {
        let identifiers = Set(apps.map(\.bundleID))
        var result: [MoleCandidate] = []
        for folder in ["Library/Caches", "Library/Preferences", "Library/Saved Application State"] {
            let root = URL(fileURLWithPath:home).appendingPathComponent(folder)
            guard let walker = FileManager.default.enumerator(at:root,includingPropertiesForKeys:nil,options:[.skipsSubdirectoryDescendants]) else { continue }
            for case let url as URL in walker {
                var id = url.lastPathComponent
                for suffix in [".plist", ".savedState"] where id.hasSuffix(suffix) { id = String(id.dropLast(suffix.count)) }
                guard id.contains("."), !id.hasPrefix("com.apple."), !identifiers.contains(where: { id == $0 || id.hasPrefix($0 + ".") }),
                      let info = try? FileSafety.metadata(url.path), FileSafety.regular(info) || FileSafety.directory(info) else { continue }
                guard result.count < 5000 else { throw AlterError.refused("疑似残留超过 5,000 项，请缩小目录检查。") }
                result.append(MoleCandidate(category:"possible-leftover",path:url.path,bytes:max(0,info.st_blocks*512),note:"未在两个应用目录找到对应标识：" + id + "。可能仍属于其他位置的应用；请核实归属后选择。"))
            }
        }
        return result
    }
}
public struct AppUpdate: Sendable {
    public let app: ManagedApp, version: String, detail: String
}
private final class SecureFeedSession: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
}
private final class FeedParser: NSObject, XMLParserDelegate {
    struct Version { let short: String, build: String, minimum: String, maximum: String }
    var versions: [Version] = []
    var short="", build="", minimum="", maximum="", channel="", field="", inItem=false, macArchive=false, deltaDepth=0
    func parser(_ parser:XMLParser,didStartElement elementName:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) {
        field=elementName
        if elementName == "item" { short=""; build=""; minimum=""; maximum=""; channel=""; macArchive=false; deltaDepth=0; inItem=true }
        if elementName == "sparkle:deltas" { deltaDepth += 1 }
        if inItem, elementName == "enclosure", deltaDepth == 0, attributes["sparkle:deltaFrom"] == nil {
            let platform=attributes["sparkle:os"] ?? "macos"
            guard platform == "macos" || platform == "macosx" else { return }
            macArchive=true
            if let value=attributes["sparkle:shortVersionString"], !value.isEmpty { short=value }
            if let value=attributes["sparkle:version"], !value.isEmpty { build=value }
        }
    }
    func parser(_ parser:XMLParser,foundCharacters string:String) {
        guard inItem, deltaDepth == 0 else { return }
        switch field {
        case "sparkle:shortVersionString": short += string
        case "sparkle:version": build += string
        case "sparkle:minimumSystemVersion": minimum += string
        case "sparkle:maximumSystemVersion": maximum += string
        case "sparkle:channel": channel += string
        default: break
        }
        if [short,build,minimum,maximum,channel].contains(where: { $0.utf8.count > 256 }) { parser.abortParsing() }
    }
    func parser(_ parser:XMLParser,didEndElement elementName:String,namespaceURI:String?,qualifiedName:String?) {
        if elementName == "sparkle:deltas" { deltaDepth=max(0,deltaDepth-1) }
        if elementName == "item" {
            let clean: (String)->String = { $0.trimmingCharacters(in:.whitespacesAndNewlines) }
            if macArchive && clean(channel).isEmpty && (!clean(short).isEmpty || !clean(build).isEmpty) {
                versions.append(Version(short:clean(short),build:clean(build),minimum:clean(minimum),maximum:clean(maximum)))
            }
            if versions.count > 2000 { parser.abortParsing() }; inItem=false
        }
        field=""
    }
}
public enum AppUpdates {
    public static func check(_ app: ManagedApp) async throws -> AppUpdate {
        guard let feed = app.feed, feed.scheme == "https" else { return AppUpdate(app:app,version:app.version,detail:app.appStore ? "此应用由 App Store 管理，请在商店中检查更新。" : "应用未公开受支持的 HTTPS 更新订阅，请使用应用内更新器。") }
        let configuration = URLSessionConfiguration.ephemeral; configuration.timeoutIntervalForRequest=20; configuration.timeoutIntervalForResource=30; configuration.urlCredentialStorage=nil; configuration.httpCookieStorage=nil
        let session = URLSession(configuration:configuration,delegate:SecureFeedSession(),delegateQueue:nil); defer { session.invalidateAndCancel() }
        let (bytes,response) = try await session.bytes(from:feed)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, response.url?.scheme == "https", response.expectedContentLength <= 2_097_152 else { throw AlterError.refused("更新订阅不可用或超过 2 MB 预算。") }
        var data = Data()
        for try await byte in bytes { guard data.count < 2_097_152 else { throw AlterError.refused("更新订阅超过预算。") }; data.append(byte) }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return try parse(data,app:app,systemVersion:"\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
    }
    static func parse(_ data: Data, app: ManagedApp, systemVersion: String) throws -> AppUpdate {
        guard data.count <= 2_097_152 else { throw AlterError.refused("更新订阅超过预算。") }
        // Reject declarations before the XML parser, including UTF-16/32 encodings.
        let encodings: [String.Encoding] = [.utf16LittleEndian,.utf16BigEndian,.utf32LittleEndian,.utf32BigEndian]
        guard !([String(decoding:data,as:UTF8.self)] + encodings.compactMap({ String(data:data,encoding:$0) })).contains(where: { $0.contains("<!DOCTYPE") || $0.contains("<!ENTITY") }) else { throw AlterError.refused("更新订阅包含不支持的实体声明。") }
        let delegate=FeedParser(), parser=XMLParser(data:data); parser.shouldResolveExternalEntities=false; parser.delegate=delegate
        guard parser.parse() else { throw AlterError.refused("无法解析更新订阅。") }
        let versions=delegate.versions.filter {
            ($0.minimum.isEmpty || systemVersion.compare($0.minimum,options:.numeric) != .orderedAscending) &&
            ($0.maximum.isEmpty || systemVersion.compare($0.maximum,options:.numeric) != .orderedDescending)
        }
        let useBuild = app.buildVersion != nil && versions.contains { !$0.build.isEmpty }
        let comparable=versions.filter { useBuild ? !$0.build.isEmpty : !$0.short.isEmpty }
        guard let latest=comparable.sorted(by: {
            let a = useBuild ? $0.build : $0.short, b = useBuild ? $1.build : $1.short
            return a.compare(b,options:.numeric) == .orderedDescending
        }).first else { throw AlterError.refused("订阅未提供当前系统可比较的版本；请使用应用自身更新器。") }
        let available = useBuild ? latest.build : latest.short
        let installed = useBuild ? app.buildVersion! : app.version
        let newer=available.compare(installed,options:.numeric) == .orderedDescending
        return AppUpdate(app:app,version:latest.short.isEmpty ? "构建 " + available : latest.short + (useBuild ? "（构建 " + latest.build + "）" : ""),detail:newer ? "订阅提供更新版本。交由应用自身更新器安装，以保留其签名、公证与迁移流程。" : "当前版本不低于订阅中适用于本系统的版本。")
    }

}

func readBoundedPlist(_ url: URL) throws -> [String:Any] {
    let info = try FileSafety.metadata(url.path)
    guard FileSafety.regular(info), info.st_size <= 1_048_576 else { throw AlterError.refused("配置文件类型或大小超出预算。") }
    let input = try FileHandle(forReadingFrom:url); defer { try? input.close() }
    let data = try input.read(upToCount:1_048_577) ?? Data()
    guard data.count <= 1_048_576, let result = try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any] else { throw AlterError.refused("配置文件无法解析。") }; return result
}
