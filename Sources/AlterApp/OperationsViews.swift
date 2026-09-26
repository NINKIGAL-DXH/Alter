import SwiftUI
import AlterCore

struct CandidateList: View {
    @EnvironmentObject var model: AppModel
    var entries: [MoleCandidate] { model.candidates.filter { model.candidateQuery.isEmpty || $0.path.localizedCaseInsensitiveContains(model.candidateQuery) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("搜索预览项目", text: $model.candidateQuery).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                Spacer()
                Text("已选择 \(model.candidateSelection.count) 项").font(.system(size: 11)).foregroundStyle(.secondary)
                Button("逐项预览", action: model.previewCandidates).glassAction(prominent: true).disabled(model.busy || model.candidateSelection.isEmpty)
            }
            DisclosureGroup("扫描结果与跳过原因") { Text(model.discoveryNotes).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled) }
            if entries.isEmpty { Text(model.busy ? "Mole 正在检查…" : "没有候选项目。扫描范围、权限和跳过原因会显示在这里。").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 30) }
            else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            HStack(spacing: 12) {
                                Toggle("选择 " + URL(fileURLWithPath: entry.path).lastPathComponent, isOn: Binding(get: { model.candidateSelection.contains(entry.path) }, set: { if $0 { model.candidateSelection.insert(entry.path) } else { model.candidateSelection.remove(entry.path) } })).labelsHidden().toggleStyle(.checkbox).disabled(model.busy)
                                Image(systemName: entry.category == "application" ? "app" : entry.category == "artifact" ? "shippingbox" : "archivebox").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(URL(fileURLWithPath: entry.path).lastPathComponent).font(.system(size: 12, weight: .medium))
                                    Text(entry.path).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(entry.path)
                                    Text(entry.note).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Text(entry.bytes > 0 ? byteText(entry.bytes) : "预览时统计").font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
                                Button { model.reveal(entry.path) } label: { Image(systemName: "arrow.up.forward.square") }.buttonStyle(.plain).help("在 Finder 中显示")
                            }.padding(.vertical, 13)
                            Divider()
                        }
                    }
                }.frame(maxHeight: 470)
            }
        }.contentPanel()
    }
}

struct MoleCleanView: View {
    @EnvironmentObject var model: AppModel
    let feature: MoleFeature
    var title: String { feature == .clean ? "为重要的，腾出空间。" : feature == .purge ? "让项目，轻装前行。" : "安装之后，就可以放下。" }
    var subtitle: String { feature == .clean ? "Mole 完整用户清理规则 · 缓存、日志与开发工具残留" : feature == .purge ? "Mole 识别项目依赖与构建产物 · 源码保持原位" : "Mole 安装包识别 · 下载、桌面与其他受支持目录" }
    var body: some View {
        PageHeading(title: title, subtitle: subtitle)
        CompanionBanner(number: feature == .purge ? 6 : feature == .installer ? 4 : 10, title: "先看清，再决定。", subtitle: "每一项都由你选择。\n通过复核后，才移入废纸篓。", height: 240)
        HStack {
            Text("移入废纸篓可恢复，不会立即释放磁盘空间。").font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button { if feature == .purge { model.choosePurge() } else { model.discover(feature) } } label: { Label(feature == .purge ? "选择项目目录" : "开始只读扫描", systemImage: "viewfinder") }.glassAction(prominent: true).disabled(model.busy)
        }
        if feature == .purge {
            HStack(spacing: 12) {
                TextField("项目根目录，如 ~/Projects", text: $model.purgePathInput).textFieldStyle(.roundedBorder).disabled(model.busy)
                Button("扫描路径") { model.discover(.purge, path: (model.purgePathInput as NSString).expandingTildeInPath) }.glassAction().disabled(model.busy || model.purgePathInput.isEmpty)
            }
        }
        if model.candidateFeature == feature { CandidateList() }
        else { EmptyState(icon: feature == .purge ? "shippingbox" : "sparkles", title: "从一次只读扫描开始", detail: "候选项目默认不勾选。每次执行前都会检查文件身份和目录内容是否变化。") }
    }
}

struct ReviewedConfirmation: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { BrandImage(size: 48); VStack(alignment: .leading, spacing: 6) { Text("只处理这份清单。").font(.system(size: 23, weight: .semibold)); Text("可恢复地移入废纸篓 · 不永久删除").font(.system(size: 12)).foregroundStyle(.secondary) } }
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(model.reviewedPlan?.items ?? []) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(URL(fileURLWithPath: item.path).lastPathComponent).font(.system(size: 13, weight: .medium)); Spacer(); Text(byteText(item.bytes)).font(.system(size: 12)) }
                            Text(item.path).font(.system(size: 11)).textSelection(.enabled)
                            Text("\(item.count) 个对象 · " + item.note).font(.system(size: 10)).foregroundStyle(.secondary)
                        }; Divider()
                    }
                    ForEach(model.previewOmissions, id: \.self) { Text($0).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
            }.frame(maxHeight: 330)
            Text("目录会作为整体移动，包含上述数量的子项。执行前再次核对内容；发现变化、权限不足或跨卷就停止。系统维护、厂商卸载器和包管理脚本不会在此自动执行。").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            HStack { Button("返回修改") { model.showReviewed = false; model.reviewedPlan = nil }.glassAction(); Spacer(); Button("确认移入废纸篓", action: model.executeReviewed).glassAction(prominent: true) }
        }.padding(28).frame(width: 640)
    }
}

struct OptimizeView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        PageHeading(title: "让 Mac，回到好状态。", subtitle: "Mole 系统维护 · 一次检查一项，一次确认一项")
        CompanionBanner(number: 20, title: "有需要，再做改变。", subtitle: "维护可能重建缓存、修改偏好或数据库。\n先看具体影响，再决定是否执行。", height: 210)
        Text("按症状选择维护：搜索异常、图标异常、网络异常各有对应检查。macOS 会自动管理内存与多数缓存；定期清空内存或重建全部缓存不保证提速。").font(.system(size: 12)).foregroundStyle(.secondary).contentPanel()
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.optimizeTasks) { task in
                HStack(spacing: 16) {
                    Image(systemName: "wrench.and.screwdriver").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) { Text(task.alterTitle).font(.system(size: 13, weight: .medium)); Text(task.guidance.when).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3) }
                    Spacer(); Button("检查与预览") { model.previewOptimize(task) }.glassAction().disabled(model.busy)
                }.padding(.vertical, 8)
                Divider()
            }
            if model.optimizeTasks.isEmpty { Button("读取 Mole 维护目录", action: model.loadOptimize).glassAction().disabled(model.busy) }
        }.contentPanel()
        DisclosureGroup("最近一次维护结果") { Text(model.optimizeOutput).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12) }.contentPanel()
        Text("管理员任务在终端中由你授权；不在后台获取权限。显示 skipped / unavailable 的任务没有执行，不算成功。").font(.system(size: 11)).foregroundStyle(.secondary)
    }
}
struct OptimizeConfirmation: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text(model.optimizePreview?.task.alterTitle ?? "单项维护").font(.system(size: 23, weight: .semibold))
            Text(model.optimizePreview?.task.detail ?? "").font(.system(size: 13)).lineSpacing(4)
            if let task = model.optimizePreview?.task { OptimizeAdvice(task: task) }
            Text("Mole 预检结果：" + (model.optimizePreview?.outcome ?? "未知")).font(.system(size: 11)).foregroundStyle(.secondary)
            ScrollView { Text(model.optimizePreview?.output ?? "").font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 220).contentPanel()
            Text("此操作可能更改设置、重启服务、移除历史记录或重建数据库，具体范围以上方任务说明为准。它不是移入废纸篓，Alter 不提供一键恢复；执行途中停止可能已产生部分更改。请先保存工作。").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            HStack { Button("取消") { model.showOptimize = false; model.optimizePreview = nil }.glassAction(); Spacer(); Button("在终端授权此项", action: model.authorizeOptimizeInTerminal).glassAction(); Button("确认执行此项", action: model.executeOptimize).glassAction(prominent: true) }
            Text("“确认执行”仅使用当前用户权限；需要管理员权限的部分会跳过。").font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(28).frame(width: 680)
    }
}

struct SystemSnapshot {
    let cpu: Double, memory: Double, usedMemory: Int64, totalMemory: Int64, pressure: String, hardware: String, uptime: String
    let rows: [(String, String)]
    let raw: String
    init(data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AlterError.refused("系统状态格式无效。") }
        let c = json["cpu"] as? [String: Any] ?? [:], m = json["memory"] as? [String: Any] ?? [:], hw = json["hardware"] as? [String: Any] ?? [:]
        cpu = (c["usage"] as? NSNumber)?.doubleValue ?? 0; memory = (m["used_percent"] as? NSNumber)?.doubleValue ?? 0
        usedMemory = (m["used"] as? NSNumber)?.int64Value ?? 0; totalMemory = (m["total"] as? NSNumber)?.int64Value ?? 0
        pressure = (m["pressure"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "未提供"; hardware = hw["model"] as? String ?? "Mac"; uptime = json["uptime"] as? String ?? "未知"
        var output: [(String, String)] = []
        for disk in json["disks"] as? [[String: Any]] ?? [] { output.append((disk["mount"] as? String ?? "磁盘", byteText((disk["used"] as? NSNumber)?.int64Value ?? 0) + " / " + byteText((disk["total"] as? NSNumber)?.int64Value ?? 0))) }
        for net in json["network"] as? [[String: Any]] ?? [] { output.append((net["name"] as? String ?? "网络", String(format: "↓ %.2f MB/s  ↑ %.2f MB/s", (net["rx_rate_mbs"] as? NSNumber)?.doubleValue ?? 0, (net["tx_rate_mbs"] as? NSNumber)?.doubleValue ?? 0))) }
        for battery in json["batteries"] as? [[String: Any]] ?? [] { output.append(("电池", "\(battery["percent"] ?? "未知")% · \(battery["status"] ?? "")")) }
        for p in (json["top_processes"] as? [[String: Any]] ?? []).prefix(20) { output.append((p["name"] as? String ?? "进程", String(format: "CPU %.1f%% · ", (p["cpu"] as? NSNumber)?.doubleValue ?? 0) + byteText((p["memory_bytes"] as? NSNumber)?.int64Value ?? 0))) }
        rows = output
        raw = String(decoding: try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self)
    }
}
extension AppModel {
    func refreshStatus() {
        guard let flag = begin("Mole 正在读取系统状态…") else { return }
        let reader = MoleReader(resources: Assets.root)
        worker = Task {
            do { let data = try await Task.detached(priority: .utility) { try reader.status(cancellation: flag) }.value; systemStatus = try SystemSnapshot(data: data); statusDate = Date(); activity = "系统状态已更新。" }
            catch { statusLive = false; errorMessage = error.localizedDescription }
            busy = false
        }
    }
}
struct SystemStatusView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        PageHeading(title: "此刻的 Mac，尽在眼前。", subtitle: "CPU、内存、磁盘、网络与进程 · Mole 实际采样")
        HStack { Toggle("自动刷新（10 秒）", isOn: $model.statusLive).toggleStyle(.switch).font(.system(size: 12)); Spacer(); Button("刷新状态", action: model.refreshStatus).glassAction(prominent: true).disabled(model.busy) }
        if let status = model.systemStatus {
            HStack(spacing: 18) { metric("CPU", value: status.cpu, detail: status.hardware); metric("内存", value: status.memory, detail: byteText(status.usedMemory) + " / " + byteText(status.totalMemory)) }
            Text("内存压力：\(status.pressure) · 已运行 \(status.uptime) · 更新于 \(model.statusDate?.formatted() ?? "")").font(.system(size: 11)).foregroundStyle(.secondary)
            VStack(spacing: 0) { ForEach(Array(status.rows.enumerated()), id: \.offset) { _, row in HStack { Text(row.0); Spacer(); Text(row.1).foregroundStyle(.secondary) }.font(.system(size: 12)).padding(.vertical, 11); Divider() } }.contentPanel()
            DisclosureGroup("完整 Mole 状态（GPU、温度、风扇、电池与传感器等）") { ScrollView { Text(status.raw).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 360) }.contentPanel()
        } else { CompanionBanner(number: 8, title: "状态好，做事也轻快。", subtitle: "点击刷新，查看真实系统状态。\n未采样前，不显示模拟数值。", height: 250) }
        Text("硬件或权限不提供的数据以 Mole 原始结果为准；单次采样的网络速率可能尚未积累足够样本。").font(.system(size: 11)).foregroundStyle(.secondary)
        Color.clear.frame(height: 0).task(id: model.statusLive) {
            guard model.statusLive else { return }
            while !Task.isCancelled && model.statusLive && model.page == .status {
                if !model.busy { model.refreshStatus() }
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
            }
        }.onDisappear { model.statusLive = false }
    }
    func metric(_ title: String, value: Double, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 14) { Text(title).font(.system(size: 13, weight: .medium)); Text(String(format: "%.1f%%", value)).font(.system(size: 38, weight: .light, design: .rounded)); ProgressView(value: max(0, min(100, value)), total: 100); Text(detail).font(.system(size: 11)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).contentPanel()
    }
}

extension OptimizeTask {
    var alterTitle: String {
        let titles: [String: String] = [
            "system_maintenance": "DNS 与 Spotlight 检查",
            "cache_refresh": "Finder 缓存刷新",
            "saved_state_cleanup": "旧应用状态清理",
            "fix_broken_configs": "损坏配置修复",
            "network_optimization": "网络缓存刷新",
            "sqlite_vacuum": "数据库压缩",
            "launch_services_rebuild": "打开方式与文件关联修复",
            "prevent_network_dsstore": "Finder 网络卷偏好",
            "legacy_overrides_audit": "旧优化设置审计",
            "network_stack_optimize": "路由与 ARP 刷新",
            "disk_permissions_repair": "用户目录权限修复",
            "spotlight_index_optimize": "Spotlight 索引优化",
            "spotlight_orphan_rules_cleanup": "失效搜索规则清理",
            "periodic_maintenance": "系统周期维护",
            "shared_file_list_repair": "收藏与最近文稿修复",
            "disk_verify": "磁盘完整性检查（默认关闭）",
            "login_items_audit": "登录项审计",
            "quarantine_cleanup": "下载历史记录清理",
            "launch_agents_cleanup": "失效后台启动项清理",
            "notification_cleanup": "旧通知记录清理",
            "coreduet_cleanup": "旧使用记录清理"
        ]
        return titles[id] ?? title
    }
}
