import Foundation
import Darwin

/// User exclusions supplement Mole's rules; removing a parent of an excluded
/// descendant is also refused. Corrupt settings fail closed.
public struct ProtectionStore: Sendable {
    public let home: String
    public init(home: String = FileManager.default.homeDirectoryForCurrentUser.path) { self.home = home }
    private var folder: URL { URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Alter") }
    public func load() throws -> [String] {
        let file = folder.appendingPathComponent("protected.json")
        var st = stat()
        if lstat(file.path, &st) != 0 { if errno == ENOENT { return [] }; throw AlterError.refused("无法读取保护名单，已停止写操作。") }
        guard FileSafety.regular(st), st.st_uid == getuid(), st.st_size <= 131_072 else { throw AlterError.refused("保护名单无法验证。") }
        let parent = try FileSafety.openDirectory(folder.path); defer { close(parent) }
        let fd = openat(parent,"protected.json",O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw AlterError.refused("保护名单已变化。") }
        var opened = stat()
        guard fstat(fd,&opened) == 0, FileSafety.regular(opened), opened.st_uid == getuid(), opened.st_size <= 131_072 else { close(fd); throw AlterError.refused("保护名单文件已变化。") }
        let input = FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        let data = try input.read(upToCount:131_073) ?? Data()
        guard data.count <= 131_072 else { throw AlterError.refused("保护名单过大。") }
        let paths = try JSONDecoder().decode([String].self,from:data)
        guard paths.count <= 1000, paths.allSatisfy(FileSafety.validPath) else { throw AlterError.refused("保护名单格式无效。") }; return paths
    }
    public func save(_ paths: [String]) throws {
        let paths = Array(Set(paths)).sorted()
        guard paths.count <= 1000, paths.allSatisfy(FileSafety.validPath) else { throw AlterError.refused("最多保护 1000 个有效路径。") }
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let parent = try FileSafety.openDirectory(folder.path); defer { close(parent) }
        var s = stat(); guard fstat(parent,&s) == 0, s.st_uid == getuid(), s.st_mode & 0o022 == 0 else { throw AlterError.refused("保护名单目录权限不安全。") }
        let data = try JSONEncoder().encode(paths); guard data.count <= 131_072 else { throw AlterError.refused("保护名单过大。") }
        let name = ".protected-" + UUID().uuidString
        let fd = openat(parent,name,O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,0o600)
        guard fd >= 0 else { throw AlterError.refused("无法保存保护名单。") }
        defer { close(fd); unlinkat(parent,name,0) }
        let written = data.withUnsafeBytes { Darwin.write(fd,$0.baseAddress,data.count) }
        guard written == data.count, fsync(fd) == 0, renameat(parent,name,parent,"protected.json") == 0 else { throw AlterError.refused("保护名单保存失败。") }
    }
    public func requireUnprotected(_ path: String) throws {
        for entry in try load() where path == entry || path.hasPrefix(entry == "/" ? "/" : entry + "/") || entry.hasPrefix(path + "/") {
            throw AlterError.refused("保护名单保留此项目：" + entry)
        }
    }
}
