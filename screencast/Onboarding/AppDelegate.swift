import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
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
