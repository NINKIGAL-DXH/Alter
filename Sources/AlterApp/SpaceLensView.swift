import SwiftUI
import AlterCore

private let lensColors: [Color] = [Color(red: 0.57, green: 0.43, blue: 0.68), Color(red: 0.69, green: 0.41, blue: 0.51), Color(red: 0.41, green: 0.57, blue: 0.64), Color(red: 0.65, green: 0.56, blue: 0.43), Color(red: 0.43, green: 0.60, blue: 0.56)]

struct SpaceLensView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(alignment: .top) {
            PageHeading(title: "让空间，一目了然。", subtitle: "SPACE LENS  /  圆的面积，代表文件与文件夹的占用。")
            Spacer()
            Button(action: model.analyzeFolder) { Label("选择文件夹", systemImage: "folder.badge.plus") }.glassAction(prominent: true).disabled(model.busy)
        }
        HStack(spacing: 22) {
            if model.companionVisible { ExpressionImage(number: 15, pixels: 700).frame(width: 255, height: 150).clipped().clipShape(RoundedRectangle(cornerRadius: 18)) }
            VStack(alignment: .leading, spacing: 10) {
                Text("看看空间，都藏在哪里。").font(.system(size: 22, weight: .medium))
                Text("点进一颗圆，慢慢看清每一层。\n重要的东西，始终由你决定。").font(.system(size: 12)).lineSpacing(5).foregroundStyle(.secondary)
                Text(model.storageSummary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }.padding(14).panelSurface(radius: 24)
        HStack(spacing: 12) {
            Image(systemName: "folder").foregroundStyle(.secondary)
            TextField("目录路径，如 ~/Documents 或 /Volumes", text: $model.lensPathInput).textFieldStyle(.roundedBorder).onSubmit { model.analyzePath(model.lensPathInput) }.disabled(model.busy)
            Button("分析路径") { model.analyzePath(model.lensPathInput) }.glassAction().disabled(model.busy || model.lensPathInput.isEmpty)
        }
        if let error = model.lensError {
            VStack(alignment: .leading, spacing: 9) {
                Label("这次分析没有完成", systemImage: "exclamationmark.circle").font(.system(size: 13, weight: .semibold))
                Text(error).font(.system(size: 11)).textSelection(.enabled)
                HStack {
                    Button("重新选择目录", action: model.analyzeFolder).glassAction().disabled(model.busy)
                    Link("打开 macOS 隐私设置", destination: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!).font(.system(size: 11))
                }
            }.frame(maxWidth: .infinity, alignment: .leading).contentPanel()
        }
        VStack(alignment: .leading, spacing: 18) {
            navigation
            HStack(alignment: .top, spacing: 22) {
                lens.frame(minWidth: 260, maxWidth: .infinity).frame(height: 440)
                fileList.frame(width: 250, height: 440)
            }
            HStack {
                Label("点圆进入文件夹 · 悬停与列表联动", systemImage: "cursorarrow.rays")
                Spacer()
                Text("只读分析 · Mole V1.55.0")
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }.contentPanel()
    }
    private var navigation: some View {
        HStack(spacing: 10) {
            Button { model.lensNavigate(-1) } label: { Image(systemName: "chevron.left") }.glassAction().disabled(model.busy || model.lensPosition <= 0).help("后退")
            Button { model.lensNavigate(1) } label: { Image(systemName: "chevron.right") }.glassAction().disabled(model.busy || model.lensPosition + 1 >= model.lensTrail.count).help("前进")
            if let path = model.diskSnapshot?.path {
                Menu {
                    ForEach(ancestors(path), id: \.self) { parent in
                        Button(parent) { model.analyzePath(parent) }
                    }
                } label: { Label(path, systemImage: "folder").lineLimit(1).truncationMode(.middle).font(.system(size: 11)) }
                .menuStyle(.borderlessButton).disabled(model.busy).help(path)
                Spacer(minLength: 4)
                Button { model.analyzePath(path) } label: { Image(systemName: "arrow.clockwise") }.glassAction().disabled(model.busy).help("重新分析当前目录")
            } else {
                Text("选择目录，开始探索").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
    private var lens: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().fill(RadialGradient(colors: [Color.purple.opacity(0.045), .clear], center: .center, startRadius: 0, endRadius: size / 2))
                Circle().strokeBorder(.primary.opacity(0.08), lineWidth: 0.7)
                Circle().strokeBorder(.primary.opacity(0.035), style: StrokeStyle(lineWidth: 0.7, dash: [2, 7])).padding(15)
                if model.lensBubbles.isEmpty {
                    VStack(spacing: 15) {
                        Image(systemName: model.busy ? "sparkle.magnifyingglass" : "circle.hexagongrid").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(lensColors[0])
                        Text(model.busy ? "正在看清每一份占用" : model.diskSnapshot == nil ? "你的空间，等你探索" : "这个目录没有可显示的占用").font(.system(size: 15, weight: .medium))
                        Text("文件夹、隐藏项目与小文件\n都可在这里查看").font(.system(size: 11)).lineSpacing(5).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if !model.busy { Button("选择一个文件夹", action: model.analyzeFolder).glassAction() }
                    }
                } else {
                    ForEach(Array(model.lensBubbles.enumerated()), id: \.element.id) { index, bubble in
                        bubbleView(bubble, color: lensColors[index % lensColors.count], diameter: bubble.radius * size * 0.90)
                            .position(x: geometry.size.width / 2 + bubble.x * size * 0.45, y: geometry.size.height / 2 + bubble.y * size * 0.45)
                    }
                    .id(model.diskSnapshot?.path)
                    .transition(.asymmetric(insertion: .scale(scale: 0.86).combined(with: .opacity), removal: .scale(scale: 1.10).combined(with: .opacity)))
                }
                if model.busy, let started = model.lensStarted {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Mole 正在分析…").font(.system(size: 12, weight: .medium))
                        TimelineView(.periodic(from: started, by: 1)) { context in
                            Text("已用时 \(Int(context.date.timeIntervalSince(started))) 秒").font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Button("停止", action: model.cancel).glassAction()
                    }.padding(22).panelSurface().shadow(color: .black.opacity(0.08), radius: 20)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
                .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.86), value: model.diskSnapshot?.path)
        }
    }
    private func bubbleView(_ bubble: LensBubble, color: Color, diameter: Double) -> some View {
        let highlighted = model.lensHover == bubble.id
        return Button {
            if bubble.remainder { model.lensRemainderOnly.toggle(); model.lensPage = 0 }
            else if let entry = model.diskSnapshot?.entries.first(where: { $0.path == bubble.id }) { model.lensOpen(entry) }
        } label: {
            ZStack {
                Circle().fill(LinearGradient(colors: [color.opacity(0.44), color.opacity(0.15), color.opacity(0.34)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.85), color.opacity(0.30), .white.opacity(0.40)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: highlighted ? 2.2 : 0.8)
                if diameter > 65 {
                    VStack(spacing: diameter > 130 ? 8 : 4) {
                        if diameter > 115 { Image(systemName: bubble.remainder ? "ellipsis" : bubble.directory ? "folder" : "doc").font(.system(size: 20, weight: .light)) }
                        Text(bubble.name).font(.system(size: diameter > 130 ? 13 : 10, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
                        Text(byteText(bubble.bytes)).font(.system(size: diameter > 130 ? 17 : 10, weight: .medium, design: .rounded)).monospacedDigit()
                    }.padding(diameter * 0.14).foregroundStyle(.primary)
                }
            }.frame(width: diameter, height: diameter)
                .shadow(color: color.opacity(highlighted ? 0.30 : 0.12), radius: highlighted ? 16 : 8, y: 5)
                .scaleEffect(highlighted && !reduceMotion ? 1.035 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: highlighted)
                .contentShape(Circle())
        }.buttonStyle(.plain).disabled(model.busy)
            .onHover { model.lensHover = $0 ? bubble.id : nil }
            .help(bubble.name + " · " + byteText(bubble.bytes) + (bubble.directory ? " · 点击进入" : ""))
            .accessibilityLabel(bubble.name + "，" + byteText(bubble.bytes))
            .contextMenu { if !bubble.remainder { Button("在 Finder 中显示") { model.reveal(bubble.id) }; if let entry = model.diskSnapshot?.entries.first(where: { $0.path == bubble.id }) { Button("预览移入废纸篓") { model.previewLensItem(entry) }.disabled(model.busy) } } }
    }
    private var fileList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(model.lensRemainderOnly ? "其他项目" : "空间详情").font(.system(size: 14, weight: .semibold)); Spacer(); if model.lensRemainderOnly { Button("全部") { model.lensRemainderOnly = false; model.lensPage = 0 }.font(.system(size: 11)) } }
            TextField("搜索当前目录", text: $model.lensQuery).textFieldStyle(.roundedBorder).onChange(of: model.lensQuery) { model.lensPage = 0 }
            if model.diskSnapshot == nil { Spacer(); Text("扫描完成后，\n占用最大的项目会排在前面。").font(.system(size: 12)).lineSpacing(6).foregroundStyle(.secondary); Spacer() }
            else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(model.pagedLensEntries) { entry in
                            Button { model.lensOpen(entry) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: entry.isDir ? "folder" : "doc").foregroundStyle(lensColors[0]).frame(width: 18)
                                    VStack(alignment: .leading, spacing: 5) { Text(entry.name).lineLimit(1).font(.system(size: 12, weight: .medium)); Text(byteText(entry.size)).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary) }
                                    Spacer(minLength: 4)
                                    Image(systemName: entry.isDir ? "chevron.right" : "arrow.up.forward.square").font(.system(size: 9)).foregroundStyle(.secondary)
                                }.padding(11).background(model.lensHover == entry.path ? lensColors[0].opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).disabled(model.busy).onHover { model.lensHover = $0 ? entry.path : nil }.help(entry.path)
                                .contextMenu { Button("在 Finder 中显示") { model.reveal(entry.path) }; Button("预览移入废纸篓") { model.previewLensItem(entry) }.disabled(model.busy) }
                        }
                    }
                }
                if model.lensEntries.count > 100 {
                    HStack { Button("上一页") { model.lensPage -= 1 }.disabled(model.lensPage == 0); Spacer(); Text("\(model.lensPage + 1) / \((model.lensEntries.count + 99) / 100)"); Spacer(); Button("下一页") { model.lensPage += 1 }.disabled((model.lensPage + 1) * 100 >= model.lensEntries.count) }.font(.system(size: 10))
                }
                Text("\(model.lensEntries.count) 项 · 按占用排序").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
    private func ancestors(_ path: String) -> [String] {
        var paths = [path], current = path
        while current != "/" { current = URL(fileURLWithPath: current).deletingLastPathComponent().path; paths.append(current) }
        return paths
    }
}
