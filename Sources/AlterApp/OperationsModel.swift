import SwiftUI
import AppKit
import AlterCore

extension AppModel {
    var operations: MoleOperations { MoleOperations(resources: Assets.root) }
    func previewLensItem(_ entry: DiskEntry) {
        guard !busy else { return }
        duplicateReviewGroups = []
        candidateFeature = .clean; uninstallTarget = nil; discoveryRoot = nil
        candidates = [MoleCandidate(category: "file", path: entry.path, bytes: entry.size, note: "你在空间透镜中选择的项目")]
        candidateSelection = [entry.path]; discoveryNotes = "来自空间透镜的手动选择。"; page = .clean
        previewCandidates()
    }
    func choosePurge() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "选择项目根目录。Mole 会识别依赖与构建产物，源代码不列入整理项目。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        discover(.purge, path: url.resolvingSymlinksInPath().path)
    }
    func discover(_ feature: MoleFeature, path: String? = nil) {
        guard let flag = begin("Mole 正在生成只读预览…") else { return }
        duplicateReviewGroups = []
        candidateFeature = feature; candidateSelection = []; candidates = []; candidateQuery = ""; uninstallTarget = feature == .uninstall ? path : nil
        page = feature == .clean ? .clean : feature == .purge ? .purge : feature == .installer ? .installer : .apps
        discoveryRoot = path; discoveryNotes = "正在扫描，尚未修改文件。"; let ops = operations
        worker = Task {
            do {
                let result = try await Task.detached(priority: .utility) { try ops.discover(feature, path: path, cancellation: flag) }.value
                candidates = result.candidates
                discoveryNotes = "Mole 找到 \(candidates.count) 个候选项目。" + result.notices.joined(separator: "\n")
                activity = "只读预览完成，尚未选择或修改任何文件。"; expression = 10
            } catch { discoveryNotes = error.localizedDescription; errorMessage = error.localizedDescription }
            busy = false
        }
    }
    func previewCandidates() {
        let chosen = candidates.filter { candidateSelection.contains($0.path) }
        guard !chosen.isEmpty, chosen.count <= 64 else { errorMessage = "每批请选择 1–64 个项目。"; return }
        guard let flag = begin("正在复核所选项目、目录内容与 Mole 保护规则…") else { return }
        let ops = operations, home = self.home
        previewOmissions = []; let app = uninstallTarget
        worker = Task {
            do {
                if let app, isRunning(app) { throw AlterError.refused("请先退出这个应用，再预览卸载。Alter 不会强制结束用户进程。") }
                let result = try await Task.detached(priority: .utility) { () -> ([ReviewedItem], [String]) in
                    let allowed = try ops.review(chosen.map(\.path), cancellation: flag)
                    var accepted: [ReviewedItem] = [], omitted: [String] = []
                    for (candidate, yes) in zip(chosen, allowed) {
                        if flag.isCancelled { throw AlterError.refused("预览已取消。") }
                        guard yes else { omitted.append("Mole 保留：" + candidate.path); continue }
                        do { accepted.append(try ReviewedRemoval.snapshot(candidate, home: home, cancellation: flag)) }
                        catch { omitted.append(error.localizedDescription) }
                    }
                    return (accepted, omitted)
                }.value
                previewOmissions = result.1
                reviewedPlan = try ReviewedPlan(items: result.0); showReviewed = true; expression = 20
                activity = "请确认这份具体清单；未通过检查的项目已列出原因。"
            } catch { errorMessage = error.localizedDescription + (previewOmissions.isEmpty ? "" : "\n" + previewOmissions.joined(separator: "\n")) }
            busy = false
        }
    }
    func executeReviewed() {
        guard let plan = reviewedPlan, let flag = begin("正在逐项复核并移入废纸篓…") else { return }
        showReviewed = false; reviewedPlan = nil
        let ops = operations, home = self.home, app = uninstallTarget, root = discoveryRoot, feature = candidateFeature, duplicates = duplicateReviewGroups
        worker = Task {
            var moved = 0
            do {
                guard records.count + plan.items.count <= 200 else { throw AlterError.refused("恢复记录已满。请先处理现有记录，Alter 不会覆盖历史记录。") }
                try history.save(records)
                if !duplicates.isEmpty {
                    try await Task.detached(priority:.utility) { try DuplicateFinder.revalidate(duplicates, selected:Set(plan.items.map(\.path)), cancellation:flag) }.value
                }
                // Refresh Mole's complete uninstall discovery, including surviving siblings.
                if let app {
                    guard !isRunning(app) else { throw AlterError.refused("应用正在运行，请先退出。") }
                    let fresh = try await Task.detached(priority: .utility) { try ops.discover(.uninstall, path: app, cancellation: flag) }.value
                    let paths = Set(fresh.candidates.map(\.path))
                    guard plan.items.allSatisfy({ paths.contains($0.path) }) else { throw AlterError.refused("应用关联关系已变化，请重新预览。") }
                }
                if feature == .purge, let root {
                    let fresh = try await Task.detached(priority: .utility) { try ops.discover(.purge, path: root, cancellation: flag) }.value
                    let paths = Set(fresh.candidates.map(\.path))
                    guard plan.items.allSatisfy({ paths.contains($0.path) }) else { throw AlterError.refused("项目产物规则或项目结构已变化，请重新预览。") }
                }
                let allowed = try await Task.detached(priority: .utility) { try ops.review(plan.items.map(\.path), cancellation: flag) }.value
                guard allowed.allSatisfy({ $0 }) else { throw AlterError.refused("Mole 保护规则已变化，请重新预览。") }
                for item in plan.items {
                    if flag.isCancelled { break }
                    if let app, isRunning(app) { throw AlterError.refused("应用重新启动，已停止后续移动。") }
                    let record = try await Task.detached(priority: .utility) { try ReviewedRemoval.move(item, home: home, created: plan.created, cancellation: flag) }.value
                    records.insert(record, at: 0); moved += 1
                    try history.save(records)
                    candidates.removeAll { $0.path == item.path }; candidateSelection.remove(item.path)
                }
                activity = "已将 \(moved) / \(plan.items.count) 项移入废纸篓，可在操作记录恢复。"; expression = 22
            } catch { errorMessage = "已移动 \(moved) 项；其余停止。\n" + error.localizedDescription; activity = "操作已停止，请查看结果。" }
            busy = false; indexStale = true; refreshCapacity()
        }
    }
    func isRunning(_ app: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { running in
            running.bundleURL?.resolvingSymlinksInPath().path == app || running.executableURL?.path.hasPrefix(app + "/") == true
        }
    }
    func loadOptimize() {
        guard optimizeTasks.isEmpty, let flag = begin("正在读取 Mole 维护目录…") else { return }
        let ops = operations
        worker = Task {
            do { optimizeTasks = try await Task.detached(priority: .utility) { try ops.optimizeTasks(cancellation: flag) }.value }
            catch { errorMessage = error.localizedDescription }
            busy = false; activity = "维护项目按需预览，每次只确认一项。"
        }
    }
    func previewOptimize(_ task: OptimizeTask) {
        guard let flag = begin("正在只读检查：" + task.title) else { return }
        let ops = operations
        worker = Task {
            do { optimizePreview = try await Task.detached(priority: .utility) { try ops.preview(task, cancellation: flag) }.value; showOptimize = true }
            catch { errorMessage = error.localizedDescription }
            busy = false; activity = "维护检查结束。"
        }
    }
    func executeOptimize() {
        guard let preview = optimizePreview, let flag = begin("正在执行已确认的单项维护：" + preview.task.title) else { return }
        showOptimize = false; let ops = operations
        worker = Task {
            do { optimizeOutput = try await Task.detached(priority: .utility) { try ops.execute(preview, cancellation: flag) }.value; activity = "维护任务已返回，请查看实际结果；跳过不代表完成。" }
            catch { optimizeOutput = error.localizedDescription; errorMessage = error.localizedDescription }
            optimizePreview = nil; busy = false
        }
    }
    func authorizeOptimizeInTerminal() {
        guard let preview = optimizePreview, Date().timeIntervalSince(preview.created) < 300 else { errorMessage = "预览已过期。"; return }
        do {
            try operations.verify()
            let folder = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("alter-authorize-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
            let launcher = folder.appendingPathComponent("Alter-maintenance.command")
            let executable = Bundle.main.executableURL!.path
            let body = "#!/bin/bash\nset -euo pipefail\nprintf '%s\\n' " + quote("Alter · 单项管理员维护\n" + preview.task.title + "\n" + preview.task.detail + "\n此任务可能修改系统设置或数据库，不能一键撤销。授权只用于当前维护项。") + "\n/usr/bin/sudo -v\nexec " + quote(executable) + " --authorized-maintenance " + quote(preview.task.id) + " " + String(Int(preview.created.timeIntervalSince1970) + 300) + "\n"
            try body.write(to: launcher, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: launcher.path)
            NSWorkspace.shared.open(launcher)
            showOptimize = false; activity = "已交给终端进行单项授权；结果显示在终端中，不记为已完成。"
        } catch { errorMessage = error.localizedDescription }
    }
}
