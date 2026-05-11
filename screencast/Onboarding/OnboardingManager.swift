import AppKit
import AVFoundation
import CoreGraphics
import SwiftUI

@MainActor
final class OnboardingManager {
    static let shared = OnboardingManager()
    private init() {}

    private var window: NSWindow?

    /// Show onboarding whenever any of the three required TCC permissions
    /// is not yet granted. Re-evaluated on every app launch and any time
    /// `showIfNeeded()` is called.
    var needsOnboarding: Bool {
        let screen = CGPreflightScreenCaptureAccess()
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let cam = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        return !(screen && mic && cam)
    }

    func showIfNeeded() {
        if needsOnboarding {
            show()
        }
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = OnboardingView(onFinish: { [weak self] in self?.dismiss() })
        let hosting = NSHostingController(rootView: root)
        let win = NSWindow(contentViewController: hosting)
        win.styleMask = [.titled, .closable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.title = ""
        win.isMovableByWindowBackground = true
        win.standardWindowButton(.zoomButton)?.isHidden = true
        win.standardWindowButton(.miniaturizeButton)?.isHidden = true
        win.center()
        win.isReleasedWhenClosed = false
        win.backgroundColor = NSColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1)

        // Briefly show in dock so the window can grab focus reliably.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)

        self.window = win
    }

    private func dismiss() {
        window?.orderOut(nil)
        window = nil
        // Back to menu-bar-only mode.
        NSApp.setActivationPolicy(.accessory)
    }
}
