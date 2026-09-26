import Foundation
import Darwin
import CryptoKit

public struct DuplicateGroup: Identifiable, Sendable {
    public let id: String
    public let files: [IndexedFile]
}
public struct DuplicateReport: Sendable {
    public let groups: [DuplicateGroup]
    public let checked: Int, skipped: Int
    public let notes: [String]
}
public enum DuplicateFinder {
    public static func revalidate(_ groups: [DuplicateGroup], selected: Set<String>, cancellation: CancellationFlag) throws {
        let deadline = Date().addingTimeInterval(300)
        for group in groups where group.files.contains(where: { selected.contains($0.path) }) {
            let retained = group.files.filter { !selected.contains($0.path) }
            guard !retained.isEmpty else { throw AlterError.refused("每组至少保留一份重复文件。") }
            var verifiedCopy = false
            for file in retained {
                if (try? digest(file,cancellation:cancellation,deadline:deadline)) == group.id { verifiedCopy = true; break }
            }
            guard verifiedCopy else { throw AlterError.refused("保留副本已变化或不可读，请重新查重。") }
            for file in group.files where selected.contains(file.path) {
                guard try digest(file,cancellation:cancellation,deadline:deadline) == group.id else { throw AlterError.refused("待移除文件已变化，请重新查重。") }
            }
        }
    }

    /// Full SHA-256, one 1 MiB buffer, no memory mapping or cloud download.
    /// Metadata is checked before and after hashing; no symlink/hardlink aliases.
    static func digest(_ file: IndexedFile, cancellation: CancellationFlag, deadline: Date) throws -> String {
        let parent = try FileSafety.openDirectory(URL(fileURLWithPath:file.path).deletingLastPathComponent().path); defer { close(parent) }
        let fd = openat(parent,file.name,O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw AlterError.refused("文件不可读。") }; defer { close(fd) }
        var before = stat()
        guard fstat(fd,&before) == 0, FileSafety.regular(before), before.st_flags & UInt32(SF_DATALESS) == 0,
              "\(before.st_dev):\(before.st_ino)" == file.identity, before.st_size == file.logical else { throw AlterError.refused("跳过已变化或仅在云端的文件。") }
        var hash = SHA256(), buffer = [UInt8](repeating:0,count:1_048_576), bytes: Int64 = 0
        while true {
            guard !cancellation.isCancelled, Date() < deadline else { throw AlterError.refused("重复文件检查已停止。") }
            let count = Darwin.read(fd,&buffer,buffer.count)
            if count == 0 { break }; if count < 0 { if errno == EINTR { continue }; throw AlterError.refused("读取文件失败。") }
            hash.update(data:Data(buffer.prefix(count))); bytes += Int64(count)
        }
        var after = stat()
        guard bytes == file.logical, fstat(fd,&after) == 0, FileSafety.identity(before) == FileSafety.identity(after) else { throw AlterError.refused("文件在检查期间变化。") }
        return hash.finalize().map { String(format:"%02x",$0) }.joined()
    }
    public static func find(in index: DiskIndex, cancellation: CancellationFlag) throws -> DuplicateReport {
        let deadline = Date().addingTimeInterval(900)
        var groups: [DuplicateGroup] = [], checked = 0, skipped = 0, sizeCursor: Int64 = 0
        var notes: [String] = []
        while true {
            let sizes = try index.duplicateSizes(after:sizeCursor); if sizes.isEmpty { break }
            for size in sizes {
                var cursor = "", hashes: [String:[IndexedFile]] = [:], identities: Set<String> = []
                while true {
                    let batch = try index.files(exactSize:size,after:cursor); if batch.isEmpty { break }
                    for file in batch {
                        guard !cancellation.isCancelled, Date() < deadline, checked + skipped < 100_000, groups.count < 1000 else { throw AlterError.refused("重复文件检查已停止或达到预算，请缩小目录后重试。") }
                        guard identities.insert(file.identity).inserted else { skipped += 1; continue }
                        // Per-size group metadata is bounded even for millions of tiny identical files.
                        guard identities.count <= 10_000 else { throw AlterError.refused("同尺寸文件超过单组预算，请选择子目录检查。") }
                        do { let key = try digest(file,cancellation:cancellation,deadline:deadline); hashes[key,default:[]].append(file); checked += 1 }
                        catch { if cancellation.isCancelled { throw error }; skipped += 1; if notes.count < 8 { notes.append(file.path + ": " + error.localizedDescription) } }
                    }
                    cursor = batch.last!.path
                }
                for (hash,files) in hashes where files.count > 1 {
                    guard groups.reduce(0, { $0 + $1.files.count }) + files.count <= 10_000 else { throw AlterError.refused("重复结果超过 10,000 项，请分目录检查。") }
                    groups.append(DuplicateGroup(id:hash,files:files.sorted { $0.path < $1.path }))
                }
                sizeCursor = size
            }
        }
        return DuplicateReport(groups:groups.sorted { $0.files[0].logical > $1.files[0].logical },checked:checked,skipped:skipped,notes:notes)
    }
}
