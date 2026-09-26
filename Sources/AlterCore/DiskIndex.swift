import Foundation
import SQLite3

public struct IndexedFile: Identifiable, Sendable {
    public var id: String { path }
    public let path: String, name: String, identity: String
    public let size: Int64, logical: Int64, modified: Int64
    public var entry: DiskEntry { DiskEntry(name: name, path: path, size: size, isDir: false) }
}
/// One bounded on-disk index per scan. Navigation never traverses the filesystem.
/// This is a display snapshot, never an authorization to delete a file.
public final class DiskIndex: @unchecked Sendable {
    public let root: String, created = Date()
    private let folder: URL
    private var db: OpaquePointer?
    private var incompleteNodes = 0
    private let lock = NSLock()
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    struct Node: Decodable {
        let path, parent, name, identity, kind, issue: String
        let size, logical, modified, files: Int64
    }
    public init(root: String, stream: URL, cancellation: CancellationFlag) throws {
        self.root = root
        folder = URL(fileURLWithPath: "/private/tmp/alter-index-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            guard sqlite3_open_v2(folder.appendingPathComponent("index.sqlite").path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw failure() }
            try exec("PRAGMA cache_size=-8192; PRAGMA temp_store=FILE; PRAGMA journal_mode=OFF; PRAGMA max_page_count=131072; CREATE TABLE nodes(path TEXT PRIMARY KEY,parent TEXT,name TEXT,size INTEGER,logical INTEGER,modified INTEGER,identity TEXT,kind TEXT,files INTEGER,issue TEXT); BEGIN;")
            let insert = try prepare("INSERT INTO nodes VALUES(?,?,?,?,?,?,?,?,?,?)"); defer { sqlite3_finalize(insert) }
            let input = try FileHandle(forReadingFrom: stream); defer { try? input.close() }
            var pending = Data(), count = 0
            let decoder = JSONDecoder()
            while true {
                guard !cancellation.isCancelled else { throw AlterError.refused("索引导入已取消。") }
                let chunk = try input.read(upToCount: 65_536) ?? Data()
                if chunk.isEmpty { break }
                pending.append(chunk)
                while let end = pending.firstIndex(of: 10) {
                    let line = pending.prefix(upTo: end)
                    guard line.count <= 65_536, count < 2_000_000 else { throw AlterError.refused("索引超过预算。") }
                    let n = try decoder.decode(Node.self, from: line)
                    guard n.size >= 0, n.logical >= 0, n.files >= 0,
                          n.path == root || n.path.hasPrefix(root == "/" ? "/" : root + "/"),
                          n.path == root ? n.parent.isEmpty : URL(fileURLWithPath: n.path).deletingLastPathComponent().path == n.parent,
                          ["dir", "file", "link", "other"].contains(n.kind) else { throw AlterError.refused("空间索引格式无效。") }
                    sqlite3_reset(insert); sqlite3_clear_bindings(insert)
                    for (i, text) in [(1,n.path),(2,n.parent),(3,n.name),(7,n.identity),(8,n.kind),(10,n.issue)] { bind(insert, Int32(i), text) }
                    for (i, value) in [(4,n.size),(5,n.logical),(6,n.modified),(9,n.files)] { sqlite3_bind_int64(insert, Int32(i), value) }
                    guard sqlite3_step(insert) == SQLITE_DONE else { throw failure() }
                    if !n.issue.isEmpty && n.kind != "link" { incompleteNodes += 1 }
                    pending.removeSubrange(...end); count += 1
                }
                guard pending.count <= 65_536 else { throw AlterError.refused("索引记录过长。") }
            }
            guard pending.isEmpty, count > 0 else { throw AlterError.refused("索引未完整写入。") }
            try exec("COMMIT; CREATE INDEX children ON nodes(parent,size DESC,path); CREATE INDEX file_sizes ON nodes(kind,logical); CREATE INDEX ages ON nodes(kind,modified);")
            guard try hasDirectory(root) else { throw AlterError.refused("索引缺少根目录。") }
        } catch {
            if let db { sqlite3_close(db); self.db = nil }; MoleReader.clearJob(folder); throw error
        }
    }
    deinit { if let db { sqlite3_close(db) }; MoleReader.clearJob(folder) }
    private func failure() -> AlterError { .refused("空间索引读写失败：" + (db.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库")) }
    private func exec(_ sql: String) throws { guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure() } }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var p: OpaquePointer?; guard sqlite3_prepare_v2(db, sql, -1, &p, nil) == SQLITE_OK, let p else { throw failure() }; return p
    }
    private func bind(_ p: OpaquePointer, _ i: Int32, _ s: String) { _ = s.withCString { sqlite3_bind_text(p, i, $0, -1, Self.transient) } }
    private func string(_ p: OpaquePointer, _ i: Int32) -> String { sqlite3_column_text(p, i).map { String(cString: $0) } ?? "" }
    public func hasDirectory(_ path: String) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        let p = try prepare("SELECT 1 FROM nodes WHERE path=? AND kind='dir'"); defer { sqlite3_finalize(p) }; bind(p,1,path)
        return sqlite3_step(p) == SQLITE_ROW
    }
    public func snapshot(_ path: String) throws -> DiskSnapshot {
        lock.lock(); defer { lock.unlock() }
        let rootQuery = try prepare("SELECT size,files,issue FROM nodes WHERE path=? AND kind='dir'"); defer { sqlite3_finalize(rootQuery) }; bind(rootQuery,1,path)
        guard sqlite3_step(rootQuery) == SQLITE_ROW else { throw AlterError.refused("目录不在当前索引中，请选择它单独分析。") }
        let size = sqlite3_column_int64(rootQuery,0), files = sqlite3_column_int64(rootQuery,1), issue = string(rootQuery,2)
        guard issue.isEmpty else { throw AlterError.refused("此目录未能完整读取（\(issue)），请授予访问权限后重新分析。") }
        let p = try prepare("SELECT path,name,size,kind FROM nodes WHERE parent=? ORDER BY size DESC,path LIMIT 256"); defer { sqlite3_finalize(p) }; bind(p,1,path)
        var entries: [DiskEntry] = []
        while sqlite3_step(p) == SQLITE_ROW { entries.append(DiskEntry(name: string(p,1),path: string(p,0),size: sqlite3_column_int64(p,2),isDir: string(p,3) == "dir")) }
        let count = try prepare("SELECT COUNT(*) FROM nodes WHERE parent=?"); defer { sqlite3_finalize(count) }; bind(count,1,path)
        guard sqlite3_step(count) == SQLITE_ROW else { throw failure() }
        return DiskSnapshot(path:path,entries:entries,totalSize:size,totalFiles:files,childCount:Int(sqlite3_column_int64(count,0)))
    }
    public func children(_ path: String, query: String = "", excluding: Set<String> = [], page: Int = 0) throws -> (entries: [DiskEntry], count: Int) {
        lock.lock(); defer { lock.unlock() }
        guard excluding.count <= 23, page >= 0, page <= 20_000 else { throw AlterError.refused("无效索引查询。") }
        let excluded = excluding.sorted()
        let whereClause = "parent=? AND instr(lower(name),lower(?))>0" + (excluded.isEmpty ? "" : " AND path NOT IN (" + Array(repeating:"?",count:excluded.count).joined(separator:",") + ")")
        func arguments(_ p: OpaquePointer) { bind(p,1,path); bind(p,2,query); for (i,value) in excluded.enumerated() { bind(p,Int32(i+3),value) } }
        let countQuery = try prepare("SELECT COUNT(*) FROM nodes WHERE " + whereClause); defer { sqlite3_finalize(countQuery) }; arguments(countQuery)
        guard sqlite3_step(countQuery) == SQLITE_ROW else { throw failure() }; let count = Int(sqlite3_column_int64(countQuery,0))
        let p = try prepare("SELECT path,name,size,kind FROM nodes WHERE " + whereClause + " ORDER BY size DESC,path LIMIT 100 OFFSET ?"); defer { sqlite3_finalize(p) }; arguments(p); sqlite3_bind_int64(p,Int32(excluded.count+3),Int64(page)*100)
        var entries: [DiskEntry] = [], state = sqlite3_step(p)
        while state == SQLITE_ROW { entries.append(DiskEntry(name:string(p,1),path:string(p,0),size:sqlite3_column_int64(p,2),isDir:string(p,3) == "dir")); state=sqlite3_step(p) }
        guard state == SQLITE_DONE else { throw failure() }; return (entries,count)
    }
    public func issues() throws -> Int { incompleteNodes }
    /// Cursor pagination keeps even a large flat directory or duplicate-size group bounded.
    public func files(minimumSize: Int64 = 0, olderThan: Int64 = Int64.max, exactSize: Int64? = nil, after: String = "", limit: Int = 500) throws -> [IndexedFile] {
        lock.lock(); defer { lock.unlock() }
        let p = try prepare("SELECT path,name,size,logical,modified,identity FROM nodes WHERE kind='file' AND logical>=? AND modified<=? AND path>?" + (exactSize == nil ? "" : " AND logical=?") + " ORDER BY path LIMIT ?")
        defer { sqlite3_finalize(p) }
        sqlite3_bind_int64(p,1,minimumSize); sqlite3_bind_int64(p,2,olderThan); bind(p,3,after)
        var slot: Int32 = 4
        if let exactSize { sqlite3_bind_int64(p,slot,exactSize); slot += 1 }
        sqlite3_bind_int(p,slot,Int32(max(1,min(limit,1000))))
        var result: [IndexedFile] = []
        while sqlite3_step(p) == SQLITE_ROW { result.append(IndexedFile(path:string(p,0),name:string(p,1),identity:string(p,5),size:sqlite3_column_int64(p,2),logical:sqlite3_column_int64(p,3),modified:sqlite3_column_int64(p,4))) }
        return result
    }
    public func duplicateSizes(after: Int64 = 0) throws -> [Int64] {
        lock.lock(); defer { lock.unlock() }
        let p = try prepare("SELECT logical FROM nodes WHERE kind='file' AND logical>? GROUP BY logical HAVING COUNT(DISTINCT identity)>1 ORDER BY logical LIMIT 256")
        defer { sqlite3_finalize(p) }; sqlite3_bind_int64(p,1,after)
        var result: [Int64] = []; while sqlite3_step(p) == SQLITE_ROW { result.append(sqlite3_column_int64(p,0)) }; return result
    }
}
