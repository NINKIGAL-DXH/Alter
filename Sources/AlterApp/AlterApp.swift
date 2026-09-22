import SwiftUI
import AppKit
import AlterCore

@main struct AlterApp: App {
    @StateObject private var model = AppModel()
    init() {
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--authorized-maintenance" {
            do {
                guard let expires = Int(CommandLine.arguments[3]) else { exit(64) }
                let result = try MoleOperations(resources: Assets.root).executeTask(CommandLine.arguments[2], authority: "admin", expires: expires, cancellation: CancellationFlag())
                print(result); exit(0)
            } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
        }

        if CommandLine.arguments.contains("--smoke-test") {
            guard Assets.expressions.count == 23,
                  Assets.expressions.allSatisfy({ Assets.image("Expressions/" + $0.file, pixels: 160) != nil }),
                  Assets.image("Brand/Alter.png", pixels: 64) != nil,
                  FileManager.default.fileExists(atPath: Assets.root.appendingPathComponent("Mole/UPSTREAM.json").path) else {
                fputs("Alter bundle resource verification failed\n", stderr); exit(1)
            }
            do {
                try MoleOperations(resources: Assets.root).verify()
                for name in ["analyze", "status"] {
                    guard FileManager.default.isExecutableFile(atPath: Assets.root.appendingPathComponent("Kernel/" + name).path) else { throw AlterError.refused("Missing Mole worker: " + name) }
                }
                guard FileManager.default.fileExists(atPath: Assets.root.appendingPathComponent("Kernel/licenses/modules.json").path) else { throw AlterError.refused("Missing dependency licenses") }
            } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
            print("Alter bundle verified: 23 cropped expressions, supplied icon, full pinned Mole source, analyze/status workers and licenses.")
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
