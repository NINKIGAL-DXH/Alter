import SwiftUI
import AppKit
import AlterCore

enum AppPage: String, CaseIterable, Identifiable {
    case overview = "总览", clean = "智能清理", storage = "磁盘空间", apps = "应用管理", companion = "Alter 陪伴", history = "操作记录", settings = "设置"
    var id: String { rawValue }
    var icon: String { switch self { case .overview: "square.grid.2x2"; case .clean: "sparkles"; case .storage: "internaldrive"; case .apps: "square.stack.3d.up"; case .companion: "moon.stars"; case .history: "clock.arrow.circlepath"; case .settings: "slider.horizontal.3" } }
    var expression: Int { switch self { case .overview: 1; case .clean: 4; case .storage: 15; case .apps: 17; case .companion: 2; case .history: 23; case .settings: 18 } }
}
@MainActor final class AppModel: ObservableObject {
    @Published var page: AppPage = .overview { didSet { expression = page.expression } }
    @Published var appQuery = ""
    @Published var expressionsPlaying = false
    @Published var expression = 1
    @Published var busy = false
    @Published var activity = "准备好了。先查看，再决定。"
    @Published var errorMessage: String?
    @Published var installers: [ScanEntry] = []
    @Published var caches: [ScanEntry] = []
    @Published var largeFiles: [ScanEntry] = []
    @Published var applications: [ScanEntry] = []
    @Published var selected: Set<String> = []
    @Published var pendingPlan: RemovalPlan?
    @Published var showConfirmation = false
    @Published var scanSummary = "尚未扫描"
    @Published var storageSummary = "请选择一个文件夹进行只读分析。"
    @Published var appSummary = "尚未读取应用目录。"
    @Published var records: [TrashRecord] = []
    @Published var totalCapacity: Int64 = 0
    @Published var freeCapacity: Int64 = 0
    @AppStorage("appearance") var appearance = 0
    @AppStorage("companionVisible") var companionVisible = true
    @AppStorage("heroExpression") var heroExpression = 1
    private var cancellation = CancellationFlag()
    private var worker: Task<Void, Never>?
    private var pressure: DispatchSourceMemoryPressure?
    private let home = FileManager.default.homeDirectoryForCurrentUser.path
    private var history: HistoryStore { HistoryStore(directory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Alter")) }
    init() {
        refreshCapacity()
        do { records = try history.load() } catch { errorMessage = error.localizedDescription }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in Task { @MainActor in self?.cancel(); Assets.cache.removeAllObjects(); self?.activity = "系统内存紧张，已停止扫描并释放图片缓存。" } }
        source.resume(); pressure = source
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.cancel() } }
    }
    var selectedEntries: [ScanEntry] { installers.filter { selected.contains($0.id) && $0.canTrash } }
    var selectedBytes: Int64 { selectedEntries.reduce(0) { $0 + $1.bytes } }
    var reclaimBytes: Int64 { installers.filter(\.canTrash).reduce(0) { $0 + $1.bytes } }
    var currentExpression: Expression? { Assets.expressions.first { $0.id == expression } }
    func refreshCapacity() {
        if let values = try? URL(fileURLWithPath: home).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]) {
            totalCapacity = Int64(values.volumeTotalCapacity ?? 0); freeCapacity = Int64(values.volumeAvailableCapacity ?? 0)
        }
    }
    func cancel() { cancellation.cancel(); activity = "正在停止，请稍候…" }
    private func begin(_ message: String) -> CancellationFlag? {
        guard !busy, geteuid() != 0 else { if geteuid() == 0 { errorMessage = "Alter 拒绝以 root 身份运行。" }; return nil }
        busy = true; activity = message; cancellation = CancellationFlag(); return cancellation
    }
    func scanClean() {
        guard let flag = begin("正在只读扫描下载目录与缓存…") else { return }
        page = .clean; expression = 7; selected.removeAll(); installers = []; caches = []
        let home = self.home, policy = MolePolicy(root: Assets.root.appendingPathComponent("Mole"), home: self.home)
        worker = Task {
            let result = await Task.detached(priority: .utility) { () -> (ScanReport, ScanReport, String?) in
                var downloads = BoundedScanner(home: home, limits: ScanLimits(maxEntries: 30_000, maxResults: 128, maxDepth: 1, seconds: 10)).scan(root: home + "/Downloads", mode: .installer, cancellation: flag)
                var policyError: String?
                if !downloads.incomplete && !flag.isCancelled {
                    do {
                        for offset in stride(from: 0, to: downloads.entries.count, by: 64) {
                            let end = min(offset + 64, downloads.entries.count)
                            let allowed = try policy.review(downloads.entries[offset..<end].map(\.path), cancellation: flag)
                            for (relative, yes) in allowed.enumerated() {
                                downloads.entries[offset + relative].canTrash = yes
                                downloads.entries[offset + relative].note = yes ? "已通过 Mole 保护检查 · 仅可移入废纸篓" : "Mole 保护或白名单命中 · 保留"
                            }
                        }
                    } catch { policyError = error.localizedDescription; for i in downloads.entries.indices { downloads.entries[i].canTrash = false } }
                }
                let cacheReport = flag.isCancelled ? ScanReport() : BoundedScanner(home: home, limits: ScanLimits(maxEntries: 60_000, maxResults: 64, maxDepth: 12, seconds: 12)).scan(root: home + "/Library/Caches", mode: .cache, cancellation: flag)
                return (downloads, cacheReport, policyError)
            }.value
            installers = result.0.entries; caches = result.1.entries
            if flag.isCancelled { selected.removeAll(); for i in installers.indices { installers[i].canTrash = false } }
            let messages = result.0.messages + result.1.messages
            scanSummary = "检查了 \(result.0.visited + result.1.visited) 项 · " + (messages.isEmpty ? "只读扫描完成" : messages.joined(separator: " "))
            if let failure = result.2 { errorMessage = failure }
            activity = flag.isCancelled ? "扫描已取消。" : "扫描结束；未修改任何文件。"
            expression = flag.isCancelled ? 3 : 10; busy = false; refreshCapacity()
        }
    }
    func analyzeFolder() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "选择只读分析的文件夹。不会跟随符号链接、读取文件内容或下载云端文件。"
        guard panel.runModal() == .OK, let url = panel.url else { expression = 3; return }
        guard let flag = begin("正在分析所选文件夹…") else { return }
        page = .storage; let home = self.home
        worker = Task {
            let report = await Task.detached(priority: .utility) { BoundedScanner(home: home).scan(root: url.path, mode: .largeFile, cancellation: flag) }.value
            largeFiles = report.entries
            storageSummary = "\(url.lastPathComponent) · 已统计 \(byteText(report.bytes)) · \(report.visited) 项。" + report.messages.joined(separator: " ")
            busy = false; activity = flag.isCancelled ? "分析已停止。" : "分析完成；大文件仅供查看。"; expression = 15
        }
    }
    func scanApps() {
        guard let flag = begin("正在只读统计应用…") else { return }
        page = .apps; let home = self.home
        worker = Task {
            let report = await Task.detached(priority: .utility) { BoundedScanner(home: home, limits: ScanLimits(maxEntries: 100_000, maxResults: 200, maxDepth: 14, seconds: 20)).scan(root: "/Applications", mode: .application, cancellation: flag) }.value
            applications = report.entries; busy = false
            appSummary = "已读取 \(applications.count) 个应用。" + report.messages.joined(separator: " ")
            activity = "应用统计结束。本版本不执行卸载或关联文件删除。"; expression = 17
        }
    }
    func confirmSelected() {
        guard !busy else { return }
        do { pendingPlan = try RemovalPlan(entries: selectedEntries); showConfirmation = true; expression = 20 }
        catch { errorMessage = error.localizedDescription }
    }
    func executeConfirmed() {
        guard let plan = pendingPlan, let flag = begin("正在复核所选安装包…") else { return }
        showConfirmation = false; pendingPlan = nil; expression = 21
        let policy = MolePolicy(root: Assets.root.appendingPathComponent("Mole"), home: home), trash = TrashService(home: home)
        worker = Task {
            do {
                // Persist before touching files to establish a writable audit location.
                guard records.count + plan.entries.count <= 200 else { throw AlterError.refused("恢复记录已达 200 条。请先处理现有记录；不会丢弃恢复信息。") }
                try history.save(records)
                let allowed = try await Task.detached(priority: .utility) { try policy.review(plan.entries.map(\.path), cancellation: flag) }.value
                guard allowed.allSatisfy({ $0 }), !flag.isCancelled else { throw AlterError.refused("Mole 复核拒绝或操作取消；文件保持原位。") }
                for item in plan.entries {
                    if flag.isCancelled { break }
                    let record = try await Task.detached(priority: .utility) { try trash.move(item, planCreated: plan.created) }.value
                    records.insert(record, at: 0)
                    do { try history.save(records) }
                    catch { throw AlterError.refused("文件已移入废纸篓，但记录保存失败；已停止后续操作。请在废纸篓查看 \(record.trashName)。") }
                    installers.removeAll { $0.id == item.id }; selected.remove(item.id)
                }
                activity = "所选安装包已移入废纸篓，可从操作记录恢复。"; expression = 22
            } catch { errorMessage = error.localizedDescription; activity = "操作已停止，请查看说明。"; expression = 13 }
            busy = false; refreshCapacity()
        }
    }
    func restore(_ record: TrashRecord) {
        guard !busy else { return }
        let alert = NSAlert(); alert.messageText = "恢复这个安装包？"; alert.informativeText = record.originalPath + "\n不会覆盖同名文件。"
        alert.addButton(withTitle: "恢复"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try TrashService(home: home).restore(record)
            if let i = records.firstIndex(where: { $0.id == record.id }) { records[i].restored = true }
            try history.save(records); activity = "已恢复到原位置。"; expression = 8
        } catch { errorMessage = error.localizedDescription }
    }
    func reveal(_ path: String) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
}
