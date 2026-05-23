import Foundation
import AppKit
import Carbon.HIToolbox
import Observation

enum AppPhase: Equatable {
    case idle
    case recording
    case saving
    case error(String)
}

@MainActor
@Observable
final class AppState {
    var options = RecordingOptions()
    var phase: AppPhase = .idle
    /// Local recordings on disk, newest first. Replaces the old upload history.
    var recordings: [URL] = []
    let devices = DeviceCatalog()

    private let recorder = RecordingEngine()
    private let bubble = CameraBubbleController()
    private let controls = RecordingControlsController()
    private let regionOverlay = RecordingRegionOverlay()
    private let regionSelector = RegionSelector()
    private let hotkey = GlobalHotkey()

    /// Re-entry guard for `stopRecording()`. The popover and the floating
    /// controls window each have a Stop button, and on long recordings
    /// `recorder.stop()` can take 1–2s to flush the file. Without a guard,
    /// a second click during that window hits `RecordingError.notRecording`
    /// on the second call and surfaces a spurious error.
    private var isStopping = false

    init() {
        refreshRecordings()
        registerGlobalHotkey()
    }

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    var isBusy: Bool {
        switch phase {
        case .recording, .saving: return true
        default: return false
        }
    }

    // MARK: - Recording

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
        if let region = options.captureRegion {
            regionOverlay.show(rect: region)
        }
        Task {
            do {
                try await recorder.start(options: options)
                phase = .recording
                controls.show(onStop: { [weak self] in self?.stopRecording() })
            } catch {
                phase = .error(error.localizedDescription)
                bubble.hide()
                regionOverlay.hide()
            }
        }
    }

    private func stopRecording() {
        // Guard against double-clicks (popover + floating controls both fire).
        guard !isStopping, case .recording = phase else { return }
        isStopping = true

        controls.hide()
        regionOverlay.hide()
        bubble.hide()
        // Flip out of `.recording` immediately so the menu shows "Saving…"
        // feedback while SCRecordingOutput is still flushing the file.
        phase = .saving

        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.recorder.stop()
                self.isStopping = false
                self.phase = .idle
                self.refreshRecordings()
            } catch {
                self.isStopping = false
                self.phase = .error(error.localizedDescription)
                self.refreshRecordings()
            }
        }
    }

    // MARK: - Local recordings

    /// Reload the on-disk recordings list (newest first).
    func refreshRecordings() {
        guard let dir = try? RecordingEngine.recordingsDirectory() else {
            recordings = []
            return
        }
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        recordings = urls
            .filter { $0.pathExtension.lowercased() == "mov" }
            .sorted { a, b in
                let ad = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let bd = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return ad > bd
            }
    }

    /// Open a recording in the default player (QuickTime).
    func playRecording(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Move a recording to the Trash and refresh the list.
    func deleteRecording(_ url: URL) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        refreshRecordings()
    }

    /// Reveal the local recordings folder in Finder.
    func openRecordingsFolder() {
        guard let url = try? RecordingEngine.recordingsDirectory() else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Region

    func selectRegion() {
        regionSelector.select { [weak self] rect in
            self?.options.captureRegion = rect
        }
    }

    func clearRegion() {
        options.captureRegion = nil
    }

    // MARK: - Global hotkey

    private func registerGlobalHotkey() {
        hotkey.register(
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey)
        ) { [weak self] in
            self?.toggleRecording()
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
