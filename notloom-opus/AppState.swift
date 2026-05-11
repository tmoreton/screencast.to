import Foundation
import AppKit
import Observation

enum AppPhase: Equatable {
    case idle
    case recording
    case uploading(progress: Double)
    case done(URL)
    case error(String)
}

@MainActor
@Observable
final class AppState {
    var options = RecordingOptions()
    var phase: AppPhase = .idle
    var lastSharedURL: URL?
    let devices = DeviceCatalog()

    private let recorder = RecordingEngine()
    private let bubble = CameraBubbleController()
    private let controls = RecordingControlsController()
    private let uploader = UploadClient()

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    var isBusy: Bool {
        switch phase {
        case .recording, .uploading: return true
        default: return false
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        if options.showCameraBubble {
            bubble.show(deviceID: options.cameraDeviceID)
        }
        Task {
            do {
                try await recorder.start(options: options)
                phase = .recording
                controls.show(onStop: { [weak self] in self?.stopRecording() })
            } catch {
                phase = .error(error.localizedDescription)
                bubble.hide()
            }
        }
    }

    private func stopRecording() {
        controls.hide()
        Task { [weak self] in
            guard let self else { return }
            do {
                let fileURL = try await self.recorder.stop()
                self.bubble.hide()
                self.phase = .uploading(progress: 0)
                let publicURL = try await self.uploader.upload(fileURL: fileURL) { [weak self] p in
                    self?.phase = .uploading(progress: p)
                }
                self.lastSharedURL = publicURL
                self.phase = .done(publicURL)
            } catch {
                self.phase = .error(error.localizedDescription)
                self.bubble.hide()
            }
        }
    }

    func copyLastURL() {
        guard let url = lastSharedURL else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
    }

    func openLastURL() {
        guard let url = lastSharedURL else { return }
        NSWorkspace.shared.open(url)
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
