import Foundation
import AppKit
import AVFoundation
import Carbon.HIToolbox
import CoreGraphics
import Observation

enum AppPhase: Equatable {
    case idle
    case starting(Int?)
    case recording
    case paused
    case saving
}

enum OptionalInputAvailability: Equatable {
    case available
    case requestable
    case denied
    case restricted
    case unavailable
}

enum CaptureInputIssue: Hashable {
    case cameraPermissionRequired
    case cameraDenied
    case cameraRestricted
    case cameraUnavailable
    case microphonePermissionRequired
    case microphoneDenied
    case microphoneRestricted
    case microphoneUnavailable

    var isCameraIssue: Bool {
        switch self {
        case .cameraPermissionRequired, .cameraDenied, .cameraRestricted, .cameraUnavailable:
            return true
        default:
            return false
        }
    }

    var isMicrophoneIssue: Bool { !isCameraIssue }
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
    /// Optional inputs that were disabled because permission or hardware was
    /// unavailable. Screen-only recording remains usable in every case.
    var captureInputIssues: [CaptureInputIssue] = []

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

    /// Per-recording upload state, keyed by local file path. Saved links are
    /// presented as fresh for one day; lifecycle deletion may take another day.
    var uploads: [String: UploadState] = [:]
    private static let uploadsKey = "screencast.uploads.v1"
    /// The app forgets a shared link after one day. The R2 lifecycle starts
    /// deletion around then, but physical deletion may take another day.
    static let rememberedLinkLifetime: TimeInterval = 24 * 60 * 60
    private static let maximumDeletionWindow: TimeInterval = 48 * 60 * 60
    private static let cameraPreflightCountdownSeconds = 3

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
    private var currentFormat: CaptureFormat = .screenOnly
    private var startTask: Task<Void, Never>?
    /// When true, the cancelled startup task owns recorder shutdown and the
    /// final transition back to idle; callers must leave any safety curtain up.
    private var deferredStartCancellation = false
    private var formatTransitionTask: Task<Void, Never>?
    private var formatTransitionTarget: CaptureFormat?
    private var formatTransitionGeneration = 0
    private var cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    private var microphoneAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)

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
        refreshOptionalInputAvailability()
        bubble.onCaptureFailure = { [weak self] in
            self?.handleCameraCaptureFailure()
        }
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

    var isStarting: Bool {
        if case .starting = phase { return true }
        return false
    }

    var isBusy: Bool {
        switch phase {
        case .starting, .recording, .paused, .saving: return true
        default: return false
        }
    }

    // MARK: - Recording

    func toggleRecording() {
        switch phase {
        case .starting:
            cancelStartingRecording()
        case .recording, .paused:
            stopRecording()
        case .idle:
            startRecording()
        case .saving:
            break
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
        guard case .idle = phase else { return }
        guard CGPreflightScreenCaptureAccess() else {
            OnboardingManager.shared.show()
            return
        }

        // Dismiss the menu popover so it isn't caught in the first frames.
        dismissMenuPopover()

        deferredStartCancellation = false
        phase = .starting(nil)
        currentFormat = options.format
        let captureRect = captureRectGlobal()
        if let region = options.captureRegion {
            regionOverlay.show(rect: region, recording: false)
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

        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                let canStart = try await self.prepareSelectedOptionalInputs()
                try Task.checkCancellation()
                guard canStart else {
                    self.finishStartingRecording()
                    self.showIdleRegionOverlayIfNeeded()
                    return
                }
                self.currentFormat = self.options.format
                if self.currentFormat.usesCamera {
                    // Warm up the camera and wait for a live frame before
                    // the visible countdown, so auto-exposure/focus settle
                    // before ScreenCaptureKit starts writing frames.
                    let requestedFormat = self.currentFormat
                    let cameraReady = await self.bubble.apply(
                        format: requestedFormat,
                        deviceID: self.options.cameraDeviceID,
                        region: self.options.captureRegion
                    )
                    try Task.checkCancellation()
                    if cameraReady {
                        self.activeControls?.showControls(
                            onStop: { [weak self] in self?.stopRecording() },
                            onPauseResume: { [weak self] in self?.togglePauseResume() },
                            onCycleFormat: { [weak self] in self?.cycleFormat() }
                        )
                        self.activeControls?.setFormat(self.currentFormat)
                        self.activeControls?.beginCountdown(seconds: Self.cameraPreflightCountdownSeconds)
                        try await self.runCameraPreflightCountdown()
                    } else {
                        self.reportCameraUnavailable()
                        self.options.format = .screenOnly
                        self.currentFormat = .screenOnly

                        // Camera-only is implemented as an opaque camera window
                        // over ScreenCaptureKit. Never start ScreenCaptureKit if
                        // that window has no confirmed frame: doing so would save
                        // an unintended desktop recording.
                        guard requestedFormat != .cameraOnly else {
                            self.finishStartingRecording()
                            self.showIdleRegionOverlayIfNeeded()
                            return
                        }

                        // Screen + Camera can safely degrade to Screen Only.
                        try await Task.sleep(for: .milliseconds(250))
                    }
                } else {
                    self.bubble.hide()
                    // Give the dismissed popover a beat to disappear.
                    try await Task.sleep(for: .milliseconds(250))
                }
                try Task.checkCancellation()
                try await self.recorder.start(options: self.options, zoomState: self.zoom.state)
                try Task.checkCancellation()

                if let region = self.options.captureRegion {
                    self.regionOverlay.show(rect: region, recording: true)
                }
                self.phase = .recording
                if !self.currentFormat.usesCamera {
                    self.activeControls?.showControls(
                        onStop: { [weak self] in self?.stopRecording() },
                        onPauseResume: { [weak self] in self?.togglePauseResume() },
                        onCycleFormat: { [weak self] in self?.cycleFormat() }
                    )
                    self.activeControls?.setFormat(self.currentFormat)
                }
                self.activeControls?.beginRecording()
                self.deferredStartCancellation = false
                self.startTask = nil
            } catch is CancellationError {
                await self.unwindCancelledStart()
            } catch {
                if Task.isCancelled {
                    await self.unwindCancelledStart()
                    return
                }
                self.lastError = error.localizedDescription
                self.finishStartingRecording()
            }
        }
    }

    /// Request only the optional inputs selected for this recording. A denied,
    /// restricted, or disconnected input is turned off and reported. A
    /// screen-and-camera recording can safely fall back to screen-only; a
    /// camera-only start is cancelled so it never records the desktop instead.
    private func prepareSelectedOptionalInputs() async throws -> Bool {
        devices.refresh()
        refreshAuthorizationStatuses()
        var issues: [CaptureInputIssue] = []
        let requestedCameraOnly = options.format == .cameraOnly

        if options.format.usesCamera {
            var availability = cameraInputAvailability
            if availability == .requestable {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                try Task.checkCancellation()
                devices.refresh()
                refreshAuthorizationStatuses()
                availability = cameraInputAvailability
                if !granted, availability == .requestable {
                    availability = .denied
                }
            }
            if let issue = cameraIssue(for: availability) {
                options.format = .screenOnly
                issues.append(issue)
                if requestedCameraOnly {
                    captureInputIssues = issues
                    return false
                }
            }
        }

        if options.microphone.isOn {
            var availability = microphoneInputAvailability
            if availability == .requestable {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                try Task.checkCancellation()
                devices.refresh()
                refreshAuthorizationStatuses()
                availability = microphoneInputAvailability
                if !granted, availability == .requestable {
                    availability = .denied
                }
            }
            if let issue = microphoneIssue(for: availability) {
                options.microphone = .off
                issues.append(issue)
            }
        }

        captureInputIssues = issues
        return true
    }

    private func runCameraPreflightCountdown() async throws {
        for remaining in stride(from: Self.cameraPreflightCountdownSeconds, through: 1, by: -1) {
            try Task.checkCancellation()
            phase = .starting(remaining)
            activeControls?.updateCountdown(seconds: remaining)
            try await Task.sleep(for: .seconds(1))
        }
        try Task.checkCancellation()
        phase = .starting(nil)
        activeControls?.updateCountdown(seconds: 0)
    }

    private func cancelStartingRecording() {
        guard isStarting else { return }
        beginDeferredStartCancellation(preserveCameraCurtain: currentFormat == .cameraOnly)
    }

    /// Cancel startup without making the app idle while ScreenCaptureKit may
    /// still be inside startCapture(). The startup task's cancellation handler
    /// is the sole owner of recorder stop + final cleanup.
    private func beginDeferredStartCancellation(preserveCameraCurtain: Bool) {
        guard isStarting else { return }
        deferredStartCancellation = true
        if preserveCameraCurtain {
            bubble.showSafetyCurtain()
        } else {
            bubble.hide()
        }
        activeControls?.hideControls()
        phase = .saving
        startTask?.cancel()
    }

    private func unwindCancelledStart() async {
        _ = try? await recorder.stop()
        guard deferredStartCancellation else { return }
        deferredStartCancellation = false
        finishStartingRecording()
        showIdleRegionOverlayIfNeeded()
    }

    private func finishStartingRecording() {
        deferredStartCancellation = false
        startTask = nil
        activeControls?.hideControls()
        activeControls = nil
        phase = .idle
        bubble.hide()
        regionOverlay.hide()
        zoom.stop()
        teleprompter.hide()
        unregisterZoomHotkey()
        unregisterFormatHotkey()
        unregisterTeleprompterHotkey()
    }

    /// Cycle Screen → Screen+Camera → Camera, applied live during recording.
    func cycleFormat() {
        guard isActive else { return }
        // Camera transitions are atomic: wait for the in-flight first-frame
        // preflight instead of starting overlapping AVCaptureSession work.
        guard formatTransitionTask == nil else { return }
        let nextFormat = currentFormat.next
        if nextFormat.usesCamera, cameraInputAvailability != .available {
            if let issue = cameraIssue(for: cameraInputAvailability, permissionRequiredWhenRequestable: true) {
                captureInputIssues.removeAll(where: \.isCameraIssue)
                captureInputIssues.append(issue)
            }
            return
        }
        if nextFormat == .screenOnly {
            cancelFormatTransition()
            currentFormat = .screenOnly
            activeControls?.setFormat(.screenOnly)
            // Hide and relinquish the capture session synchronously with the
            // user's format change; stopRunning itself remains off-main-thread.
            bubble.hide()
            return
        }

        formatTransitionGeneration &+= 1
        let generation = formatTransitionGeneration
        formatTransitionTarget = nextFormat
        formatTransitionTask = Task { [weak self] in
            guard let self else { return }
            let cameraReady = await self.bubble.apply(
                format: nextFormat,
                deviceID: self.options.cameraDeviceID,
                region: self.options.captureRegion
            )
            guard !Task.isCancelled, generation == self.formatTransitionGeneration else { return }
            self.formatTransitionTask = nil
            self.formatTransitionTarget = nil

            if cameraReady {
                self.currentFormat = nextFormat
                self.activeControls?.setFormat(nextFormat)
                return
            }

            self.reportCameraUnavailable()
            if nextFormat == .cameraOnly {
                // A failed camera-only transition must not continue saving the
                // desktop beneath an absent full-frame camera presentation.
                self.bubble.showSafetyCurtain()
                self.stopRecording(preserveCameraCurtain: true)
                return
            }

            // Screen + Camera can safely remain Screen Only on camera failure.
            self.currentFormat = .screenOnly
            self.activeControls?.setFormat(.screenOnly)
            self.bubble.hide()
        }
    }

    private func cancelFormatTransition() {
        formatTransitionGeneration &+= 1
        formatTransitionTask?.cancel()
        formatTransitionTask = nil
        formatTransitionTarget = nil
    }

    private func reportCameraUnavailable() {
        captureInputIssues.removeAll(where: \.isCameraIssue)
        captureInputIssues.append(.cameraUnavailable)
    }

    /// Fail closed if a live camera session is interrupted or reports a runtime
    /// error. Screen + Camera may safely continue without the bubble, while a
    /// camera-only recording must stop before it can expose the desktop.
    private func handleCameraCaptureFailure() {
        reportCameraUnavailable()
        if isStarting {
            // Do not attempt to rewrite options while recorder.start may have
            // taken its snapshot. Cancel atomically; camera-only keeps the full
            // black curtain until the cancelled task has stopped capture.
            beginDeferredStartCancellation(preserveCameraCurtain: currentFormat == .cameraOnly)
            return
        }
        guard isActive else { return }

        let failedFormat = formatTransitionTarget ?? currentFormat
        cancelFormatTransition()
        if failedFormat == .cameraOnly {
            bubble.showSafetyCurtain()
            stopRecording(preserveCameraCurtain: true)
            return
        }

        if failedFormat == .screenAndCamera {
            currentFormat = .screenOnly
            activeControls?.setFormat(.screenOnly)
            bubble.hide()
        }
    }

    private func stopRecording(preserveCameraCurtain: Bool = false) {
        if isStarting {
            cancelStartingRecording()
            return
        }
        // Guard against double-clicks (popover + floating controls both fire).
        guard !isStopping, isActive else { return }
        isStopping = true

        cancelFormatTransition()
        activeControls?.hideControls()
        regionOverlay.hide()
        let keepCurtainUntilCaptureStops = preserveCameraCurtain || currentFormat == .cameraOnly
        if keepCurtainUntilCaptureStops {
            bubble.showSafetyCurtain()
        } else {
            bubble.hide()
        }
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
                self.bubble.hide()
                self.isStopping = false
                self.phase = .idle
                self.refreshRecordings()
                self.showIdleRegionOverlayIfNeeded()
            } catch {
                self.bubble.hide()
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

    // MARK: - Optional capture inputs

    var cameraInputAvailability: OptionalInputAvailability {
        inputAvailability(
            authorization: cameraAuthorizationStatus,
            hasSelectedDevice: hasSelectedCamera
        )
    }

    var microphoneInputAvailability: OptionalInputAvailability {
        inputAvailability(
            authorization: microphoneAuthorizationStatus,
            hasSelectedDevice: hasSelectedMicrophone
        )
    }

    var canSelectCamera: Bool {
        switch cameraAuthorizationStatus {
        case .denied, .restricted:
            return false
        case .authorized, .notDetermined:
            return hasAnyCamera
        @unknown default:
            return false
        }
    }

    var canSelectMicrophone: Bool {
        switch microphoneAuthorizationStatus {
        case .denied, .restricted:
            return false
        case .authorized, .notDetermined:
            return hasAnyMicrophone
        @unknown default:
            return false
        }
    }

    /// Re-check after returning from System Settings or connecting a device.
    func refreshOptionalInputAvailability() {
        devices.refresh()
        refreshAuthorizationStatuses()
        captureInputIssues.removeAll { issue in
            switch issue {
            case .cameraPermissionRequired:
                return cameraAuthorizationStatus == .authorized
            case .cameraDenied:
                return cameraAuthorizationStatus != .denied
            case .cameraRestricted:
                return cameraAuthorizationStatus != .restricted
            case .cameraUnavailable:
                return false
            case .microphonePermissionRequired:
                return microphoneAuthorizationStatus == .authorized
            case .microphoneDenied:
                return microphoneAuthorizationStatus != .denied
            case .microphoneRestricted:
                return microphoneAuthorizationStatus != .restricted
            case .microphoneUnavailable:
                return false
            }
        }
    }

    func dismissCaptureInputIssues() {
        captureInputIssues = []
    }

    func openCameraPrivacySettings() {
        openPrivacySettings(pane: "Privacy_Camera")
    }

    func openMicrophonePrivacySettings() {
        openPrivacySettings(pane: "Privacy_Microphone")
    }

    private var hasSelectedCamera: Bool {
        if let id = options.cameraDeviceID {
            return AVCaptureDevice(uniqueID: id) != nil
        }
        return AVCaptureDevice.default(for: .video) != nil || !devices.cameras.isEmpty
    }

    private var hasAnyCamera: Bool {
        AVCaptureDevice.default(for: .video) != nil || !devices.cameras.isEmpty
    }

    private var hasSelectedMicrophone: Bool {
        if let id = options.microphone.deviceID {
            return AVCaptureDevice(uniqueID: id) != nil
        }
        return AVCaptureDevice.default(for: .audio) != nil || !devices.microphones.isEmpty
    }

    private var hasAnyMicrophone: Bool {
        AVCaptureDevice.default(for: .audio) != nil || !devices.microphones.isEmpty
    }

    private func refreshAuthorizationStatuses() {
        cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        microphoneAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    private func inputAvailability(
        authorization: AVAuthorizationStatus,
        hasSelectedDevice: Bool
    ) -> OptionalInputAvailability {
        switch authorization {
        case .authorized:
            return hasSelectedDevice ? .available : .unavailable
        case .notDetermined:
            return hasSelectedDevice ? .requestable : .unavailable
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .restricted
        }
    }

    private func cameraIssue(
        for availability: OptionalInputAvailability,
        permissionRequiredWhenRequestable: Bool = false
    ) -> CaptureInputIssue? {
        switch availability {
        case .available: return nil
        case .requestable: return permissionRequiredWhenRequestable ? .cameraPermissionRequired : nil
        case .denied: return .cameraDenied
        case .restricted: return .cameraRestricted
        case .unavailable: return .cameraUnavailable
        }
    }

    private func microphoneIssue(
        for availability: OptionalInputAvailability,
        permissionRequiredWhenRequestable: Bool = false
    ) -> CaptureInputIssue? {
        switch availability {
        case .available: return nil
        case .requestable: return permissionRequiredWhenRequestable ? .microphonePermissionRequired : nil
        case .denied: return .microphoneDenied
        case .restricted: return .microphoneRestricted
        case .unavailable: return .microphoneUnavailable
        }
    }

    private func openPrivacySettings(pane: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Upload (on-demand, background)

    /// Stop presenting a saved link as fresh after its advertised one-day
    /// window. Physical lifecycle deletion can complete during the next day.
    func uploadState(for url: URL) -> UploadState {
        let state = uploads[url.path] ?? .idle
        if case .done(_, let at) = state, Date().timeIntervalSince(at) > Self.rememberedLinkLifetime {
            return .idle
        }
        return state
    }

    /// Upload a recording to the optional service and produce a temporary link.
    /// Non-blocking: runs on its own URLSession so it never interferes with
    /// recording. The link is copied to the clipboard on success.
    func uploadRecording(_ url: URL) {
        let path = url.path
        if case .uploading = uploads[path] { return }  // already in flight
        guard UploadConfig.isUploadConfigured else {
            uploads[path] = .failed(UploadError.uploadNotConfigured.localizedDescription)
            return
        }
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

    func openPrivacyPolicy() {
        if let url = ProductLinks.privacyURL { NSWorkspace.shared.open(url) }
    }

    func openSupport() {
        if let url = ProductLinks.supportURL { NSWorkspace.shared.open(url) }
    }

    private struct PersistedUpload: Codable {
        let url: URL
        let at: Date
    }

    private func persistUploads() {
        var store: [String: PersistedUpload] = [:]
        for (path, state) in uploads {
            if case .done(let url, let at) = state,
               Date().timeIntervalSince(at) <= Self.rememberedLinkLifetime {
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
        for (path, item) in store where now.timeIntervalSince(item.at) <= Self.rememberedLinkLifetime {
            uploads[path] = .done(url: item.url, at: item.at)
        }
    }

    private func issueNote(for recording: URL, link: URL, sharedAt: Date) -> String {
        let deletionStartsAt = sharedAt.addingTimeInterval(Self.rememberedLinkLifetime)
        let deletionExpectedBy = sharedAt.addingTimeInterval(Self.maximumDeletionWindow)
        let dateFormatter = ISO8601DateFormatter()
        let createdAt = (try? recording.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        let bytes = (try? recording.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return """
        ### Temporary screencast

        \(link.absoluteString)

        Deletion window: \(dateFormatter.string(from: deletionStartsAt)) to \(dateFormatter.string(from: deletionExpectedBy))
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

    // MARK: - Recording hotkeys

    private func registerZoomHotkey() {
        guard zoomHotkeyID == nil else { return }
        zoomHotkeyID = hotkey.register(
            keyCode: UInt32(kVK_ANSI_Z),
            modifiers: UInt32(cmdKey) | UInt32(shiftKey),
            onPressed: { [weak self] in
                self?.zoom.zoomIn()
                self?.activeControls?.setZoomActive(true)
            },
            onReleased: { [weak self] in
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
