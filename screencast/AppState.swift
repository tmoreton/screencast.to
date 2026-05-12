import Foundation
import AppKit
import Carbon.HIToolbox
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
    var history: [ShareEntry] = []
    var pendingRecordings: [URL] = []
    let devices = DeviceCatalog()

    /// Set when the most recent upload attempt failed; used by the Retry
    /// button in the menu while `phase == .error`.
    private(set) var failedUploadURL: URL?

    private let recorder = RecordingEngine()
    private let bubble = CameraBubbleController()
    private let controls = RecordingControlsController()
    private let regionOverlay = RecordingRegionOverlay()
    private let uploader = UploadClient()
    private let regionSelector = RegionSelector()
    private let hotkey = GlobalHotkey()

    /// Re-entry guard for `stopRecording()`. The popover and the floating
    /// controls window each have a Stop button, and on long recordings
    /// `recorder.stop()` can take 1–2s to flush the file. Without a guard,
    /// a second click during that window hits `RecordingError.notRecording`
    /// on the second call and surfaces a spurious "Upload failed" — losing
    /// the in-flight recording from the user's perspective.
    private var isStopping = false

    init() {
        history = ShareHistoryStore.shared.entries
        refreshPendingRecordings()
        registerGlobalHotkey()
    }

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
        // Flip out of `.recording` immediately so the menu swaps the Stop
        // button for the upload progress view and the user sees feedback even
        // while the file is still being flushed by SCRecordingOutput.
        phase = .uploading(progress: 0)

        Task { [weak self] in
            guard let self else { return }
            do {
                let fileURL = try await self.recorder.stop()
                self.isStopping = false
                await self.performUpload(fileURL: fileURL)
            } catch {
                self.isStopping = false
                self.phase = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Upload

    private func performUpload(fileURL: URL) async {
        failedUploadURL = nil
        phase = .uploading(progress: 0)
        do {
            let publicURL = try await uploader.upload(fileURL: fileURL) { [weak self] p in
                self?.phase = .uploading(progress: p)
            }
            ShareHistoryStore.shared.record(localURL: fileURL, publicURL: publicURL)
            history = ShareHistoryStore.shared.entries
            lastSharedURL = publicURL
            phase = .done(publicURL)
            refreshPendingRecordings()
        } catch {
            failedUploadURL = fileURL
            phase = .error(error.localizedDescription)
            refreshPendingRecordings()
        }
    }

    /// Retry the upload that just failed (driven by the Retry button on
    /// `phase == .error`). Falls through quietly if there is no candidate.
    func retryFailedUpload() {
        guard let url = failedUploadURL else { return }
        Task { await performUpload(fileURL: url) }
    }

    /// Upload an arbitrary on-disk recording (used by the Pending Uploads list).
    func retryUpload(fileURL: URL) {
        Task { await performUpload(fileURL: fileURL) }
    }

    // MARK: - Pending recordings

    func refreshPendingRecordings() {
        guard let dir = try? RecordingEngine.recordingsDirectory() else {
            pendingRecordings = []
            return
        }
        let fm = FileManager.default
        let uploaded = ShareHistoryStore.shared.uploadedLocalPaths()
        let urls = (try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        pendingRecordings = urls
            .filter { $0.pathExtension.lowercased() == "mov" }
            .filter { !uploaded.contains($0.path) }
            .sorted { a, b in
                let ad = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let bd = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return ad > bd
            }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - History actions

    func copyLastURL() {
        guard let url = lastSharedURL else { return }
        copyURL(url)
    }

    func copyURL(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
    }

    func openLastURL() {
        guard let url = lastSharedURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Reveal the local recordings folder in Finder. Failed uploads stay
    /// here as a safety net for re-upload / recovery.
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
