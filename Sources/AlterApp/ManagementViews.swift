import SwiftUI
import AlterCore

struct FileManagementView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        PageHeading(title:"把空间，还给重要的事。",subtitle:"大文件 · 旧文件 · 完整内容哈希查重")
        CompanionBanner(number:14,title:"每一份保留，都由你选择。",subtitle:"使用空间透镜中的目录索引。\n修改时间久远，不等于可以删除。",height:210)
        Picker("分类",selection:$model.fileCollection) { ForEach(FileCollection.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).onChange(of:model.fileCollection) { model.fileSelection = []; model.managedFiles = []; model.duplicateGroups = [] }
        HStack {
            if model.fileCollection == .large { Picker("大于",selection:$model.largeFileMB) { Text("100 MB").tag(100); Text("500 MB").tag(500); Text("1 GB").tag(1024) }.frame(width:190) }
            if model.fileCollection == .old { Picker("未修改",selection:$model.oldFileDays) { Text("半年").tag(180); Text("一年").tag(365); Text("两年").tag(730) }.frame(width:190) }
            Button("选择分析目录") { model.analyzeFolder() }.glassAction().disabled(model.busy)
            Spacer()
            Button(model.fileCollection == .duplicates ? "开始内容查重" : "读取文件") { model.loadFiles() }.glassAction(prominent:true).disabled(model.busy || model.diskIndex == nil)
        }
        Text(model.managementNote).font(.system(size:12)).foregroundStyle(.secondary).textSelection(.enabled)
        if model.indexStale { Label("索引可能已过期，请在空间透镜刷新。写操作仍会重新校验文件。",systemImage:"arrow.clockwise").font(.system(size:11)).foregroundStyle(.orange) }
        if model.fileCollection == .duplicates {
            ForEach(model.duplicateGroups) { group in
                VStack(alignment:.leading,spacing:12) {
                    Text("\(group.files.count) 份相同内容 · 每份 \(byteText(group.files[0].logical))").font(.headline)
                    ForEach(group.files) { file in fileRow(file) }
                }.contentPanel()
            }
        } else {
            LazyVStack(spacing:0) { ForEach(model.managedFiles) { file in fileRow(file); Divider() } }.contentPanel()
            if model.fileCanNext { Button("下一页（500 项）") { model.loadFiles(next:true) }.glassAction().disabled(model.busy) }
        }
        HStack { Text("已选 \(model.fileSelection.count) 项").font(.system(size:12)); Spacer(); Button("预览移入废纸篓",action:model.previewManagedFiles).glassAction(prominent:true).disabled(model.busy || model.fileSelection.isEmpty) }
    }
    func fileRow(_ file: IndexedFile) -> some View {
        HStack(spacing:12) {
            Toggle("选择 " + file.name,isOn:Binding(get:{ model.fileSelection.contains(file.path) },set:{ if $0 { model.fileSelection.insert(file.path) } else { model.fileSelection.remove(file.path) } })).labelsHidden().toggleStyle(.checkbox).disabled(model.busy)
            VStack(alignment:.leading,spacing:4) { Text(file.name).font(.system(size:12,weight:.medium)); Text(file.path).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle); Text("修改于 " + Date(timeIntervalSince1970:Double(file.modified)).formatted(date:.abbreviated,time:.omitted)).font(.system(size:10)).foregroundStyle(.secondary) }
            Spacer(); Text(byteText(file.logical)).font(.system(size:12,design:.rounded))
            Button { model.reveal(file.path) } label: { Image(systemName:"arrow.up.forward.square") }.buttonStyle(.plain).help("在 Finder 中显示")
        }.padding(.vertical,9).contextMenu { Button("加入保护名单") { model.addProtection(file.path) } }
    }
}
struct ProtectionView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        PageHeading(title:"重要的，放心留下。",subtitle:"保护名单补充 Mole 的内置规则，清理和启动项修改都会检查")
        HStack { Text("文件、文件夹及其上层目录的移除都会被拦截。").font(.system(size:12)).foregroundStyle(.secondary); Spacer(); Button("添加保护") { model.addProtection() }.glassAction(prominent:true).disabled(model.busy) }
        LazyVStack(spacing:14) { ForEach(model.protectedPaths,id:\.self) { path in HStack { Label(path,systemImage:"lock.shield").font(.system(size:12)).textSelection(.enabled); Spacer(); Button("取消保护") { model.removeProtection(path) }.disabled(model.busy) } } }.contentPanel().onAppear { model.readProtection() }
    }
}
struct StartupView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        PageHeading(title:"让开机，轻盈一些。",subtitle:"查看后台服务 · 按项管理用户 LaunchAgent")
        HStack { Link("系统登录项与扩展",destination:URL(string:"x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!); Spacer(); Button("检查启动项",action:model.scanStartup).glassAction(prominent:true).disabled(model.busy) }
        Text("用户启动项可停用与恢复；系统服务及现代登录项由 macOS 设置管理。停用不强制结束正在运行的进程。").font(.system(size:12)).foregroundStyle(.secondary)
        LazyVStack(spacing:0) { ForEach(model.startupItems) { item in
            HStack(spacing:14) {
                Image(systemName:item.userAgent ? "person.crop.circle" : "gearshape.2").foregroundStyle(.purple)
                VStack(alignment:.leading,spacing:5) { Text(item.label).font(.system(size:13,weight:.medium)); Text(item.program).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(2); Text(item.userAgent ? (item.disabled == nil ? "状态未确认" : item.disabled! ? "已停用" : "允许启动") : "系统设置管理").font(.system(size:10)) }
                Spacer(); Button("配置") { model.reveal(item.path) }.buttonStyle(.plain)
                if item.userAgent { Button(item.disabled == true ? "启用…" : "停用…") { model.changeStartup(item) }.glassAction().disabled(model.busy || item.disabled == nil) }
            }.padding(.vertical,14); Divider()
        } }.contentPanel()
    }
}
struct SecurityView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        PageHeading(title:"了解防护，安心使用。",subtitle:"系统防护状态与应用签名 · 本页只读")
        CompanionBanner(number:13,title:"重要的防线，逐一看清。",subtitle:"检查 SIP、Gatekeeper、FileVault 与防火墙。\n应用签名校验不等同于恶意软件扫描。",height:210)
        HStack { Button("检查系统防护",action:model.auditProtection).glassAction(prominent:true); Button("选择应用检查签名") { model.auditSignature() }.glassAction(); Spacer(); if let date = model.securityDate { Text(date,style:.time).font(.caption).foregroundStyle(.secondary) } }.disabled(model.busy)
        ForEach(model.securityFindings) { finding in findingView(finding) }
        if let finding = model.signatureFinding { findingView(finding) }
    }
    func findingView(_ finding: AuditFinding) -> some View {
        VStack(alignment:.leading,spacing:10) { Label(finding.title,systemImage:finding.verified ? "info.circle" : "questionmark.circle").font(.headline); Text(finding.detail).font(.system(size:12)).textSelection(.enabled) }.frame(maxWidth:.infinity,alignment:.leading).contentPanel()
    }
}
struct AppUpdatesView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Text("检查应用公开的 Sparkle HTTPS 订阅；App Store 与其他应用交由各自更新器安装。").font(.system(size:12)).foregroundStyle(.secondary)
        HStack { Button("读取应用目录",action:model.readAppInventory).glassAction(); Button("检查 Homebrew",action:model.checkBrewUpdates).glassAction() }.disabled(model.busy)
        Text(model.brewNote).font(.caption).foregroundStyle(.secondary).lineLimit(6)
        ForEach(model.brewUpdates) { update in
            HStack { Text(update.token); Text(update.installed + " → " + update.available).foregroundStyle(.secondary); Spacer(); Button("更新预览…") { model.previewBrewUpdate(update) }.glassAction().disabled(model.busy) }.font(.system(size:12)).contentPanel()
        }
        if let update = model.appUpdate {
            VStack(alignment:.leading,spacing:12) {
                Text("\(update.app.name) · 已安装 \(update.app.version) · 来源版本 \(update.version)").font(.headline)
                Text(update.detail).font(.system(size:12))
                if let feed = update.app.feed { Link("查看更新来源",destination:feed).font(.caption) }
                Button(update.app.appStore ? "打开 App Store 更新" : "打开应用的更新器入口") { model.showAppUpdater(update.app) }.glassAction(prominent:true)
                if !update.app.appStore { Text("打开后，请在应用菜单中选择“检查更新”。").font(.caption).foregroundStyle(.secondary) }
            }.contentPanel()
        }
        LazyVStack(spacing:0) { ForEach(model.managedApps) { app in HStack { VStack(alignment:.leading,spacing:5) { Text(app.name).font(.system(size:13,weight:.medium)); Text(app.version + " · " + (app.appStore ? "App Store" : app.feed == nil ? "应用内更新器" : "Sparkle")).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("检查更新") { model.checkAppUpdate(app) }.glassAction().disabled(model.busy) }.padding(.vertical,12); Divider() } }.contentPanel().onAppear { if model.managedApps.isEmpty { model.readAppInventory() } }
    }
}
