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

/// On-demand upload state for a single recording.
enum UploadState: Equatable {
    case idle
    case uploading(Double)
    case done(url: URL, at: Date)
    case failed(String)
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

    /// Teleprompter script (persisted) and whether to show it while recording.
    /// The teleprompter window is excluded from the recording.
    var teleprompterScript: String = "" {
        didSet { UserDefaults.standard.set(teleprompterScript, forKey: Self.scriptKey) }
    }
    var teleprompterEnabled: Bool = false {
        didSet { UserDefaults.standard.set(teleprompterEnabled, forKey: Self.enabledKey) }
    }
    private static let scriptKey = "screencast.teleprompter.script"
    private static let enabledKey = "screencast.teleprompter.enabled"

    /// Per-recording upload state, keyed by local file path. Links live 24h.
    var uploads: [String: UploadState] = [:]
    private static let uploadsKey = "screencast.uploads.v1"
    /// Uploaded links expire server-side after this (R2 lifecycle rule).
    static let linkLifetime: TimeInterval = 24 * 60 * 60

    let devices = DeviceCatalog()

    private let recorder = RecordingEngine()
    private let bubble = CameraBubbleController()
    private let controls = RecordingControlsController()
    private let regionOverlay = RecordingRegionOverlay()
    private let regionSelector = RegionSelector()
    private let hotkey = GlobalHotkey()
    private let zoom = ZoomController()
    private let teleprompter = TeleprompterController()
    /// The controls host for the current recording: the standalone pill, or the
    /// teleprompter (with the recording controls embedded in its header) when the
    /// teleprompter is in use — so they're one unit.
    private var activeControls: RecordingControlsHost?
    /// Zoom hotkey is registered only while recording so it doesn't hijack
    /// ⌘⇧Z (Redo) system-wide the rest of the time.
    private var zoomHotkeyID: UInt32?
    /// Format-cycle hotkey (⌘⇧C), registered only while recording.
    private var formatHotkeyID: UInt32?
    /// Teleprompter scroll hotkey (⌘⇧Space), registered only while recording.
    private var teleprompterHotkeyID: UInt32?
    /// Live filming format during a recording (starts from `options.format`).
    private var currentFormat: CaptureFormat = .screenAndCamera

    /// Re-entry guard for `stopRecording()`. The popover and the floating
    /// controls window each have a Stop button, and on long recordings
    /// `recorder.stop()` can take 1–2s to flush the file. Without a guard,
    /// a second click during that window hits `RecordingError.notRecording`
    /// on the second call and surfaces a spurious error.
    private var isStopping = false

    init() {
        teleprompterScript = UserDefaults.standard.string(forKey: Self.scriptKey) ?? ""
        teleprompterEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        loadUploads()
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
            activeControls?.setPaused(true)
        case .paused:
            recorder.resume()
            phase = .recording
            activeControls?.setPaused(false)
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

        let useTeleprompter = teleprompterEnabled && !teleprompterScript.isEmpty
        if useTeleprompter {
            teleprompter.loadScript(teleprompterScript)
            registerTeleprompterHotkey()
            activeControls = teleprompter
        } else {
            activeControls = controls
        }

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
                activeControls?.showControls(
                    onStop: { [weak self] in self?.stopRecording() },
                    onPauseResume: { [weak self] in self?.togglePauseResume() },
                    onCycleFormat: { [weak self] in self?.cycleFormat() }
                )
                activeControls?.setFormat(currentFormat)
            } catch {
                lastError = error.localizedDescription
                phase = .idle
                bubble.hide()
                regionOverlay.hide()
                zoom.stop()
                teleprompter.hide()
                unregisterZoomHotkey()
                unregisterFormatHotkey()
                unregisterTeleprompterHotkey()
            }
        }
    }

    /// Cycle Screen → Screen+Camera → Camera, applied live during recording.
    func cycleFormat() {
        guard isActive else { return }
        currentFormat = currentFormat.next
        activeControls?.setFormat(currentFormat)
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

        activeControls?.hideControls()
        regionOverlay.hide()
        bubble.hide()
        zoom.stop()
        teleprompter.hide()
        unregisterZoomHotkey()
        unregisterFormatHotkey()
        unregisterTeleprompterHotkey()
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

    // MARK: - Upload (on-demand, background)

    /// Current upload state for a recording, treating links older than 24h as
    /// expired (they're gone server-side).
    func uploadState(for url: URL) -> UploadState {
        let state = uploads[url.path] ?? .idle
        if case .done(_, let at) = state, Date().timeIntervalSince(at) > Self.linkLifetime {
            return .idle
        }
        return state
    }

    /// Upload a recording to R2 in the background and produce a 24h link.
    /// Non-blocking: runs on its own URLSession so it never interferes with
    /// recording. The link is copied to the clipboard on success.
    func uploadRecording(_ url: URL) {
        let path = url.path
        if case .uploading = uploads[path] { return }  // already in flight
        uploads[path] = .uploading(0)
        Task { [weak self] in
            let client = UploadClient()
            do {
                let publicURL = try await client.upload(fileURL: url) { progress in
                    self?.uploads[path] = .uploading(progress)
                }
                guard let self else { return }
                let now = Date()
                self.uploads[path] = .done(url: publicURL, at: now)
                self.persistUploads()
                self.copyLink(publicURL)
            } catch {
                self?.uploads[path] = .failed(error.localizedDescription)
            }
        }
    }

    func copyLink(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
    }

    func copyIssueNote(for recording: URL, link: URL, sharedAt: Date) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(issueNote(for: recording, link: link, sharedAt: sharedAt), forType: .string)
    }

    func openLink(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private struct PersistedUpload: Codable {
        let url: URL
        let at: Date
    }

    private func persistUploads() {
        var store: [String: PersistedUpload] = [:]
        for (path, state) in uploads {
            if case .done(let url, let at) = state,
               Date().timeIntervalSince(at) <= Self.linkLifetime {
                store[path] = PersistedUpload(url: url, at: at)
            }
        }
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: Self.uploadsKey)
        }
    }

    private func loadUploads() {
        guard let data = UserDefaults.standard.data(forKey: Self.uploadsKey),
              let store = try? JSONDecoder().decode([String: PersistedUpload].self, from: data) else {
            return
        }
        let now = Date()
        for (path, item) in store where now.timeIntervalSince(item.at) <= Self.linkLifetime {
            uploads[path] = .done(url: item.url, at: item.at)
        }
    }

    private func issueNote(for recording: URL, link: URL, sharedAt: Date) -> String {
        let expiresAt = sharedAt.addingTimeInterval(Self.linkLifetime)
        let dateFormatter = ISO8601DateFormatter()
        let createdAt = (try? recording.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        let bytes = (try? recording.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return """
        ### Temporary screencast

        \(link.absoluteString)

        Expires: \(dateFormatter.string(from: expiresAt))
        Recording: \(recording.lastPathComponent) (\(size))
        Created: \(dateFormatter.string(from: createdAt))
        Environment: \(ProcessInfo.processInfo.operatingSystemVersionString), Screencast \(version) (\(build))

        ### Notes

        - What happened:
        - Expected:
        - Steps:
        """
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
                self?.activeControls?.setZoomActive(true)
            },
            onReleased: { [weak self] in
                NSLog("Zoom: ⌘⇧Z released -> zoom out")
                self?.zoom.zoomOut()
                self?.activeControls?.setZoomActive(false)
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

    private func registerTeleprompterHotkey() {
        guard teleprompterHotkeyID == nil else { return }
        teleprompterHotkeyID = hotkey.register(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey),
            onPressed: { [weak self] in self?.teleprompter.toggleScroll() }
        )
    }

    private func unregisterTeleprompterHotkey() {
        if let id = teleprompterHotkeyID {
            hotkey.unregister(id)
            teleprompterHotkeyID = nil
        }
    }

    // MARK: - Teleprompter

    /// Show/hide the teleprompter outside of recording so the user can position
    /// it and preview the script.
    func toggleTeleprompterPreview() {
        teleprompter.loadScript(teleprompterScript)
        teleprompter.togglePreview()
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
