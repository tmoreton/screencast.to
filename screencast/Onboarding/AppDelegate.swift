import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var recordingState: AppState?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard recordingState?.phase == .saving else { return .terminateNow }
        Task { @MainActor in
            await recordingState?.waitForPendingSave()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                _ = WebsiteSharingManager.shared.handleCallbackURL(url)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            OnboardingManager.shared.showIfNeeded()
        }
    }
}
