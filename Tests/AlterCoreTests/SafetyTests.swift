import XCTest
import Foundation
import Darwin
@testable import AlterCore

final class SafetyTests: XCTestCase {
    var home: URL!
    let future = Date().addingTimeInterval(365 * 86400)
    override func setUpWithError() throws {
        home = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("alter-test-" + UUID().uuidString)
        for name in ["Downloads", ".Trash", "Downloads/Nested", "Private"] { try FileManager.default.createDirectory(at: home.appendingPathComponent(name), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
    }
    override func tearDownWithError() throws {
        // Only fixture tree created by this test. Never points at the real home.
        guard let home, home.lastPathComponent.hasPrefix("alter-test-") else { return }
        try FileManager.default.removeItem(at: home)
    }
    @discardableResult func file(_ relative: String, count: Int = 1024) throws -> URL {
        let url = home.appendingPathComponent(relative); try Data(repeating: 42, count: count).write(to: url); return url
    }
    func entry(_ url: URL) throws -> ScanEntry {
        let info = try FileSafety.metadata(url.path)
        return ScanEntry(path: url.path, kind: .installer, bytes: info.st_size, identity: FileSafety.identity(info), canTrash: true)
    }
    func testRecentInstallerIsNotEligible() throws {
        let url = try file("Downloads/Fresh.dmg")
        XCTAssertFalse(FileSafety.installerEligible(path: url.path, home: home.path, info: try FileSafety.metadata(url.path)))
    }
    func testNoDocumentsOrRootOrTraversal() throws {
        let url = try file("Private/notes.dmg")
        XCTAssertFalse(FileSafety.installerEligible(path: url.path, home: home.path, info: try FileSafety.metadata(url.path), now: future))
        XCTAssertFalse(FileSafety.validPath(home.path + "/Downloads/../Private/a.dmg"))
        XCTAssertFalse(FileSafety.validPath("/Downloads/hello\n.dmg"))
    }
    func testSymlinkDirectoryIsRefused() throws {
        try FileManager.default.createSymbolicLink(atPath: home.appendingPathComponent("Downloads/Link").path, withDestinationPath: home.appendingPathComponent("Private").path)
        XCTAssertThrowsError(try FileSafety.openDirectory(home.appendingPathComponent("Downloads/Link").path))
        let secret = try file("Private/secret.dmg")
        let report = BoundedScanner(home: home.path).scan(root: home.appendingPathComponent("Downloads").path, mode: .installer, cancellation: CancellationFlag(), now: future)
        XCTAssertTrue(report.entries.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: secret.path))
    }
    func testSymlinkLeafAndHardlinkAreExcluded() throws {
        let original = try file("Downloads/Original.dmg")
        let symlink = home.appendingPathComponent("Downloads/Linked.dmg")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: original)
        XCTAssertFalse(FileSafety.installerEligible(path: symlink.path, home: home.path, info: try FileSafety.metadata(symlink.path), now: future))
        let hard = home.appendingPathComponent("Downloads/Hard.dmg")
        XCTAssertEqual(link(original.path, hard.path), 0)
        XCTAssertFalse(FileSafety.installerEligible(path: original.path, home: home.path, info: try FileSafety.metadata(original.path), now: future))
    }
    func testScanLimitsAndCancellation() throws {
        for n in 0..<40 { try file("Downloads/\(n).dmg") }
        let report = BoundedScanner(home: home.path, limits: ScanLimits(maxEntries: 10, maxResults: 3)).scan(root: home.appendingPathComponent("Downloads").path, mode: .installer, cancellation: CancellationFlag(), now: future)
        XCTAssertTrue(report.incomplete); XCTAssertLessThanOrEqual(report.visited, 10); XCTAssertLessThanOrEqual(report.entries.count, 3)
        let flag = CancellationFlag(); flag.cancel()
        let stopped = BoundedScanner(home: home.path).scan(root: home.appendingPathComponent("Downloads").path, mode: .installer, cancellation: flag, now: future)
        XCTAssertTrue(stopped.incomplete); XCTAssertEqual(stopped.visited, 0)
    }
    func testTrashAndRestoreWithoutContentChanges() throws {
        let url = try file("Downloads/Archive.dmg")
        let before = try Data(contentsOf: url)
        let service = TrashService(home: home.path)
        let record = try service.move(try entry(url), planCreated: future, now: future)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: home.appendingPathComponent(".Trash/" + record.trashName)), before)
        try service.restore(record)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }
    func testChangedFileRejected() throws {
        let url = try file("Downloads/Changed.dmg"), snapshot = try entry(url)
        try Data(repeating: 7, count: 4096).write(to: url)
        XCTAssertThrowsError(try TrashService(home: home.path).move(snapshot, planCreated: future, now: future))
        XCTAssertEqual(try Data(contentsOf: url).count, 4096)
    }
    func testRestoreNeverOverwrites() throws {
        let url = try file("Downloads/Collision.dmg")
        let service = TrashService(home: home.path)
        let record = try service.move(try entry(url), planCreated: future, now: future)
        let newer = Data(repeating: 99, count: 99); try newer.write(to: url)
        XCTAssertThrowsError(try service.restore(record))
        XCTAssertEqual(try Data(contentsOf: url), newer)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(".Trash/" + record.trashName).path))
    }
    func testExpiredPlanRefused() throws {
        let url = try file("Downloads/Expired.dmg")
        XCTAssertThrowsError(try TrashService(home: home.path).move(try entry(url), planCreated: future.addingTimeInterval(-301), now: future))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testReplacedParentRefusedAndOutsideUnchanged() throws {
        let url = try file("Downloads/Nested/Payload.dmg"), snapshot = try entry(url)
        try FileManager.default.moveItem(at: home.appendingPathComponent("Downloads/Nested"), to: home.appendingPathComponent("Private/Moved"))
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Downloads/Nested"), withDestinationURL: home.appendingPathComponent("Private/Moved"))
        XCTAssertThrowsError(try TrashService(home: home.path).move(snapshot, planCreated: future, now: future))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Private/Moved/Payload.dmg").path))
    }
    func testPlanCannotContainUnreviewedOrDuplicateEntries() throws {
        let url = try file("Downloads/A.dmg"), reviewed = try entry(url)
        var readonly = reviewed; readonly.canTrash = false
        XCTAssertThrowsError(try RemovalPlan(entries: [readonly]))
        XCTAssertThrowsError(try RemovalPlan(entries: [reviewed, reviewed]))
    }
    func testHistoryRejectsSymlink() throws {
        let directory = home.appendingPathComponent("History")
        let store = HistoryStore(directory: directory)
        try store.save([])
        let target = try file("Private/valuable.json")
        try FileManager.default.removeItem(at: directory.appendingPathComponent("history.json"))
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("history.json"), withDestinationURL: target)
        XCTAssertThrowsError(try store.save([])); XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: target).count, 1024)
    }
    func testMoleLiveProtectionCoreAndSandbox() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repo.appendingPathComponent("Sources/AlterApp/Resources/Mole")
        let policy = MolePolicy(root: root, home: home.path)
        let values = try policy.review([home.path + "/Library/Application Support/Codex", home.path + "/Library/Caches/com.apple.finder", home.path + "/Downloads/Example.dmg"], cancellation: CancellationFlag())
        XCTAssertEqual(values, [false, false, true])
        let protected = try file("Private/sandbox-sentinel")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-f", root.appendingPathComponent("policy.sb").path, "/bin/bash", "--noprofile", "--norc", "-c", "printf changed > \"$1\"", "alter-sandbox-test", protected.path]
        process.standardError = FileHandle.nullDevice; try process.run(); process.waitUntilExit()
        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertEqual(try Data(contentsOf: protected).count, 1024)
    }
}
