import SwiftUI
import AlterCore

private let wine = Color(red: 0.64, green: 0.23, blue: 0.35)

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) { BrandImage(size: 44); VStack(alignment: .leading, spacing: 0) { Text("Alter").font(.system(size: 31, weight: .medium, design: .serif)); Text("SPACE TO BEGIN").font(.system(size: 8, weight: .medium)).tracking(2.5).foregroundStyle(.secondary) } }.padding(.horizontal, 16).padding(.top, 22)
                List(AppPage.allCases, selection: $model.page) { page in Label(page.rawValue, systemImage: page.icon).tag(page).padding(.vertical, 7) }.listStyle(.sidebar).scrollContentBackground(.hidden)
                if model.companionVisible {
                    Button { model.page = .companion } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            ExpressionImage(number: model.expression, pixels: 420).frame(height: 115).clipped().clipShape(RoundedRectangle(cornerRadius: 13))
                            Text(model.currentExpression?.quote ?? "一起轻装前行。").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4).multilineTextAlignment(.leading)
                            Text("ALTER · \(model.expression) / 23").font(.system(size: 9)).tracking(1.2).foregroundStyle(wine)
                        }
                    }.buttonStyle(.plain).padding(.horizontal, 17)
                }
                Label("你的文件，由你决定", systemImage: "checkmark.shield").font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 17).padding(.bottom, 15)
            }.navigationSplitViewColumnWidth(min: 195, ideal: 215, max: 245)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch model.page {
                    case .files: FileManagementView()
                    case .startup: StartupView()
                    case .security: SecurityView()
                    case .protection: ProtectionView()
                    case .overview: OverviewView()
                    case .clean: MoleCleanView(feature: .clean)
                    case .purge: MoleCleanView(feature: .purge)
                    case .installer: MoleCleanView(feature: .installer)
                    case .optimize: OptimizeView()
                    case .status: SystemStatusView()
                    case .storage: SpaceLensView()
                    case .apps: ApplicationsView()
                    case .companion: CompanionView()
                    case .history: HistoryView()
                    case .settings: SettingsView()
                    }
                    HStack { Label("本地处理 · 写操作需确认", systemImage: "lock.shield"); Spacer(); Text("Mole V1.55.0 · Alter " + (Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "开发版")) }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 8)
                }.padding(30).frame(maxWidth: 1150).frame(maxWidth: .infinity)
            }

            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 10) {
                    if model.busy { ProgressView().controlSize(.small) } else { Image(systemName: "checkmark.shield").foregroundStyle(.secondary) }
                    Text(model.activity).font(.system(size: 11)).lineLimit(2)
                    Spacer()
                    if model.busy { Button("停止", action: model.cancel).glassAction() }
                }.padding(.horizontal, 24).padding(.vertical, 12).panelSurface(radius: 0)
            }
            .toolbar {
                ToolbarItem(placement: .navigation) { Text(model.page.rawValue).font(.system(size: 12)).foregroundStyle(.secondary) }
                ToolbarItem(placement: .primaryAction) { Button { model.appearance = model.appearance == 2 ? 1 : 2; model.expression = model.appearance == 2 ? 12 : 14 } label: { Image(systemName: model.appearance == 2 ? "sun.max" : "moon") }.help("切换深浅外观") }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background { AlterBackdrop() }
        .sheet(isPresented: $model.showReviewed) { ReviewedConfirmation() }
        .sheet(isPresented: $model.showOptimize) { OptimizeConfirmation() }
        .sheet(isPresented: $model.showConfirmation) { ConfirmationView() }
        .alert("Alter 已保留安全边界", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("知道了") { model.errorMessage = nil } } message: { Text(model.errorMessage ?? "") }
    }
}
struct PageHeading: View {
    let title: String, subtitle: String
    var body: some View { VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 27, weight: .semibold)); Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary) } }
}
struct CompanionBanner: View {
    @EnvironmentObject var model: AppModel
    var number: Int? = nil
    let title: String
    let subtitle: String
    var height: CGFloat = 240
    var body: some View {
        HStack(spacing: 0) {
            if model.companionVisible {
                GeometryReader { g in ExpressionImage(number: number ?? model.expression).frame(width: g.size.width, height: height).clipped() }.frame(width: 350, height: height)
            }
            VStack(alignment: .leading, spacing: 16) {
                Text("ALTER / BY YOUR SIDE").font(.system(size: 9, weight: .medium)).tracking(2).foregroundStyle(Color(red: 0.83, green: 0.70, blue: 0.57))
                Text(title).font(.system(size: 24, weight: .medium)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 13)).lineSpacing(5).foregroundStyle(.white.opacity(0.75))
            }.padding(27).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity).frame(height: height).background(Color(red: 0.17, green: 0.14, blue: 0.21)).clipShape(RoundedRectangle(cornerRadius: 22))
    }
}
struct OverviewView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        PageHeading(title: "给 Mac，留一点余裕。", subtitle: "整理空间，也整理开始下一件事的心情。")
        ZStack(alignment: .leading) {
            if model.companionVisible { GeometryReader { g in ExpressionImage(number: model.heroExpression).frame(width: g.size.width * 0.60, height: 290).clipped().frame(maxWidth: .infinity, alignment: .trailing) } }
            LinearGradient(stops: [.init(color: Color(red: 0.17, green: 0.14, blue: 0.21), location: 0), .init(color: Color(red: 0.17, green: 0.14, blue: 0.21).opacity(0.80), location: 0.36), .init(color: .clear, location: 0.9)], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 16) {
                Text("A LITTLE LESS. A LITTLE LIGHTER.").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(Color(red: 0.81, green: 0.65, blue: 0.49))
                Text("把空间还给热爱。").font(.system(size: 31, weight: .medium)).foregroundStyle(.white)
                Text("先看清每一份占用，\n再决定哪些可以放下。").font(.system(size: 13)).lineSpacing(5).foregroundStyle(.white.opacity(0.7))
                Button(action: model.scanClean) { Label("开始只读扫描", systemImage: "viewfinder").padding(.horizontal, 8).padding(.vertical, 5) }.glassAction(prominent: true).disabled(model.busy)
            }.padding(34)
        }.frame(height: 290).background(Color(red: 0.17, green: 0.14, blue: 0.21)).clipShape(RoundedRectangle(cornerRadius: 22))
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Label("Macintosh HD", systemImage: "internaldrive").font(.system(size: 13, weight: .medium)); Spacer(); Button("空间详情") { model.page = .storage }.buttonStyle(.plain).foregroundStyle(wine).font(.system(size: 11)) }
                HStack(alignment: .firstTextBaseline) { Text(byteText(max(0, model.totalCapacity - model.freeCapacity))).font(.system(size: 30, weight: .medium, design: .rounded)); Text("/ \(byteText(model.totalCapacity))").font(.system(size: 12)).foregroundStyle(.secondary) }
                ProgressView(value: Double(max(0, model.totalCapacity - model.freeCapacity)), total: Double(max(1, model.totalCapacity))).tint(Color(red: 0.56, green: 0.48, blue: 0.62))
                Text("当前可用 \(byteText(model.freeCapacity)) · 系统实时容量").font(.system(size: 11)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).contentPanel()
            VStack(alignment: .leading, spacing: 13) {
                Text("逐项预览与确认").font(.system(size: 13, weight: .medium))
                Text("由你决定").font(.system(size: 30, weight: .medium, design: .rounded)).foregroundStyle(wine)
                Text("Mole 候选项目 · 不默认勾选").font(.system(size: 11)).foregroundStyle(.secondary)
                Button("查看整理项目  →") { model.page = .clean }.buttonStyle(.plain).foregroundStyle(wine).font(.system(size: 12))
            }.frame(maxWidth: .infinity, alignment: .leading).contentPanel()
        }
        Text("按你的方式整理").font(.system(size: 14, weight: .semibold))
        HStack(spacing: 14) {
            QuickTile(title: "检查清理项目", subtitle: "先预览，再移入废纸篓", icon: "shippingbox") { model.page = .clean }
            QuickTile(title: "找到大文件", subtitle: "只读分析你选择的目录", icon: "folder") { model.page = .storage }
            QuickTile(title: "查看应用占用", subtitle: "应用与关联项目逐项预览", icon: "square.stack.3d.up") { model.page = .apps }
        }
    }
}
struct QuickTile: View {
    let title: String, subtitle: String, icon: String
    let action: () -> Void
    var body: some View { Button(action: action) { HStack(spacing: 11) { Image(systemName: icon).font(.system(size: 22)).foregroundStyle(wine.opacity(0.75)); VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 12, weight: .medium)); Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary) }.padding(18).frame(maxWidth: .infinity).panelSurface(radius: 16) }.buttonStyle(.plain) }
}
struct CleanView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        PageHeading(title: "为重要的，腾出空间。", subtitle: "安装包先确认，缓存先了解。任何不确定的项目都保留。")
        CompanionBanner(title: model.busy ? "我会仔细看清楚。" : "先查看，再决定。", subtitle: model.currentExpression?.quote ?? "重要的东西，要好好留下。", height: 250)
        HStack { VStack(alignment: .leading, spacing: 5) { Text("旧安装包").font(.system(size: 16, weight: .semibold)); Text(model.scanSummary).font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); Button(action: model.scanClean) { Label("只读扫描", systemImage: "arrow.clockwise") }.glassAction().disabled(model.busy) }
        Text("范围仅限 Downloads 及下一层文件夹，Mole 保护检查通过后才可选择。移入废纸篓不会立即增加磁盘可用空间。").font(.system(size: 11)).foregroundStyle(.secondary)
        if model.installers.isEmpty { EmptyState(icon: "shippingbox", title: model.busy ? "正在检查…" : "还没有可整理的安装包", detail: "扫描后，只显示至少 30 天未变动的本地安装包。") }
        else {
            LazyVStack(spacing: 0) {
                ForEach(model.installers) { entry in
                    HStack(spacing: 13) {
                        Toggle(entry.name, isOn: Binding(get: { model.selected.contains(entry.id) }, set: { if $0 { model.selected.insert(entry.id); model.expression = 6 } else { model.selected.remove(entry.id) } })).labelsHidden().toggleStyle(.checkbox).disabled(!entry.canTrash || model.busy)
                        FileRow(entry: entry)
                        Button { model.reveal(entry.path) } label: { Image(systemName: "folder") }.buttonStyle(.plain).help("在 Finder 中查看")
                    }.padding(.vertical, 13)
                    Divider()
                }
            }.contentPanel()
        }
        HStack {
            VStack(alignment: .leading, spacing: 5) { Text("已选 \(model.selectedEntries.count) 项 · \(byteText(model.selectedBytes))").font(.system(size: 14, weight: .medium)); Text("单次最多 20 项 / 25 GB · 操作前再次复核").font(.system(size: 10)).foregroundStyle(.secondary) }
            Spacer()
            Button(action: model.confirmSelected) { Label("检查并移入废纸篓", systemImage: "trash").padding(.vertical, 4) }.glassAction(prominent: true).disabled(model.selectedEntries.isEmpty || model.busy)
        }
        if !model.caches.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text("缓存占用 · 只读观察").font(.system(size: 15, weight: .semibold)); Spacer(); Label("保留", systemImage: "lock").font(.system(size: 11)).foregroundStyle(.secondary) }
                Text("缓存名称不能证明可以删除。本版本不提供缓存删除入口。").font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach(model.caches.prefix(12)) { entry in FileRow(entry: entry); Divider() }
            }.contentPanel()
        }
    }
}
struct FileRow: View {
    let entry: ScanEntry
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.kind == .application ? "app.dashed" : entry.kind == .cache ? "archivebox" : "doc").font(.system(size: 23)).foregroundStyle(wine.opacity(0.7)).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) { Text(entry.name).font(.system(size: 12, weight: .medium)).lineLimit(1).help(entry.path); Text(entry.note).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2) }
            Spacer(minLength: 16)
            Text(byteText(entry.bytes)).font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
        }
    }
}
struct EmptyState: View {
    let icon: String, title: String, detail: String
    var body: some View { VStack(spacing: 13) { Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(wine.opacity(0.6)); Text(title).font(.system(size: 15, weight: .medium)); Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center) }.padding(40).frame(maxWidth: .infinity).panelSurface() }
}
struct ApplicationsView: View {
    @EnvironmentObject var model: AppModel

    var entries: [ScanEntry] { model.applications.filter { model.appQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(model.appQuery) } }
    var body: some View {
        PageHeading(title: "留下真正需要的。", subtitle: "Mole 应用识别与关联文件发现 · 卸载前逐项预览")
        Picker("应用功能", selection: $model.appTab) { Text("已安装").tag(0); Text("应用更新").tag(1); Text("疑似残留").tag(2) }.pickerStyle(.segmented)
        if model.appTab == 1 { AppUpdatesView() }
        else if model.appTab == 2 {
            Button("查找疑似残留", action: model.scanLeftovers).glassAction(prominent: true).disabled(model.busy)
            CandidateList()
        } else {
        CompanionBanner(number: 17, title: "每个工具，都有它的位置。", subtitle: "应用与关联数据，分开看清。\n需要厂商卸载器的应用会说明原因。", height: 230)
        HStack { TextField("搜索应用", text: $model.appQuery).textFieldStyle(.roundedBorder).frame(maxWidth: 260); Spacer(); Button(action: model.scanApps) { Label("读取应用", systemImage: "arrow.clockwise") }.glassAction().disabled(model.busy) }
        Text(model.appSummary).font(.system(size: 11)).foregroundStyle(.secondary)
        if entries.isEmpty { EmptyState(icon: "square.stack.3d.up", title: model.appQuery.isEmpty ? "尚无应用统计" : "没有匹配的应用", detail: "读取 /Applications 与用户 Applications，选择应用后检查关联项目。") }
        else { LazyVStack(spacing: 0) { ForEach(entries) { entry in HStack { FileRow(entry: entry); Button("签名") { model.auditSignature(entry.path); model.page = .security }.buttonStyle(.plain).font(.system(size: 11)); Button("卸载预览") { model.discover(.uninstall, path: entry.path); model.expression = 19 }.buttonStyle(.plain).foregroundStyle(wine).font(.system(size: 11)) }.padding(.vertical, 14); Divider() } }.contentPanel() }
        if model.candidateFeature == .uninstall, model.uninstallTarget != nil { CandidateList() }
        }
    }
}
struct CompanionView: View {
    @EnvironmentObject var model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        PageHeading(title: "每一种神情，都在身边。", subtitle: "23 张参考，23 个陪伴时刻。细微的变化，也认真保留。")
        VStack(spacing: 0) {
            ExpressionImage(number: model.expression, pixels: 1000, fit: .fit).frame(height: 350).frame(maxWidth: .infinity).panelSurface(radius: 0).clipped()
            HStack {
                VStack(alignment: .leading, spacing: 8) { Text(model.currentExpression?.name ?? "Alter").font(.system(size: 19, weight: .medium)); Text(model.currentExpression?.quote ?? "").font(.system(size: 12)).foregroundStyle(.secondary); Text("场景 / " + (model.currentExpression?.state ?? "")).font(.system(size: 10)).foregroundStyle(wine) }
                Spacer()
                Button { model.expressionsPlaying = false; model.expression = model.expression == 1 ? 23 : model.expression - 1 } label: { Image(systemName: "chevron.left") }.glassAction().accessibilityLabel("上一个表情")
                Button(model.expressionsPlaying ? "暂停" : "依次预览") { model.expressionsPlaying.toggle() }.glassAction().disabled(reduceMotion)
                Button { model.expressionsPlaying = false; model.expression = model.expression % 23 + 1 } label: { Image(systemName: "chevron.right") }.glassAction().accessibilityLabel("下一个表情")
            }.padding(23).panelSurface(radius: 0)
        }.clipShape(RoundedRectangle(cornerRadius: 20))
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
            ForEach(Assets.expressions) { ex in
                Button { model.expressionsPlaying = false; model.expression = ex.id } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        ExpressionImage(number: ex.id, pixels: 360).frame(height: 110).clipped()
                        Text(String(format: "%02d", ex.id) + "  " + ex.name).font(.system(size: 11, weight: .medium)).padding(.horizontal, 12)
                        Text(ex.state).font(.system(size: 9)).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 12)
                    }.panelSurface(radius: 0).clipShape(RoundedRectangle(cornerRadius: 12)).overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(model.expression == ex.id ? wine : .clear, lineWidth: 2) }
                }.buttonStyle(.plain)
            }
        }
        .task(id: model.expressionsPlaying) {
            guard model.expressionsPlaying else { return }
            while !Task.isCancelled && model.expressionsPlaying {
                do { try await Task.sleep(for: .seconds(2.5)) } catch { break }
                if Task.isCancelled { break }; model.expression = model.expression % 23 + 1
            }
        }.onDisappear { model.expressionsPlaying = false }
    }
}
struct HistoryView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        PageHeading(title: "每一次整理，都有迹可循。", subtitle: "只记录真实移动。可将文件与目录恢复到原位置。")
        if model.records.isEmpty { CompanionBanner(number: 23, title: "还没有需要回头看的事。", subtitle: "移入废纸篓后，操作记录会留在这里。\n不会覆盖已有的同名文件。", height: 255) }
        else {
            LazyVStack(spacing: 0) {
                ForEach(model.records) { record in
                    HStack {
                        Image(systemName: record.restored ? "arrow.uturn.backward.circle" : "trash").foregroundStyle(wine)
                        VStack(alignment: .leading, spacing: 5) { Text(URL(fileURLWithPath: record.originalPath).lastPathComponent).font(.system(size: 12, weight: .medium)); Text(record.date.formatted() + " · " + byteText(record.bytes)).font(.system(size: 10)).foregroundStyle(.secondary) }
                        Spacer()
                        if record.restored { Text("已恢复").font(.system(size: 11)).foregroundStyle(.secondary) }
                        else { Button("恢复到原位置") { model.restore(record) }.glassAction().disabled(model.busy) }
                    }.padding(.vertical, 17)
                    Divider()
                }
            }.contentPanel()
        }
        Label("废纸篓由你管理。Alter 不清空废纸篓，也不永久删除文件。", systemImage: "checkmark.shield").font(.system(size: 12)).foregroundStyle(.secondary)
    }
}
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        PageHeading(title: "你习惯的样子。", subtitle: "让 Alter 成为属于你的工作空间。")
        VStack(alignment: .leading, spacing: 22) {
            HStack { Label("外观", systemImage: "circle.lefthalf.filled"); Spacer(); Picker("外观", selection: $model.appearance) { Text("跟随系统").tag(0); Text("月白").tag(1); Text("夜色").tag(2) }.labelsHidden().pickerStyle(.segmented).frame(width: 250) }
            Divider()
            Toggle("角色陪伴", isOn: $model.companionVisible).toggleStyle(.switch)
            Divider()
            HStack { Text("首页视觉"); Spacer(); Picker("首页视觉", selection: $model.heroExpression) { Text("暮色日常").tag(1); Text("黑甲紫电").tag(9) }.labelsHidden().frame(width: 180) }
        }.font(.system(size: 13)).contentPanel()
        VStack(alignment: .leading, spacing: 16) {
            Text("安全与资源边界").font(.system(size: 16, weight: .semibold))
            Label("清理移入废纸篓；维护逐项确认；管理员授权在终端完成", systemImage: "lock.shield")
            Label("单个扫描任务；可取消；数量和时间均有上限", systemImage: "gauge.with.dots.needle.33percent")
            Label("图片缩略解码；缓存预算 20 MB；内存压力触发停止", systemImage: "memorychip")
            Label("遇到路径变化、权限不足或未知结果，一律跳过", systemImage: "hand.raised")
            Text("这些限制降低资源耗尽风险，并不构成任何环境下绝不会耗尽内存的保证。").font(.system(size: 10)).foregroundStyle(.secondary)
        }.font(.system(size: 12)).contentPanel()
        HStack(alignment: .top, spacing: 19) {
            BrandImage(size: 68)
            VStack(alignment: .leading, spacing: 9) {
                Text("Alter " + (Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "开发版")).font(.system(size: 21, weight: .medium, design: .serif))
                Text("Mole V1.55.0 内核 · 原生 SwiftUI 界面").font(.system(size: 12))
                Text("使用 tw93/Mole 的清理、卸载发现、维护、分析、状态、项目产物与安装包模块，GPL-3.0。Alter 为独立衍生项目，无官方背书；写操作经过预览适配，具体限制见 README。").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                HStack(spacing: 18) { Link("Mole 源项目", destination: URL(string: "https://github.com/tw93/Mole/tree/69ab325d4f05af0ea21aeeeae544046c9f04a76b")!); Link("Apple 材质指南", destination: URL(string: "https://developer.apple.com/design/human-interface-guidelines/materials")!); Button("许可证") { model.reveal(Assets.root.appendingPathComponent("Mole/LICENSE").path) }.buttonStyle(.plain) }.font(.system(size: 11)).foregroundStyle(wine)
                Text("角色图片由用户提供；角色与原作权利归原权利人，不属于 GPL 代码授权。").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.contentPanel()
    }
}
struct ConfirmationView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack { BrandImage(size: 45); VStack(alignment: .leading, spacing: 5) { Text("这些安装包，可以放下了吗？").font(.system(size: 20, weight: .semibold)); Text("仅移入废纸篓 · 不永久删除").font(.system(size: 11)).foregroundStyle(.secondary) } }
            ScrollView { VStack(alignment: .leading, spacing: 14) { ForEach(model.pendingPlan?.entries ?? []) { entry in VStack(alignment: .leading, spacing: 4) { HStack { Text(entry.name).font(.system(size: 12, weight: .medium)); Spacer(); Text(byteText(entry.bytes)).font(.system(size: 11)) }; Text(entry.path).font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled) }; Divider() } } }.frame(maxHeight: 280)
            Text("执行前会再次验证 Mole 保护规则、所有权、文件身份与时间。若有变化则停止，不会覆盖其他文件。移入废纸篓不会立即释放磁盘空间。").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            HStack { Button("再看看") { model.showConfirmation = false; model.pendingPlan = nil; model.expression = 3 }.glassAction(); Spacer(); Button("确认移入废纸篓", action: model.executeConfirmed).glassAction(prominent: true).keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 590)
    }
}
