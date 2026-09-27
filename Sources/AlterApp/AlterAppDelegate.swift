import AppKit

/// Closing the last main window or choosing Quit terminates the app, including
/// its menu-bar extra. A file operation finishes its current atomic step first.
@MainActor final class AlterAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var terminating = false
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        guard let model else { return .terminateNow }
        terminating = true
        Task { @MainActor in
            await model.prepareToQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
