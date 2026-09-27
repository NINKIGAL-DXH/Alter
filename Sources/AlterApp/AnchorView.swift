import SwiftUI
import AppKit
import CoreText
import AlterCore

// Keep the property-wrapper spelling unambiguous with SDKs that also export a State macro.
private typealias AnchorState<Value> = SwiftUI.State<Value>

struct AnchorSetupView: View {
    @EnvironmentObject var model: AppModel
    @AnchorState<String> private var draft = ""
    @AnchorState<String?> private var note: String?
    var body: some View {
        PageHeading(title: "Anchor", subtitle: "让一句话，静静停在光里。")
        ZStack(alignment: .bottomLeading) {
            ExpressionImage(number: model.anchorPicture, pixels: 1400).frame(height: 310).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                Text("A N C H O R").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                Text("只留下，画面与你的文字。").font(.system(size: 27, weight: .light, design: .serif)).foregroundStyle(.white)
                Text("进入后冻结整理、维护和状态刷新；退出后由你手动继续。").font(.callout).foregroundStyle(.white.opacity(0.8))
            }.padding(28)
        }.frame(height: 310).clipShape(RoundedRectangle(cornerRadius: 24))
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("你的文字").font(.headline); Spacer(); Text("用空行分段 · 每段依次呈现").font(.caption).foregroundStyle(.secondary) }
            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(get: { draft }, set: { value in
                    if value.utf8.count <= 131_072 && value.count <= AnchorText.maximumCharacters { draft = value }
                    else { note = "文字超过 8,000 字，本次输入未采用；原有文字仍保留。" }
                })).font(.system(size: 17, design: .serif)).scrollContentBackground(.hidden).padding(8)
                if draft.isEmpty { Text("在这里粘贴你想留下的话…").foregroundStyle(.secondary).padding(13).allowsHitTesting(false) }
            }.frame(height: 150).background(.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Text("\(draft.count) / 8,000 字 · 仅保存在本机").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("保存文字") { save() }.glassAction()
            }
            if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
        }.contentPanel()
        HStack(spacing: 20) {
            Toggle("轮播全部 23 张角色图片", isOn: $model.anchorSlideshow)
            if !model.anchorSlideshow {
                Picker("画面", selection: $model.anchorPicture) { ForEach(Assets.expressions) { Text($0.name).tag($0.id) } }.frame(maxWidth: 250)
            }
            Spacer()
        }.contentPanel()
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Esc 退出 · ⌘⇧A 随时切换").font(.callout)
                Text("应用内屏保，可切换全屏；不改变 macOS 锁屏与休眠设置。").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("进入 Anchor", systemImage: "sparkle") { if save() { model.enterAnchor() } }
                .glassAction(prominent: true).disabled(model.busy)
        }
        if model.busy { Text("当前任务结束后即可进入。文件操作不会被强行暂停在中途。").font(.caption).foregroundStyle(.secondary) }
        if let message = model.anchorPreparingNote { Text(message).font(.callout).foregroundStyle(.secondary) }
        Text("未填写文字时仅显示 Anchor 标识。长段落自动分页，原文不会被改写。").font(.caption).foregroundStyle(.secondary)
            .onAppear { draft = model.anchorText }
    }
    @discardableResult private func save() -> Bool {
        do { _ = try AnchorText.pages(draft); model.anchorText = draft; note = "已保存在这台 Mac。"; return true }
        catch { note = error.localizedDescription; return false }
    }
}

/// Static glyph outlines are rebuilt only when the text or window size changes.
/// The animation moves that one shape; it never rasterizes a full-screen texture per frame.
private struct AnchorGlyph: Shape {
    let outline: Path
    func path(in rect: CGRect) -> Path { outline }
}
private struct AnchorLettering {
    let outline: Path
    let size: CGFloat
    let needsFallback: Bool
    static func make(_ text: String, width: CGFloat, height: CGFloat) -> Self {
        var size = min(64, max(32, width / 15))
        while size >= 20 {
            let font = NSFont.systemFont(ofSize: size, weight: .medium)
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineSpacing = size * 0.22
            let string = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: paragraph])
            let setter = CTFramesetterCreateWithAttributedString(string)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: CGRect(x: 0, y: 0, width: width, height: height), transform: nil), nil)
            if CTFrameGetVisibleStringRange(frame).length == string.length {
                let lines = CTFrameGetLines(frame) as! [CTLine]
                var origins = [CGPoint](repeating: .zero, count: lines.count)
                CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
                let path = CGMutablePath(); var fallback = false
                for (lineIndex, line) in lines.enumerated() {
                    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                        let count = CTRunGetGlyphCount(run)
                        var glyphs = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count)
                        CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                        CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                        let attrs = CTRunGetAttributes(run) as NSDictionary
                        let runFont = attrs[kCTFontAttributeName] as! CTFont
                        for i in 0..<count {
                            if let glyph = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
                                path.addPath(glyph, transform: CGAffineTransform(translationX: origins[lineIndex].x + positions[i].x, y: origins[lineIndex].y + positions[i].y))
                            } else if glyphs[i] != CTFontGetGlyphWithName(runFont, "space" as CFString) { fallback = true }
                        }
                    }
                }
                let bounds = path.boundingBoxOfPath
                guard !path.isEmpty else { return .init(outline: Path(), size: size, needsFallback: true) }
                var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: (width - bounds.width) / 2 - bounds.minX, ty: (height + bounds.height) / 2 + bounds.minY)
                return .init(outline: Path(path.copy(using: &transform) ?? path), size: size, needsFallback: fallback)
            }
            size -= 2
        }
        return .init(outline: Path(), size: 20, needsFallback: true)
    }
}

private struct CrystalWords: View {
    let text: String
    let width: CGFloat
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @AnchorState<AnchorLettering> private var letters = AnchorLettering(outline: Path(), size: 40, needsFallback: true)
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion || scenePhase != .active)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let shift = sin(time / 9)
            Group {
                if reduceTransparency || contrast == .increased || letters.needsFallback {
                    Text(text).font(.system(size: letters.size, weight: .medium)).multilineTextAlignment(.center)
                        .foregroundStyle(.white).shadow(color: .black.opacity(0.8), radius: 9, y: 2)
                        .frame(width: width, height: height)
                } else {
                    let glyph = AnchorGlyph(outline: letters.outline)
                    ZStack {
                        if #available(macOS 26.0, *) {
                            Color.clear.glassEffect(.clear, in: glyph)
                        } else {
                            glyph.fill(.ultraThinMaterial)
                        }
                        glyph.fill(LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.16), Color(red: 0.83, green: 0.9, blue: 1).opacity(0.45), .white.opacity(0.7)], startPoint: UnitPoint(x: 0.2 + shift * 0.18, y: 0), endPoint: .bottomTrailing))
                        glyph.stroke(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.08), .white.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.65)
                    }.frame(width: width, height: height)
                        .shadow(color: .black.opacity(0.4), radius: 14, y: 5)
                        .accessibilityElement(children: .ignore).accessibilityLabel(text)
                }
            }.offset(x: reduceMotion ? 0 : shift * 12, y: reduceMotion ? 0 : cos(time / 11) * 8)
        }
        .task(id: "\(text)|\(Int(width))|\(Int(height))") { letters = AnchorLettering.make(text, width: width, height: height) }
    }
}

struct AnchorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AnchorState<Int> private var slide = 0
    @AnchorState<Bool> private var controlsVisible = true
    @AnchorState<Date> private var lastPointer = Date()
    @AnchorState<NSWindow?> private var window: NSWindow?
    @AnchorState<Bool> private var ownsFullScreen = false
    var body: some View {
        GeometryReader { geometry in
            let pictures = model.anchorPictureIDs
            let picture = pictures.isEmpty ? 2 : pictures[slide % pictures.count]
            let pages = model.anchorPages
            let words = pages.isEmpty ? "Anchor" : pages[slide % pages.count]
            ZStack {
                Color.black
                ZStack {
                    ExpressionImage(number: picture, pixels: 1600).frame(width: geometry.size.width, height: geometry.size.height).clipped().blur(radius: 32).overlay(.black.opacity(0.25))
                    ExpressionImage(number: picture, pixels: 1600, fit: .fit).frame(width: geometry.size.width, height: geometry.size.height)
                }.id(picture).transition(.opacity)
                LinearGradient(stops: [.init(color: .black.opacity(0.08), location: 0), .init(color: .clear, location: 0.42), .init(color: .black.opacity(0.37), location: 1)], startPoint: .top, endPoint: .bottom)
                CrystalWords(text: words, width: min(860, geometry.size.width - 120), height: min(300, geometry.size.height * 0.43))
                    .id(words).transition(.opacity)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.71)
                if model.anchorSession.phase == .preparing { ProgressView("正在进入 Anchor…").padding(24).panelSurface().foregroundStyle(.white) }
                VStack {
                    HStack {
                        HStack(spacing: 10) { Image(systemName: "sparkle"); Text("A N C H O R").font(.system(size: 11, weight: .medium)); Text("原有功能已冻结").font(.caption).foregroundStyle(.white.opacity(0.65)) }
                        Spacer()
                        Button { toggleFullscreen() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.glassAction().help("切换全屏")
                        Button("退出 · Esc") { exit() }.glassAction()
                    }
                    Spacer()
                    HStack {
                        Button { advance(-1) } label: { Image(systemName: "chevron.left") }.glassAction().accessibilityLabel("上一幅")
                        Spacer()
                        Text("ALTER  /  STAY A LITTLE LONGER").font(.system(size: 9, weight: .medium)).tracking(2)
                        Spacer()
                        Button { advance(1) } label: { Image(systemName: "chevron.right") }.glassAction().accessibilityLabel("下一幅")
                    }
                }.padding(28).foregroundStyle(.white).opacity(controlsVisible ? 1 : 0).allowsHitTesting(controlsVisible)
            }.clipped().background { AnchorWindowReader { window = $0 } }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active = phase, Date().timeIntervalSince(lastPointer) > 0.3 { wake() }
                }
                .onTapGesture { wake() }
        }.ignoresSafeArea().preferredColorScheme(.dark)
            .onExitCommand { exit() }
            .task(id: lastPointer) {
                do { try await Task.sleep(for: .seconds(4)); withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) { controlsVisible = false } } catch {}
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(22)) } catch { return }
                    guard !Task.isCancelled, model.anchorSession.phase == .active else { return }
                    advance(1)
                }
            }
            .onDisappear { if ownsFullScreen, window?.styleMask.contains(.fullScreen) == true { window?.toggleFullScreen(nil) } }
    }
    private func wake() { lastPointer = Date(); controlsVisible = true }
    private func advance(_ delta: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.8)) { slide = max(0, slide + delta) }
    }
    private func toggleFullscreen() {
        guard let window else { return }
        ownsFullScreen = !window.styleMask.contains(.fullScreen); window.toggleFullScreen(nil); wake()
    }
    private func exit() { model.leaveAnchor() }
}

private struct AnchorWindowReader: NSViewRepresentable {
    var ready: (NSWindow) -> Void
    class Probe: NSView {
        var ready: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if let window { DispatchQueue.main.async { [weak self, weak window] in if let window { self?.ready?(window) } } } }
    }
    func makeNSView(context: Context) -> Probe { let view = Probe(); view.ready = ready; return view }
    func updateNSView(_ view: Probe, context: Context) { view.ready = ready }
}
