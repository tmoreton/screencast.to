import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import Observation

enum PermissionStatus: Equatable {
    case notDetermined
    case granted
    case denied
}

@MainActor
@Observable
final class PermissionsModel {
    var screenRecording: PermissionStatus = .notDetermined
    var microphone: PermissionStatus = .notDetermined
    var camera: PermissionStatus = .notDetermined

    /// True once the user has been shown the screen-recording prompt (either
    /// the system request or via "Open Settings"). After this, even if the
    /// user toggles the switch ON, macOS only reflects the change after a
    /// full app relaunch — so the onboarding row swaps to a "Quit & Relaunch"
    /// button as the next action.
    var screenRecordingPrompted: Bool = false

    private var pollTask: Task<Void, Never>?

    init() { refresh() }

    var allGranted: Bool {
        screenRecording == .granted && microphone == .granted && camera == .granted
    }

    func refresh() {
        screenRecording = CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
        microphone = mapAVStatus(AVCaptureDevice.authorizationStatus(for: .audio))
        camera = mapAVStatus(AVCaptureDevice.authorizationStatus(for: .video))
    }

    // Screen Recording: macOS only registers the app in System Settings AFTER
    // this call. Then the user has to manually toggle the switch.
    // We rely on `startPolling()` (called from the onboarding view's onAppear)
    // to detect the flip without restarting the app.
    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        screenRecordingPrompted = true
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        screenRecordingPrompted = true
    }

    /// Relaunch the app. After the user flips the Screen Recording toggle in
    /// System Settings, the API only sees the new state after a full restart.
    func relaunchApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphone = granted ? .granted : .denied
    }

    func requestCamera() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        camera = granted ? .granted : .denied
    }

    /// Refresh all three statuses every ~1.5s while called. Cancel with `stopPolling()`.
    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func mapAVStatus(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}
