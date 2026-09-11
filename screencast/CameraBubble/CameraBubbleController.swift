import AppKit
import AVFoundation
import CoreMedia
import OSLog

@MainActor
final class CameraBubbleController {
    var onCaptureFailure: (() -> Void)?

    private var window: NSPanel?
    private var captureSession: ManagedCameraCaptureSession?
    private var captureObservers: [NSObjectProtocol] = []
    private var currentDeviceID: String?
    private var applyGeneration = 0
    private let log = Logger(subsystem: "to.screencast.app", category: "CameraBubble")
    private let diameter: CGFloat = 160
    /// Bubble size multiplier toggled by double-clicking the bubble (1× / 2×).
    private var bubbleScale: CGFloat = 1
    /// Captured area of the current recording, used to keep the bubble in view.
    private var currentRegion: CGRect?

    /// Apply a filming format. Warms the camera (awaiting a live frame) when the
    /// format needs it, then sizes/styles the window: hidden, a bottom-right
    /// bubble, or filling the captured area. `region` is the captured area in
    /// display points (top-left origin) or nil for full screen.
    @discardableResult
    func apply(format: CaptureFormat, deviceID: String? = nil, region: CGRect? = nil) async -> Bool {
        applyGeneration &+= 1
        let generation = applyGeneration
        currentRegion = region
        guard format.usesCamera else {
            window?.orderOut(nil)
            await stopAndReleaseSession()
            return true
        }
        if window == nil { buildWindow() }
        let cameraReady = await ensureRunning(deviceID: deviceID, generation: generation)
        guard generation == applyGeneration else { return false }
        guard cameraReady else {
            window?.orderOut(nil)
            return false
        }
        guard let window, let host = window.contentView as? CameraBubbleView else {
            await stopAndReleaseSession()
            return false
        }

        switch format {
        case .screenAndCamera:
            host.circular = true
            host.layer?.borderWidth = 3
            host.layer?.backgroundColor = NSColor.clear.cgColor
            window.ignoresMouseEvents = false
            window.setFrame(bubbleFrame(region: region), display: true)
        case .cameraOnly:
            host.circular = false
            host.layer?.borderWidth = 0
            // Keep an opaque underlay beneath the preview so compositor gaps
            // or a late preview-layer teardown can never reveal the desktop.
            host.layer?.backgroundColor = NSColor.black.cgColor
            window.ignoresMouseEvents = true
            window.setFrame(fillFrame(region: region), display: true)
        case .screenOnly:
            break  // handled by the guard above
        }
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        window.orderFrontRegardless()
        return true
    }

    func hide() {
        applyGeneration &+= 1
        window?.orderOut(nil)
        (window?.contentView as? CameraBubbleView)?.layer?.backgroundColor = NSColor.clear.cgColor
        bubbleScale = 1
        detachSession()?.stop()
    }

    /// Replace a visible camera preview with a full-region opaque frame, detach
    /// the preview/session immediately, and leave the curtain up while the
    /// screen recorder stops. This prevents even a trailing desktop frame from
    /// being exposed when camera-only capture disappears.
    func showSafetyCurtain() {
        applyGeneration &+= 1
        let shouldPresent = window?.isVisible == true
        if shouldPresent, let window,
           let host = window.contentView as? CameraBubbleView {
            host.circular = false
            host.layer?.borderWidth = 0
            host.layer?.backgroundColor = NSColor.black.cgColor
            window.ignoresMouseEvents = true
            window.setFrame(fillFrame(region: currentRegion), display: true)
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
        }

        // removeCaptureObservers() runs inside detachSession() before the stop
        // is enqueued, so this intentional teardown cannot recurse via callbacks.
        detachSession()?.stop()
        if shouldPresent {
            window?.orderFrontRegardless()
        }
    }

    /// Toggle the bubble between 1× and 2×, resizing around its current center
    /// and keeping it inside the captured area. No-op outside bubble mode.
    func toggleBubbleSize() {
        guard let window, let host = window.contentView as? CameraBubbleView, host.circular else { return }
        bubbleScale = bubbleScale == 1 ? 2 : 1
        let side = diameter * bubbleScale
        let old = window.frame
        let center = NSPoint(x: old.midX, y: old.midY)
        let frame = NSRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        window.setFrame(clampToCaptureArea(frame), display: true)
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
    }

    /// Keep a frame within the captured area so the bubble stays in the recording.
    private func clampToCaptureArea(_ frame: NSRect) -> NSRect {
        let area = fillFrame(region: currentRegion)
        var f = frame
        if f.maxX > area.maxX { f.origin.x = area.maxX - f.width }
        if f.minX < area.minX { f.origin.x = area.minX }
        if f.maxY > area.maxY { f.origin.y = area.maxY - f.height }
        if f.minY < area.minY { f.origin.y = area.minY }
        return f
    }

    // MARK: - Window

    private func buildWindow() {
        let frame = NSRect(origin: .zero, size: NSSize(width: diameter, height: diameter))

        let panel = DraggablePanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.ignoresMouseEvents = false

        let host = CameraBubbleView(frame: NSRect(origin: .zero, size: frame.size))
        host.wantsLayer = true
        host.layer?.masksToBounds = true
        host.layer?.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
        host.layer?.borderWidth = 3
        host.onDoubleClick = { [weak self] in self?.toggleBubbleSize() }
        panel.contentView = host
        self.window = panel
    }

    private func bubbleFrame(region: CGRect?) -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let side = diameter * bubbleScale
        let size = NSSize(width: side, height: side)
        if let region, let screen {
            let inset: CGFloat = 24
            let f = screen.frame
            return NSRect(x: f.minX + region.maxX - size.width - inset,
                          y: f.maxY - region.maxY + inset,
                          width: size.width, height: size.height)
        }
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(x: visible.maxX - size.width - 32, y: visible.minY + 32,
                      width: size.width, height: size.height)
    }

    /// Frame that fills the captured area (region or whole display).
    private func fillFrame(region: CGRect?) -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let f = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if let region {
            return NSRect(x: f.minX + region.minX, y: f.maxY - region.maxY,
                          width: region.width, height: region.height)
        }
        return f
    }

    // MARK: - Capture session

    private func ensureRunning(deviceID: String?, generation: Int) async -> Bool {
        guard let host = window?.contentView as? CameraBubbleView else { return false }

        let resolved: AVCaptureDevice?
        if let deviceID, let device = AVCaptureDevice(uniqueID: deviceID) {
            resolved = device
        } else {
            resolved = AVCaptureDevice.default(for: .video)
        }

        // Reuse a healthy session already running on the requested device.
        if let existing = captureSession, currentDeviceID == resolved?.uniqueID {
            let started = await existing.start()
            guard generation == applyGeneration else { return false }
            guard started else {
                log.error("Camera capture session did not start")
                await stopAndReleaseSession()
                return false
            }
            let ready = await waitForFirstFrame(from: existing, generation: generation)
            guard generation == applyGeneration else { return false }
            if !ready {
                log.error("Camera capture session produced no video frame")
                await stopAndReleaseSession()
            }
            return ready
        }

        // Replace any existing session (device changed).
        await stopAndReleaseSession()
        guard generation == applyGeneration, !Task.isCancelled else { return false }

        guard let device = resolved else {
            log.error("No camera input available")
            return false
        }

        // A running AVCaptureSession is not enough to prove that the selected
        // camera is actually delivering video. Observe its first sample buffer
        // and do not expose the preview (or start recording) until one arrives.
        let captureSession = ManagedCameraCaptureSession()
        guard await captureSession.configure(deviceID: device.uniqueID) else {
            log.error("Cannot configure camera capture")
            return false
        }
        guard generation == applyGeneration else { return false }

        let preview = AVCaptureVideoPreviewLayer(session: captureSession.session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = host.bounds
        host.layer?.addSublayer(preview)
        host.previewLayer = preview

        self.captureSession = captureSession
        self.currentDeviceID = device.uniqueID
        observeUnexpectedFailure(of: captureSession)
        let started = await captureSession.start()
        guard generation == applyGeneration else { return false }
        guard started else {
            log.error("Camera capture session did not start")
            await stopAndReleaseSession()
            return false
        }

        let ready = await waitForFirstFrame(from: captureSession, generation: generation)
        guard generation == applyGeneration else { return false }
        if !ready {
            log.error("Camera capture session produced no video frame")
            await stopAndReleaseSession()
        }
        return ready
    }

    /// Wait at most three seconds for an actual camera frame. Polling the
    /// thread-safe probe keeps cancellation responsive without retaining an
    /// unresumed continuation when a camera disappears mid-start.
    private func waitForFirstFrame(
        from captureSession: ManagedCameraCaptureSession,
        generation: Int
    ) async -> Bool {
        for _ in 0..<60 {
            guard generation == applyGeneration, !Task.isCancelled else { return false }
            if captureSession.hasReceivedFrame {
                let running = await captureSession.isRunning()
                guard generation == applyGeneration, running else { return false }
                await captureSession.finishReadinessProbe()
                return generation == applyGeneration
            }
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return false
            }
        }
        guard generation == applyGeneration, captureSession.hasReceivedFrame else { return false }
        guard await captureSession.isRunning(), generation == applyGeneration else { return false }
        await captureSession.finishReadinessProbe()
        return generation == applyGeneration
    }

    /// Drop all controller/UI references synchronously, then stop the detached
    /// session off the main actor. This prevents a hidden camera from remaining
    /// owned when the format switches to Screen Only.
    private func detachSession() -> ManagedCameraCaptureSession? {
        let detached = captureSession
        removeCaptureObservers()
        captureSession = nil
        currentDeviceID = nil

        if let host = window?.contentView as? CameraBubbleView {
            host.previewLayer?.removeFromSuperlayer()
            host.previewLayer = nil
        }
        return detached
    }

    private func observeUnexpectedFailure(of captureSession: ManagedCameraCaptureSession) {
        removeCaptureObservers()
        let sessionID = ObjectIdentifier(captureSession)
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            AVCaptureSession.runtimeErrorNotification,
            AVCaptureSession.wasInterruptedNotification,
        ]
        captureObservers = names.map { name in
            center.addObserver(
                forName: name,
                object: captureSession.session,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleUnexpectedCaptureFailure(sessionID: sessionID)
                }
            }
        }
    }

    private func removeCaptureObservers() {
        let center = NotificationCenter.default
        captureObservers.forEach(center.removeObserver)
        captureObservers = []
    }

    private func handleUnexpectedCaptureFailure(sessionID: ObjectIdentifier) {
        guard let captureSession,
              ObjectIdentifier(captureSession) == sessionID else { return }
        showSafetyCurtain()
        onCaptureFailure?()
    }

    private func stopAndReleaseSession() async {
        guard let captureSession = detachSession() else { return }
        await captureSession.stopAndWait()
    }
}

/// Owns every blocking AVCaptureSession operation on one serial queue. This
/// prevents rapid format changes from overlapping startRunning and stopRunning.
private nonisolated final class ManagedCameraCaptureSession: @unchecked Sendable {
    /// Shared across session instances so an old session's queued stop always
    /// runs before a newly selected session's configure/start operations.
    private static let sessionQueue = DispatchQueue(label: "to.screencast.app.camera-session")

    let session = AVCaptureSession()

    private let frameOutput = AVCaptureVideoDataOutput()
    private let frameProbe = CameraReadinessProbe()
    private let outputQueue = DispatchQueue(label: "to.screencast.app.camera-readiness")

    var hasReceivedFrame: Bool { frameProbe.hasReceivedFrame }

    func configure(deviceID: String) async -> Bool {
        await withCheckedContinuation { continuation in
            Self.sessionQueue.async { [self] in
                guard let device = AVCaptureDevice(uniqueID: deviceID) else {
                    continuation.resume(returning: false)
                    return
                }
                guard let input = try? AVCaptureDeviceInput(device: device) else {
                    continuation.resume(returning: false)
                    return
                }

                session.beginConfiguration()
                session.sessionPreset = .high
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    continuation.resume(returning: false)
                    return
                }
                session.addInput(input)

                frameOutput.alwaysDiscardsLateVideoFrames = true
                frameOutput.setSampleBufferDelegate(frameProbe, queue: outputQueue)
                guard session.canAddOutput(frameOutput) else {
                    session.commitConfiguration()
                    frameOutput.setSampleBufferDelegate(nil, queue: nil)
                    continuation.resume(returning: false)
                    return
                }
                session.addOutput(frameOutput)
                session.commitConfiguration()
                continuation.resume(returning: true)
            }
        }
    }

    func start() async -> Bool {
        await withCheckedContinuation { continuation in
            Self.sessionQueue.async { [self] in
                if !session.isRunning {
                    frameProbe.reset()
                    session.startRunning()
                }
                continuation.resume(returning: session.isRunning)
            }
        }
    }

    func isRunning() async -> Bool {
        await withCheckedContinuation { continuation in
            Self.sessionQueue.async { [self] in
                continuation.resume(returning: session.isRunning)
            }
        }
    }

    /// Once readiness is established, remove the data output so it does not
    /// keep converting full-resolution frames for the rest of the recording.
    func finishReadinessProbe() async {
        await withCheckedContinuation { continuation in
            Self.sessionQueue.async { [self] in
                guard session.outputs.contains(where: { $0 === frameOutput }) else {
                    continuation.resume()
                    return
                }
                session.beginConfiguration()
                session.removeOutput(frameOutput)
                session.commitConfiguration()
                frameOutput.setSampleBufferDelegate(nil, queue: nil)
                continuation.resume()
            }
        }
    }

    /// Enqueue a stop synchronously so callers can release their reference
    /// immediately without blocking AppKit's main actor.
    func stop() {
        Self.sessionQueue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
            frameOutput.setSampleBufferDelegate(nil, queue: nil)
        }
    }

    func stopAndWait() async {
        await withCheckedContinuation { continuation in
            Self.sessionQueue.async { [self] in
                if session.isRunning {
                    session.stopRunning()
                }
                frameOutput.setSampleBufferDelegate(nil, queue: nil)
                continuation.resume()
            }
        }
    }
}

/// Receives camera frames on AVFoundation's output queue and exposes only a
/// lock-protected readiness bit to the main-actor controller.
private nonisolated final class CameraReadinessProbe: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var receivedFrame = false

    var hasReceivedFrame: Bool {
        lock.lock()
        defer { lock.unlock() }
        return receivedFrame
    }

    func reset() {
        lock.lock()
        receivedFrame = false
        lock.unlock()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        lock.lock()
        receivedFrame = true
        lock.unlock()
    }
}

private final class CameraBubbleView: NSView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    /// Round the view into a circle (bubble) vs fill rectangularly (camera-only).
    var circular: Bool = true
    var onDoubleClick: (() -> Void)?

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
        layer?.cornerRadius = circular ? bounds.width / 2 : 0
    }

    // Double-click toggles the bubble size; a single click-drag moves it.
    // Only in bubble mode (camera-only fills the screen and ignores clicks).
    override func mouseDown(with event: NSEvent) {
        guard circular else { return }
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        if circular {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}

private final class DraggablePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
