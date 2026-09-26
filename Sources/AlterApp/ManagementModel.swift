import SwiftUI
import AppKit
import AlterCore

enum FileCollection: String, CaseIterable { case large = "大文件", old = "旧文件", duplicates = "重复文件" }
extension AppModel {
    func checkBrewUpdates() {
        guard let flag = begin("正在检查 Homebrew 更新…") else { return }
        worker = Task {
            do { brewUpdates = try await Task.detached(priority:.utility) { try BrewUpdates.check(cancellation:flag) }.value; brewNote = "Homebrew 当前目录报告 \(brewUpdates.count) 项更新；不会批量更新或清理旧包。" }
            catch { brewNote=error.localizedDescription }; busy=false
        }
    }
    func previewBrewUpdate(_ update: BrewUpdate) {
        guard let flag = begin("正在检查单个应用的更新动作…") else { return }
        worker = Task {
            do {
                let plan = try await Task.detached(priority:.utility) { try BrewUpdates.preview(update,cancellation:flag) }.value
                guard !plan.appPaths.contains(where: isRunning) else { throw AlterError.refused("请先退出将要更新的应用。") }
                let alert = NSAlert(); alert.messageText="更新 " + update.token + "？"
                alert.informativeText="\(update.installed) → \(update.available)\n" + plan.appPaths.joined(separator:"\n") + "\n将下载并替换上述应用包，由 Homebrew 校验下载。不清理其他软件、不自动获取管理员权限。更新可能不可回退；请先保存工作。"
                alert.addButton(withTitle:"更新此应用"); alert.addButton(withTitle:"取消")
                guard alert.runModal() == .alertFirstButtonReturn, !flag.isCancelled else { busy=false; return }
                guard !plan.appPaths.contains(where:isRunning) else { throw AlterError.refused("应用已重新启动，请退出后重试。") }
                brewNote = try await Task.detached(priority:.utility) { try BrewUpdates.execute(plan,cancellation:flag) }.value
                activity="Homebrew 已核实该项不再报告更新。"; managedApps=AppInventory.read(home:home)
            } catch { errorMessage=error.localizedDescription }; busy=false
        }
    }
    func readAppInventory() {
        let home = self.home
        Task { managedApps = await Task.detached(priority: .utility) { AppInventory.read(home:home) }.value }
    }
    func checkAppUpdate(_ app: ManagedApp) {
        guard begin("正在读取应用的更新订阅…") != nil else { return }
        worker = Task {
            do { appUpdate = try await AppUpdates.check(app); activity = "更新来源已检查，未安装软件。" }
            catch { errorMessage = error.localizedDescription }; busy = false
        }
    }
    func showAppUpdater(_ app: ManagedApp) {
        if app.appStore { NSWorkspace.shared.open(URL(string:"macappstore://showUpdatesPage")!) }
        else { NSWorkspace.shared.open(URL(fileURLWithPath:app.path)) }
    }
    func scanLeftovers() {
        guard begin("正在查找未匹配到已安装应用的配置…") != nil else { return }; let home = self.home
        worker = Task {
            do {
                candidates = try await Task.detached(priority:.utility) { try AppInventory.leftovers(home:home,apps:AppInventory.read(home:home)) }.value
                candidateSelection=[]; candidateFeature = .clean; uninstallTarget=nil; discoveryRoot=nil
                discoveryNotes="这些是疑似残留，可能属于其他位置的应用或共享组件。没有自动选择任何项目。目录实际内容与大小将在预览中复核。"
            } catch { errorMessage=error.localizedDescription }; busy=false
        }
    }
    func loadFiles(next: Bool = false) {
        guard let index = diskIndex else { errorMessage = "请先在空间透镜中选择目录，建立可复用的索引。"; return }
        guard let flag = begin("正在读取文件索引…") else { return }
        let mode = fileCollection, cursor = next ? managedFiles.last?.path ?? "" : "", days = oldFileDays, threshold = largeFileMB
        worker = Task {
            do {
                if mode == .duplicates {
                    let report = try await Task.detached(priority:.utility) { try DuplicateFinder.find(in:index,cancellation:flag) }.value
                    duplicateGroups = report.groups; managedFiles = []; fileSelection = []
                    managementNote = "完整哈希检查 \(report.checked) 项，跳过 \(report.skipped) 项；\(report.groups.count) 组内容相同的文件。每组至少保留一份。" + report.notes.joined(separator:"\n")
                } else {
                    let files = try await Task.detached(priority:.utility) { try index.files(minimumSize: mode == .large ? Int64(threshold) * 1_048_576 : 0,olderThan:mode == .old ? Int64(Date().addingTimeInterval(-Double(days)*86400).timeIntervalSince1970) : Int64.max,after:cursor) }.value
                    managedFiles = files; fileSelection = []; fileCanNext = files.count == 500
                    managementNote = "索引范围：\(index.root) · 本页 \(files.count) 项 · 按路径分页。旧文件按修改时间判断，不代表无用。"
                }
                activity = "文件列表已更新。"
            } catch { errorMessage = error.localizedDescription }
            busy = false
        }
    }
    func previewManagedFiles() {
        let files = fileCollection == .duplicates ? duplicateGroups.flatMap(\.files) : managedFiles
        if fileCollection == .duplicates, duplicateGroups.contains(where: { $0.files.allSatisfy { fileSelection.contains($0.path) } }) { errorMessage = "重复文件每组至少保留一份，请取消其中一个选择。"; return }
        duplicateReviewGroups = fileCollection == .duplicates ? duplicateGroups : []
        candidates = files.filter { fileSelection.contains($0.path) }.map { MoleCandidate(category:"file",path:$0.path,bytes:$0.size,note:fileCollection.rawValue + " · 手动选择") }
        candidateSelection = Set(candidates.map(\.path)); candidateFeature = .clean; uninstallTarget = nil; discoveryRoot = nil
        previewCandidates()
    }
    func addProtection(_ path: String? = nil) {
        var chosen = path
        if chosen == nil {
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.showsHiddenFiles = true; panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK else { return }; chosen = panel.url?.path
        }
        guard let chosen else { return }
        do { let store = ProtectionStore(home:home); try store.save(try store.load() + [try FileSafety.physicalReadPath(chosen)]); protectedPaths = try store.load(); activity = "已加入保护名单，预览和执行都会重新检查。" }
        catch { errorMessage = error.localizedDescription }
    }
    func removeProtection(_ path: String) {
        let alert = NSAlert(); alert.messageText = "取消保护此路径？"; alert.informativeText = path + "\n取消后可参与清理预览；不会自动清理。"; alert.addButton(withTitle:"取消保护"); alert.addButton(withTitle:"保留保护")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { let store = ProtectionStore(home:home); try store.save(try store.load().filter { $0 != path }); protectedPaths = try store.load() } catch { errorMessage = error.localizedDescription }
    }
    func readProtection() { do { protectedPaths = try ProtectionStore(home:home).load() } catch { errorMessage = error.localizedDescription } }
    func scanStartup() {
        guard let flag = begin("正在检查登录与后台启动项…") else { return }; let home = self.home
        worker = Task {
            do { startupItems = try await Task.detached(priority:.utility) { try StartupManager.scan(home:home,cancellation:flag) }.value; activity = "启动项已读取。" }
            catch { errorMessage = error.localizedDescription }; busy = false
        }
    }
    func changeStartup(_ item: StartupItem) {
        guard !busy, let disabled = item.disabled else { return }
        let plan = StartupPlan(item:item,disable:!disabled)
        let alert = NSAlert(); alert.messageText = disabled ? "恢复此用户启动项？" : "停用此用户启动项？"
        alert.informativeText = item.label + "\n" + item.path + "\n" + item.program + "\n仅修改当前用户的 launchd 启动状态，不删除配置、不强制结束进程。已运行的服务可能持续至退出登录。可随时重新启用。"
        alert.addButton(withTitle:disabled ? "启用" : "停用"); alert.addButton(withTitle:"取消")
        guard alert.runModal() == .alertFirstButtonReturn, let flag = begin("正在修改已确认的启动项…") else { return }; let home = self.home
        worker = Task {
            do { try await Task.detached(priority:.utility) { try StartupManager.apply(plan,home:home,cancellation:flag) }.value; activity = "启动状态已核实。可通过相反操作恢复。" }
            catch { errorMessage = error.localizedDescription }; busy = false; scanStartup()
        }
    }
    func auditProtection() {
        guard let flag = begin("正在读取系统防护状态…") else { return }
        worker = Task { securityFindings = await Task.detached(priority:.utility) { SystemAudit.protections(cancellation:flag) }.value; securityDate = Date(); busy = false; activity = "系统防护检查结束；没有修改系统设置。" }
    }
    func auditSignature(_ path: String? = nil) {
        var chosen = path
        if chosen == nil { let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; guard panel.runModal() == .OK else { return }; chosen = panel.url?.path }
        guard let chosen, begin("正在校验应用签名…") != nil else { return }
        worker = Task {
            do { signatureFinding = try await Task.detached(priority:.utility) { try SystemAudit.signature(chosen) }.value }
            catch { errorMessage = error.localizedDescription }; busy = false
        }
    }
}
