import SwiftUI
import AppKit

@main struct AlterApp: App {
    @StateObject private var model = AppModel()
    init() {
        if CommandLine.arguments.contains("--smoke-test") {
            guard Assets.expressions.count == 23,
                  Assets.image("Brand/Alter.png", pixels: 64) != nil,
                  FileManager.default.fileExists(atPath: Assets.root.appendingPathComponent("Mole/UPSTREAM.json").path) else {
                fputs("Alter bundle resource verification failed\n", stderr); exit(1)
            }
            print("Alter bundle verified: 23 expressions, supplied icon, pinned Mole core.")
            exit(0)
        }
    }
    var body: some Scene {
        WindowGroup("Alter") {
            ContentView().environmentObject(model).tint(Color(red: 0.64, green: 0.23, blue: 0.35))
                .frame(minWidth: 960, minHeight: 700)
                .preferredColorScheme(model.appearance == 0 ? nil : model.appearance == 1 ? .light : .dark)
        }.defaultSize(width: 1220, height: 860)
            .windowStyle(.hiddenTitleBar)
            .commands {
                CommandGroup(replacing: .appInfo) { Button("关于 Alter") { model.page = .settings } }
                CommandGroup(after: .appInfo) { Button("停止当前扫描") { model.cancel() }.keyboardShortcut(".", modifiers: .command).disabled(!model.busy) }
            }
    }
}
