import Foundation
import AppKit
import Carbon.HIToolbox
import Observation

enum AppPhase: Equatable {
    case idle
    case recording
    case paused
    case saving
}

@MainActor
@Observable
final class AppState {
    var options = RecordingOptions()
    var phase: AppPhase = .idle
    /// Local recordings on disk, newest first. Replaces the old upload history.
    var recordings: [URL] = []
    /// Sticky error banner: set when a recording fails, cleared only when the
    /// user explicitly dismisses it (survives across phase changes).
    var lastError: String?
    let devices = DeviceCatalog()

    private let recorder = RecordingEngine()
    private let bubble = CameraBubbleController()
    private let controls = RecordingControlsController()
    private let regionOverlay = RecordingRegionOverlay()
    private let regionSelector = RegionSelector()
    private let hotkey = GlobalHotkey()
    private let zoom = ZoomController()
    /// Zoom hotkey is registered only while recording so it doesn't hijack
    /// ⌘⇧Z (Redo) system-wide the rest of the time.
    private var zoomHotkeyID: UInt32?
    /// Format-cycle hotkey (⌘⇧C), registered only while recording.
    private var formatHotkeyID: UInt32?
    /// Live filming format during a recording (starts from `options.format`).
    private var currentFormat: CaptureFormat = .screenAndCamera

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

    var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }

    /// A recording is in progress (whether actively capturing or paused).
    var isActive: Bool { isRecording || isPaused }

    var isBusy: Bool {
        switch phase {
        case .recording, .paused, .saving: return true
        default: return false
        }
    }

    // MARK: - Recording

    func toggleRecording() {
        if isActive {
            stopRecording()
        } else {
            startRecording()
        }
    }

    /// Toggle pause/resume on the active recording (driven by the pill).
    func togglePauseResume() {
        switch phase {
        case .recording:
            recorder.pause()
            phase = .paused
            controls.setPaused(true)
        case .paused:
            recorder.resume()
            phase = .recording
            controls.setPaused(false)
        default:
            break
        }
    }

    private func startRecording() {
        // Dismiss the menu popover so it isn't caught in the first frames.
        dismissMenuPopover()

        currentFormat = options.format
        let captureRect = captureRectGlobal()
        if let region = options.captureRegion {
            regionOverlay.show(rect: region, recording: true)
        }
        zoom.start(captureRectGlobal: captureRect)
        registerZoomHotkey()
        registerFormatHotkey()

        Task {
            do {
                if currentFormat.usesCamera {
                    // Warm up the camera and wait for a live frame before
                    // capturing, so the bubble isn't an empty circle at the
                    // start. This also covers the popover-dismiss delay.
                    await bubble.apply(format: currentFormat, deviceID: options.cameraDeviceID, region: options.captureRegion)
                } else {
                    bubble.hide()
                    // Give the dismissed popover a beat to disappear.
                    try? await Task.sleep(for: .milliseconds(250))
                }
                try await recorder.start(options: options, zoomState: zoom.state)
                phase = .recording
                controls.show(
                    onStop: { [weak self] in self?.stopRecording() },
                    onPauseResume: { [weak self] in self?.togglePauseResume() },
                    onCycleFormat: { [weak self] in self?.cycleFormat() }
                )
                controls.setFormat(currentFormat)
            } catch {
                lastError = error.localizedDescription
                phase = .idle
                bubble.hide()
                regionOverlay.hide()
                zoom.stop()
                unregisterZoomHotkey()
                unregisterFormatHotkey()
            }
        }
    }

    /// Cycle Screen → Screen+Camera → Camera, applied live during recording.
    func cycleFormat() {
        guard isActive else { return }
        currentFormat = currentFormat.next
        controls.setFormat(currentFormat)
        Task {
            await bubble.apply(format: currentFormat,
                               deviceID: options.cameraDeviceID,
                               region: options.captureRegion)
        }
    }

    private func stopRecording() {
        // Guard against double-clicks (popover + floating controls both fire).
        guard !isStopping, isActive else { return }
        isStopping = true

        controls.hide()
        regionOverlay.hide()
        bubble.hide()
        zoom.stop()
        unregisterZoomHotkey()
        unregisterFormatHotkey()
        // Flip out of `.recording` immediately so the menu shows "Saving…"
        // feedback while the writer is still flushing the file.
        phase = .saving

        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.recorder.stop()
                self.isStopping = false
                self.phase = .idle
                self.refreshRecordings()
                self.showIdleRegionOverlayIfNeeded()
            } catch {
                self.isStopping = false
                self.lastError = error.localizedDescription
                self.phase = .idle
                self.refreshRecordings()
                self.showIdleRegionOverlayIfNeeded()
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

    /// Clear the sticky error banner (user-initiated only).
    func dismissError() {
        lastError = nil
    }

    /// Reveal the local recordings folder in Finder.
    func openRecordingsFolder() {
        guard let url = try? RecordingEngine.recordingsDirectory() else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Region

    func selectRegion(aspect: CaptureAspect = .free) {
        regionSelector.select(aspect: aspect) { [weak self] rect in
            guard let self, let rect else { return }  // keep current on cancel
            self.options.captureRegion = rect
            self.options.captureAspect = aspect
            // Keep the selected area marked on screen until cleared.
            if !self.isActive {
                self.regionOverlay.show(rect: rect, recording: false)
            }
        }
    }

    func clearRegion() {
        options.captureRegion = nil
        options.captureAspect = .free
        regionOverlay.hide()
    }

    /// Re-show the calm region outline after a recording ends (if a region is
    /// still selected), so the marked area persists until cleared.
    private func showIdleRegionOverlayIfNeeded() {
        if let region = options.captureRegion {
            regionOverlay.show(rect: region, recording: false)
        }
    }

    // MARK: - Global hotkey

    private func registerGlobalHotkey() {
        hotkey.register(
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey),
            onPressed: { [weak self] in self?.toggleRecording() }
        )
    }

    private func registerZoomHotkey() {
        guard zoomHotkeyID == nil else { return }
        zoomHotkeyID = hotkey.register(
            keyCode: UInt32(kVK_ANSI_Z),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey),
            onPressed: { [weak self] in
                NSLog("Zoom: ⌘⇧Z pressed -> zoom in")
                self?.zoom.zoomIn()
                self?.controls.setZoomActive(true)
            },
            onReleased: { [weak self] in
                NSLog("Zoom: ⌘⇧Z released -> zoom out")
                self?.zoom.zoomOut()
                self?.controls.setZoomActive(false)
            }
        )
    }

    private func unregisterZoomHotkey() {
        if let id = zoomHotkeyID {
            hotkey.unregister(id)
            zoomHotkeyID = nil
        }
    }

    private func registerFormatHotkey() {
        guard formatHotkeyID == nil else { return }
        formatHotkeyID = hotkey.register(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey),
            onPressed: { [weak self] in self?.cycleFormat() }
        )
    }

    private func unregisterFormatHotkey() {
        if let id = formatHotkeyID {
            hotkey.unregister(id)
            formatHotkeyID = nil
        }
    }

    /// Hide the menu-bar dropdown. When "Start Recording" is clicked the popover
    /// is the key window; we also match it by class as a cross-version fallback.
    private func dismissMenuPopover() {
        NSApp.keyWindow?.orderOut(nil)
        for window in NSApp.windows where window.isVisible {
            let cls = String(describing: type(of: window))
            if cls.contains("MenuBarExtra") || cls.contains("Popover") || cls.contains("StatusBar") {
                window.orderOut(nil)
            }
        }
    }

    /// The captured area in global, y-up screen points (for zoom cursor mapping).
    private func captureRectGlobal() -> CGRect {
        guard let screen = NSScreen.main else { return .zero }
        let f = screen.frame
        if let r = options.captureRegion {
            return CGRect(x: f.minX + r.minX, y: f.maxY - r.maxY, width: r.width, height: r.height)
        }
        return f
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
