import Foundation

public struct ManagedApp: Identifiable, Sendable {
    public var id: String { path }
    public let path: String, name: String, bundleID: String, version: String
    public let feed: URL?, appStore: Bool
}
public enum AppInventory {
    public static func read(home: String) -> [ManagedApp] {
        var apps: [ManagedApp] = []
        for folder in ["/Applications", home + "/Applications"] {
            guard let paths = try? FileManager.default.contentsOfDirectory(at:URL(fileURLWithPath:folder),includingPropertiesForKeys:nil) else { continue }
            for url in paths.prefix(2000) where url.pathExtension == "app" {
                guard let info = try? readBoundedPlist(url.appendingPathComponent("Contents/Info.plist")), let id = info["CFBundleIdentifier"] as? String else { continue }
                let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
                apps.append(ManagedApp(path:url.path,name:url.deletingPathExtension().lastPathComponent,bundleID:id,version:info["CFBundleShortVersionString"] as? String ?? "未知",feed:feed?.scheme == "https" ? feed : nil,appStore:FileManager.default.fileExists(atPath:url.appendingPathComponent("Contents/_MASReceipt/receipt").path)))
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
    var versions: [(String,String)] = [], version = "", minimum = "", channel = "", inItem = false, field = ""
    func parser(_ parser:XMLParser,didStartElement elementName:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) {
        field = elementName
        if elementName == "item" { version=""; minimum=""; channel=""; inItem=true }
        if inItem, elementName == "enclosure" { version = attributes["sparkle:shortVersionString"] ?? "" }
    }
    func parser(_ parser:XMLParser,foundCharacters string:String) {
        guard inItem else { return }
        if field == "sparkle:shortVersionString" { version += string }
        if field == "sparkle:minimumSystemVersion" { minimum += string }
        if field == "sparkle:channel" { channel += string }
    }
    func parser(_ parser:XMLParser,didEndElement elementName:String,namespaceURI:String?,qualifiedName:String?) {
        if elementName == "item" { if !version.isEmpty && channel.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { versions.append((version.trimmingCharacters(in:.whitespacesAndNewlines),minimum.trimmingCharacters(in:.whitespacesAndNewlines))) }; inItem=false }
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
        let markup = String(decoding:data,as:UTF8.self)
        guard !markup.contains("<!DOCTYPE"), !markup.contains("<!ENTITY") else { throw AlterError.refused("更新订阅包含不支持的实体声明。") }
        let delegate = FeedParser(), parser = XMLParser(data:data); parser.shouldResolveExternalEntities=false; parser.delegate=delegate
        guard parser.parse() else { throw AlterError.refused("无法解析更新订阅。") }
        let os = ProcessInfo.processInfo.operatingSystemVersion, currentOS = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let versions = delegate.versions.filter { $0.1.isEmpty || currentOS.compare($0.1,options:.numeric) != .orderedAscending }.map(\.0)
        guard let latest = versions.sorted(by: { $0.compare($1,options:.numeric) == .orderedDescending }).first else { throw AlterError.refused("订阅未提供当前系统可用的稳定版本。") }
        let newer = latest.compare(app.version,options:.numeric) == .orderedDescending
        return AppUpdate(app:app,version:latest,detail:newer ? "订阅提供更新版本。交由应用自身更新器安装，以保留其签名、公证与迁移流程。" : "当前版本不低于订阅中可用的稳定版本。")
    }
}

func readBoundedPlist(_ url: URL) throws -> [String:Any] {
    let info = try FileSafety.metadata(url.path)
    guard FileSafety.regular(info), info.st_size <= 1_048_576 else { throw AlterError.refused("配置文件类型或大小超出预算。") }
    let input = try FileHandle(forReadingFrom:url); defer { try? input.close() }
    let data = try input.read(upToCount:1_048_577) ?? Data()
    guard data.count <= 1_048_576, let result = try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any] else { throw AlterError.refused("配置文件无法解析。") }; return result
}
