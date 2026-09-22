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
    var fullResources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/test-resources")
    }
    func testRealMoleAnalyzerIncludesSmallHiddenAndPackageEntries() throws {
        try file("Private/.hidden", count: 4096)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Private/Example.app"), withIntermediateDirectories: false)
        try file("Private/Example.app/contents", count: 8192)
        try file("Private/small.txt", count: 2048)
        let snapshot = try MoleReader(resources: fullResources).analyze(home.appendingPathComponent("Private").path, cancellation: CancellationFlag())
        XCTAssertTrue(snapshot.entries.contains { $0.name == ".hidden" })
        XCTAssertTrue(snapshot.entries.contains { $0.name == "small.txt" })
        XCTAssertTrue(snapshot.entries.contains { $0.name == "Example.app" && $0.isDir })
        XCTAssertTrue(snapshot.totalSize > 0)
        let alias = home.appendingPathComponent("Alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: home.appendingPathComponent("Private"))
        let aliased = try MoleReader(resources: fullResources).analyze(alias.path, cancellation: CancellationFlag())
        XCTAssertEqual(aliased.path, snapshot.path)
    }
    func testRealMoleInstallerDiscoveryAndFullPolicy() throws {
        let url = try file("Downloads/current.dmg", count: 4096)
        let ops = MoleOperations(resources: fullResources, home: home.path)
        let found = try ops.discover(.installer, path: home.appendingPathComponent("Downloads").path, cancellation: CancellationFlag())
        XCTAssertTrue(found.candidates.contains { $0.path == url.path })
        let allowed = try ops.review([url.path, home.path + "/.ssh/id_ed25519"], cancellation: CancellationFlag())
        XCTAssertEqual(allowed, [true, false])
        XCTAssertEqual(try Data(contentsOf: url).count, 4096)
    }
    func testOptimizeCatalogContainsEveryUpstreamTask() throws {
        let tasks = try MoleOperations(resources: fullResources, home: home.path).optimizeTasks(cancellation: CancellationFlag())
        let source = try String(contentsOf: fullResources.appendingPathComponent("MoleFull/lib/optimize/catalog.sh"), encoding: .utf8)
        let expected = source.components(separatedBy: "\n").filter { $0.hasPrefix("_optimize_catalog_register ") }.count
        XCTAssertEqual(tasks.count, expected)
        XCTAssertTrue(tasks.contains { $0.id == "sqlite_vacuum" })
        XCTAssertTrue(tasks.contains { $0.id == "disk_permissions_repair" })
        let whitelist = home.appendingPathComponent(".config/mole")
        try FileManager.default.createDirectory(at: whitelist, withIntermediateDirectories: true)
        try "prevent_network_dsstore\n".write(to: whitelist.appendingPathComponent("whitelist_optimize"), atomically: true, encoding: .utf8)
        let task = tasks.first { $0.id == "prevent_network_dsstore" }!
        let preview = try MoleOperations(resources: fullResources, home: home.path).preview(task, cancellation: CancellationFlag())
        XCTAssertEqual(preview.outcome, "skipped")
    }
    func testRealMolePurgeAndUninstallPreview() throws {
        let project = home.appendingPathComponent("Project")
        try FileManager.default.createDirectory(at: project.appendingPathComponent("node_modules/example"), withIntermediateDirectories: true)
        try "{}".write(to: project.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: project.appendingPathComponent("node_modules/example/package.json"), atomically: true, encoding: .utf8)
        let ops = MoleOperations(resources: fullResources, home: home.path)
        let artifacts = try ops.discover(.purge, path: project.path, cancellation: CancellationFlag())
        XCTAssertTrue(artifacts.candidates.contains { $0.path == project.appendingPathComponent("node_modules").path })
        let app = home.appendingPathComponent("Applications/AlterFixtureUnique.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "io.alter.fixture.unique", "CFBundleName": "AlterFixtureUnique", "CFBundleExecutable": "fixture", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try Data("fixture-only".utf8).write(to: app.appendingPathComponent("Contents/MacOS/fixture"))
        let related = home.appendingPathComponent("Library/Caches/io.alter.fixture.unique")
        try FileManager.default.createDirectory(at: related, withIntermediateDirectories: true)
        let result = try ops.discover(.uninstall, path: app.path, cancellation: CancellationFlag())
        XCTAssertTrue(result.candidates.contains { $0.path == app.path })
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: related.path))
    }
    func testRealMoleCleanPreviewNeverChangesFixture() throws {
        let cache = home.appendingPathComponent("Library/Caches/io.alter.cleanfixture")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let sentinel = cache.appendingPathComponent("cache.bin")
        let content = Data(repeating: 17, count: 1024 * 1024)
        try content.write(to: sentinel)
        let result = try MoleOperations(resources: fullResources, home: home.path).discover(.clean, cancellation: CancellationFlag())
        if !result.candidates.contains(where: { $0.path == cache.path || $0.path == sentinel.path }) { throw AlterError.refused(result.notices.joined(separator: "\n")) }
        XCTAssertEqual(try Data(contentsOf: sentinel), content)
    }
    func testFullPolicyProtectsRunningCacheOwner() throws {
        let cache = home.appendingPathComponent("Library/Caches/io.alter.runningfixture")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 5, count: 1024).write(to: cache.appendingPathComponent("cache.bin"))
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "exec -a io.alter.runningfixture /bin/sleep 30"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); defer { if process.isRunning { process.terminate() }; process.waitUntilExit() }
        let result = try MoleOperations(resources: fullResources, home: home.path).review([cache.path], cancellation: CancellationFlag())
        XCTAssertEqual(result, [false])
    }
    func testRealMoleStatusReturnsMeasuredFields() throws {
        let data = try MoleReader(resources: fullResources).status(cancellation: CancellationFlag())
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertTrue(json?["cpu"] is [String: Any])
        XCTAssertTrue(json?["memory"] is [String: Any])
        XCTAssertLessThanOrEqual(data.count, 8 * 1024 * 1024)
    }
    func testReviewedDirectoryMoveRestoreAndChangedChildren() throws {
        let url = try file("Private/inside.txt")
        let candidate = MoleCandidate(category: "artifact", path: home.appendingPathComponent("Private").path, bytes: 0, note: "fixture")
        let flag = CancellationFlag()
        let before = try ReviewedRemoval.snapshot(candidate, home: home.path, cancellation: flag)
        try Data(repeating: 1, count: 1200).write(to: url)
        XCTAssertThrowsError(try ReviewedRemoval.move(before, home: home.path, created: Date(), cancellation: flag))
        let reviewed = try ReviewedRemoval.snapshot(candidate, home: home.path, cancellation: flag)
        let record = try ReviewedRemoval.move(reviewed, home: home.path, created: Date(), cancellation: flag)
        XCTAssertFalse(FileManager.default.fileExists(atPath: candidate.path))
        try TrashService(home: home.path).restore(record)
        XCTAssertEqual(try Data(contentsOf: url).count, 1200)
    }
    func testReviewedPlanRejectsParentsAndProtectedRoots() throws {
        let url = try file("Private/inside.txt")
        let flag = CancellationFlag()
        let parent = try ReviewedRemoval.snapshot(MoleCandidate(category: "cache", path: home.appendingPathComponent("Private").path, bytes: 0, note: "fixture"), home: home.path, cancellation: flag)
        let child = try ReviewedRemoval.snapshot(MoleCandidate(category: "cache", path: url.path, bytes: 0, note: "fixture"), home: home.path, cancellation: flag)
        XCTAssertThrowsError(try ReviewedPlan(items: [parent, child]))
        XCTAssertThrowsError(try ReviewedRemoval.snapshot(MoleCandidate(category: "cache", path: home.path, bytes: 0, note: "fixture"), home: home.path, cancellation: flag))
        XCTAssertThrowsError(try ReviewedRemoval.snapshot(MoleCandidate(category: "cache", path: "/System", bytes: 0, note: "fixture"), home: home.path, cancellation: flag))
    }
    func testPreviewSandboxRejectsWritesOutsideJob() throws {
        let sentinel = try file("Private/valuable.txt")
        let job = home.appendingPathComponent("Job")
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: false)
        XCTAssertThrowsError(try BoundedProcess.run(executable: "/usr/bin/sandbox-exec", arguments: ["-D", "JOB=" + job.path, "-f", fullResources.appendingPathComponent("mole-preview.sb").path, "/bin/bash", "-c", "printf changed > \"$1\"", "test", sentinel.path], environment: ["PATH": "/usr/bin:/bin"], directory: job, cancellation: CancellationFlag(), seconds: 5))
        XCTAssertEqual(try Data(contentsOf: sentinel).count, 1024)
    }
    func testProcessTimeoutAndOutputBudget() throws {
        let job = home.appendingPathComponent("Budget")
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: false)
        let start = Date()
        XCTAssertThrowsError(try BoundedProcess.run(executable: "/bin/bash", arguments: ["-c", "sleep 20 & wait"], environment: ["PATH": "/usr/bin:/bin"], directory: job, cancellation: CancellationFlag(), seconds: 0.1))
        XCTAssertTrue(Date().timeIntervalSince(start) < 3)
        let output = home.appendingPathComponent("Output")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        XCTAssertThrowsError(try BoundedProcess.run(executable: "/bin/bash", arguments: ["-c", "printf '%4096s' x"], environment: ["PATH": "/usr/bin:/bin"], directory: output, cancellation: CancellationFlag(), seconds: 5, maxOutput: 256))
    }
    func testLensCirclesDoNotOverlapAndPreserveArea() throws {
        let entries = (1...35).map { DiskEntry(name: "item\($0)", path: "/fixture/\($0)", size: Int64(100000 / $0), isDir: true) }
        let bubbles = LensLayout.pack(entries)
        XCTAssertTrue(bubbles.count <= 23)
        XCTAssertEqual(bubbles.reduce(Int64(0)) { $0 + $1.bytes }, entries.reduce(Int64(0)) { $0 + $1.size })
        for a in bubbles {
            XCTAssertLessThanOrEqual(hypot(a.x, a.y) + a.radius, 1.000001)
            for b in bubbles where a.id != b.id { XCTAssertTrue(hypot(a.x - b.x, a.y - b.y) >= a.radius + b.radius - 0.000001) }
            let ratio = a.radius * a.radius / Double(a.bytes)
            let reference = bubbles[0].radius * bubbles[0].radius / Double(bubbles[0].bytes)
            XCTAssertTrue(abs(ratio / reference - 1) < 0.000001)
        }
    }
}
