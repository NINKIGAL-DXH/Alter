import SwiftUI
import AppKit
import AlterCore

enum AppPage: String, CaseIterable, Identifiable {
    case overview = "总览", clean = "智能清理", storage = "空间透镜", apps = "应用管理", purge = "项目产物", installer = "安装包", optimize = "系统维护", status = "系统状态", companion = "Alter 陪伴", history = "操作记录", settings = "设置"
    var id: String { rawValue }
    var icon: String { switch self { case .purge: "shippingbox"; case .installer: "archivebox"; case .optimize: "wrench.and.screwdriver"; case .status: "waveform.path.ecg"; case .overview: "square.grid.2x2"; case .clean: "sparkles"; case .storage: "internaldrive"; case .apps: "square.stack.3d.up"; case .companion: "moon.stars"; case .history: "clock.arrow.circlepath"; case .settings: "slider.horizontal.3" } }
    var expression: Int { switch self { case .purge: 6; case .installer: 4; case .optimize: 20; case .status: 8; case .overview: 1; case .clean: 4; case .storage: 15; case .apps: 17; case .companion: 2; case .history: 23; case .settings: 18 } }
}
@MainActor final class AppModel: ObservableObject {
    @Published var page: AppPage = .overview { didSet { expression = page.expression } }
    @Published var appQuery = ""
    @Published var candidates: [MoleCandidate] = []
    @Published var candidateFeature: MoleFeature = .clean
    @Published var candidateSelection: Set<String> = []
    @Published var candidateQuery = ""
    @Published var discoveryNotes = "尚未扫描。"
    @Published var reviewedPlan: ReviewedPlan?
    @Published var showReviewed = false
    @Published var previewOmissions: [String] = []
    @Published var discoveryRoot: String?
    @Published var uninstallTarget: String?
    @Published var optimizeTasks: [OptimizeTask] = []
    @Published var optimizePreview: OptimizePreview?
    @Published var showOptimize = false
    @Published var optimizeOutput = "尚未执行维护任务。"
    @Published var systemStatus: SystemSnapshot?
    @Published var statusLive = false
    @Published var statusDate: Date?

    @Published var expressionsPlaying = false
    @Published var expression = 1
    @Published var busy = false
    @Published var activity = "准备好了。先查看，再决定。"
    @Published var errorMessage: String?
    @Published var installers: [ScanEntry] = []
    @Published var caches: [ScanEntry] = []
    @Published var largeFiles: [ScanEntry] = []
    @Published var diskSnapshot: DiskSnapshot?
    @Published var lensBubbles: [LensBubble] = []
    @Published var lensHover: String?
    @Published var lensQuery = ""
    @Published var lensPathInput = "~"
    @Published var purgePathInput = ""
    @Published var lensRemainderOnly = false
    @Published var lensTrail: [String] = []
    @Published var lensPosition = -1
    @Published var lensStarted: Date?
    @Published var lensError: String?
    @Published var lensPage = 0
    var lensEntries: [DiskEntry] {
        let visible = Set(lensBubbles.filter { !$0.remainder }.map(\.id))
        return (diskSnapshot?.entries ?? []).filter {
            (!lensRemainderOnly || !visible.contains($0.path)) && (lensQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(lensQuery))
        }.sorted { $0.size == $1.size ? $0.path < $1.path : $0.size > $1.size }
    }
    var pagedLensEntries: [DiskEntry] { Array(lensEntries.dropFirst(lensPage * 100).prefix(100)) }

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
    var worker: Task<Void, Never>?
    private var pressure: DispatchSourceMemoryPressure?
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    var history: HistoryStore { HistoryStore(directory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Alter")) }
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
    func begin(_ message: String) -> CancellationFlag? {
        guard !busy, geteuid() != 0 else { if geteuid() == 0 { errorMessage = "Alter 拒绝以 root 身份运行。" }; return nil }
        busy = true; activity = message; cancellation = CancellationFlag(); return cancellation
    }
    func scanClean() { discover(.clean) }
    func analyzeFolder() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true; panel.treatsFilePackagesAsDirectories = true
        panel.message = "选择要查看空间分布的目录。分析只读；系统与隐藏目录也可浏览，访问权限由 macOS 决定。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        analyzePath(url.path)
    }
    func analyzePath(_ path: String, historyIndex: Int? = nil) {
        let path = (path as NSString).expandingTildeInPath
        guard path.hasPrefix("/") else { lensError = "请输入绝对路径或以 ~ 开头的路径。"; return }
        guard let flag = begin("Mole 正在统计目录大小，可以随时停止…") else { return }
        page = .storage; lensStarted = Date(); lensError = nil; lensHover = nil
        let reader = MoleReader(resources: Assets.root)
        worker = Task {
            do {
                let result = try await Task.detached(priority: .utility) { try reader.analyze(path, cancellation: flag) }.value
                guard !flag.isCancelled else { throw AlterError.refused("分析已取消。") }
                diskSnapshot = result; lensPathInput = result.path; lensBubbles = LensLayout.pack(result.entries)
                lensRemainderOnly = false; lensQuery = ""; lensPage = 0
                if let index = historyIndex { lensPosition = index }
                else if lensTrail.indices.contains(lensPosition), lensTrail[lensPosition] == result.path { }
                else {
                    lensTrail = Array(lensTrail.prefix(lensPosition + 1)); lensTrail.append(result.path)
                    if lensTrail.count > 64 { lensTrail.removeFirst() }
                    lensPosition = lensTrail.count - 1
                }
                storageSummary = "\(byteText(result.totalSize)) · \(result.entries.count) 个直接子项 · Mole 统计 \(result.totalFiles) 个文件"
                activity = "空间分析完成；结果可能不包含 macOS 隐私权限拒绝访问的内容。"; expression = 15
            } catch { lensError = error.localizedDescription; activity = "分析未完成，原有结果已保留。" }
            lensStarted = nil; busy = false
        }
    }
    func lensNavigate(_ offset: Int) {
        let target = lensPosition + offset
        guard lensTrail.indices.contains(target) else { return }
        analyzePath(lensTrail[target], historyIndex: target)
    }
    func lensOpen(_ entry: DiskEntry) {
        if entry.isDir { analyzePath(entry.path) } else { reveal(entry.path) }
    }
    func scanApps() {
        guard let flag = begin("Mole 正在统计已安装应用…") else { return }
        page = .apps
        let reader = MoleReader(resources: Assets.root), home = self.home
        worker = Task {
            do {
                let entries = try await Task.detached(priority: .utility) { () -> [ScanEntry] in
                    var entries: [ScanEntry] = []
                    for path in ["/Applications", home + "/Applications"] where FileManager.default.fileExists(atPath: path) {
                        let snapshot = try reader.analyze(path, cancellation: flag)
                        for item in snapshot.entries where item.name.lowercased().hasSuffix(".app") {
                            guard let info = try? FileSafety.metadata(item.path) else { continue }
                            entries.append(ScanEntry(path: item.path, kind: .application, bytes: item.size, identity: FileSafety.identity(info), note: "查看应用与关联项目"))
                        }
                    }
                    return entries.sorted { $0.bytes > $1.bytes }
                }.value
                applications = entries; appSummary = "已统计 \(entries.count) 个应用。选择应用后，由 Mole 检查关联文件。"
                activity = "应用统计完成。"
            } catch { errorMessage = error.localizedDescription }
            busy = false
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
                var movedCount = 0
                for item in plan.entries {
                    if flag.isCancelled { break }
                    let record = try await Task.detached(priority: .utility) { try trash.move(item, planCreated: plan.created) }.value
                    records.insert(record, at: 0)
                    movedCount += 1
                    do { try history.save(records) }
                    catch { throw AlterError.refused("文件已移入废纸篓，但记录保存失败；已停止后续操作。请在废纸篓查看 \(record.trashName)。") }
                    installers.removeAll { $0.id == item.id }; selected.remove(item.id)
                }
                activity = "已将 \(movedCount) / \(plan.entries.count) 项移入废纸篓，可从操作记录恢复。" + (flag.isCancelled ? "其余项目已停止处理。" : ""); expression = 22
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
