import AppKit
@preconcurrency import AVFoundation
import CoreMedia
import OSLog

@MainActor
final class CameraBubbleController {
    var onCaptureFailure: (() -> Void)?

    private var window: NSPanel?
    private var captureSession: ManagedCameraCaptureSession?
    private var captureObservers: [NSObjectProtocol] = []
    private var currentDeviceID: String?
    private var presenterProcessor: PresenterFrameProcessor?
    private var currentFormat: CaptureFormat = .screenOnly
    private var applyGeneration = 0
    private let log = Logger(subsystem: "to.screencast.app", category: "CameraBubble")
    private let diameter: CGFloat = 160
    /// Bubble size multiplier toggled by double-clicking the bubble (1× / 2×).
    private var bubbleScale: CGFloat = 1
    /// Captured area of the current recording, used to keep the bubble in view.
    private var currentRegion: CGRect?

    /// Apply a filming format. Warms the camera (awaiting a live frame) when the
    /// format needs it, then sizes/styles the window: hidden, a bottom-right
    /// bubble, a fixed presenter cutout, or filling the captured area. `region`
    /// is the captured area in display points (top-left origin) or nil for full screen.
    @discardableResult
    func apply(format: CaptureFormat, deviceID: String? = nil, region: CGRect? = nil) async -> Bool {
        applyGeneration &+= 1
        let generation = applyGeneration
        currentFormat = format
        currentRegion = region
        presenterProcessor?.setActive(generation: nil)
        (window?.contentView as? CameraBubbleView)?.presenterImage = nil
        guard format.usesCamera else {
            window?.orderOut(nil)
            await stopAndReleaseSession()
            return true
        }
        if window == nil { buildWindow() }
        if format == .presenter {
            // Never expose an unsegmented camera frame while Presenter warms up.
            (window?.contentView as? CameraBubbleView)?.previewLayer?.isHidden = true
            presenterProcessor?.setActive(generation: UInt64(truncatingIfNeeded: generation))
        }
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

        host.presenterLayer.isHidden = format != .presenter
        host.previewLayer?.isHidden = format == .presenter
        window.hasShadow = format == .screenAndCamera
        window.isMovableByWindowBackground = format == .screenAndCamera
        switch format {
        case .screenAndCamera:
            host.circular = true
            host.layer?.borderWidth = 3
            host.layer?.backgroundColor = NSColor.clear.cgColor
            window.ignoresMouseEvents = false
            window.setFrame(bubbleFrame(region: region), display: true)
        case .presenter:
            host.circular = false
            host.layer?.borderWidth = 0
            host.layer?.backgroundColor = NSColor.clear.cgColor
            window.ignoresMouseEvents = true
            window.setFrame(fillFrame(region: region), display: true)
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
        currentFormat = .screenOnly
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
        currentFormat = .screenOnly
        let shouldPresent = window?.isVisible == true
        if shouldPresent, let window,
           let host = window.contentView as? CameraBubbleView {
            host.circular = false
            host.layer?.borderWidth = 0
            host.layer?.backgroundColor = NSColor.black.cgColor
            window.hasShadow = false
            window.isMovableByWindowBackground = false
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
        presenterProcessor = PresenterFrameProcessor { [weak self] image, generation in
            guard let self, self.currentFormat == .presenter,
                  UInt64(truncatingIfNeeded: self.applyGeneration) == generation,
                  let host = self.window?.contentView as? CameraBubbleView else { return }
            host.presenterImage = image
            host.layoutSubtreeIfNeeded()
        }
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
            let started = await existing.start(presenterEnabled: currentFormat == .presenter)
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

        guard let device = resolved, let presenterProcessor else {
            log.error("No camera input available")
            return false
        }

        // A running AVCaptureSession is not enough to prove that the selected
        // camera is actually delivering video. Observe its first sample buffer
        // and do not expose the preview (or start recording) until one arrives.
        if currentFormat == .presenter {
            // Detaching the previous session also deactivates its processor.
            presenterProcessor.setActive(generation: UInt64(truncatingIfNeeded: generation))
        }
        let captureSession = ManagedCameraCaptureSession(presenterProcessor: presenterProcessor)
        guard await captureSession.configure(deviceID: device.uniqueID) else {
            log.error("Cannot configure camera capture")
            return false
        }
        guard generation == applyGeneration else { return false }

        let preview = AVCaptureVideoPreviewLayer(session: captureSession.session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = host.bounds
        preview.isHidden = currentFormat == .presenter
        host.layer?.insertSublayer(preview, at: 0)
        host.previewLayer = preview
        captureSession.setVideoMirrored(preview.connection?.isVideoMirrored ?? false)

        self.captureSession = captureSession
        self.currentDeviceID = device.uniqueID
        observeUnexpectedFailure(of: captureSession)
        let started = await captureSession.start(presenterEnabled: currentFormat == .presenter)
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
        detached?.disablePresenter()
        presenterProcessor?.setActive(generation: nil)
        removeCaptureObservers()
        captureSession = nil
        currentDeviceID = nil

        if let host = window?.contentView as? CameraBubbleView {
            host.presenterImage = nil
            host.presenterLayer.isHidden = true
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
    private let frameProbe: CameraReadinessProbe
    private let outputQueue: DispatchQueue
    /// Confined to sessionQueue. Readiness teardown must retain the output
    /// while the latest requested mode needs continuous foreground frames.
    private var presenterEnabled = false

    init(presenterProcessor: PresenterFrameProcessor) {
        frameProbe = CameraReadinessProbe(presenterProcessor: presenterProcessor)
        outputQueue = presenterProcessor.queue
    }

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

                frameOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
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

    func start(presenterEnabled: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            Self.sessionQueue.async { [self] in
                self.presenterEnabled = presenterEnabled
                frameProbe.setPresenterEnabled(presenterEnabled)
                // Readiness removes this output in preview-only modes. Restore
                // it for Presenter, or for a restarted session's fresh probe.
                if presenterEnabled || !session.isRunning {
                    guard attachFrameOutput() else {
                        continuation.resume(returning: false)
                        return
                    }
                }
                if !session.isRunning {
                    frameProbe.reset()
                    session.startRunning()
                }
                continuation.resume(returning: session.isRunning)
            }
        }
    }

    /// Close the forwarding gate synchronously before an old session is
    /// detached, so its queued samples cannot enter a newer mode's generation.
    func disablePresenter() {
        frameProbe.setPresenterEnabled(false)
    }

    func setVideoMirrored(_ mirrored: Bool) {
        Self.sessionQueue.async { [self] in
            guard let connection = frameOutput.connection(with: .video),
                  connection.isVideoMirroringSupported else { return }
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }

    func isRunning() async -> Bool {
        await withCheckedContinuation { continuation in
            Self.sessionQueue.async { [self] in
                continuation.resume(returning: session.isRunning)
            }
        }
    }

    /// Keep continuous samples only for Presenter. Other modes use the preview
    /// layer after readiness, avoiding full-resolution camera-buffer conversion.
    func finishReadinessProbe() async {
        await withCheckedContinuation { continuation in
            Self.sessionQueue.async { [self] in
                guard !presenterEnabled else {
                    continuation.resume()
                    return
                }
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
        disablePresenter()
        Self.sessionQueue.async { [self] in
            presenterEnabled = false
            if session.isRunning {
                session.stopRunning()
            }
            frameOutput.setSampleBufferDelegate(nil, queue: nil)
        }
    }

    func stopAndWait() async {
        disablePresenter()
        await withCheckedContinuation { continuation in
            Self.sessionQueue.async { [self] in
                presenterEnabled = false
                if session.isRunning {
                    session.stopRunning()
                }
                frameOutput.setSampleBufferDelegate(nil, queue: nil)
                continuation.resume()
            }
        }
    }

    /// Called only on sessionQueue, including when a preview-only session
    /// switches to Presenter after its first-frame output has been removed.
    private func attachFrameOutput() -> Bool {
        guard !session.outputs.contains(where: { $0 === frameOutput }) else { return true }
        frameOutput.setSampleBufferDelegate(frameProbe, queue: outputQueue)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddOutput(frameOutput) else {
            frameOutput.setSampleBufferDelegate(nil, queue: nil)
            return false
        }
        session.addOutput(frameOutput)
        return true
    }
}

/// Receives camera frames on AVFoundation's output queue and exposes only a
/// lock-protected readiness bit to the main-actor controller.
private nonisolated final class CameraReadinessProbe: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var receivedFrame = false
    private var presenterEnabled = false
    private let presenterProcessor: PresenterFrameProcessor

    init(presenterProcessor: PresenterFrameProcessor) {
        self.presenterProcessor = presenterProcessor
    }

    func setPresenterEnabled(_ enabled: Bool) {
        lock.lock()
        presenterEnabled = enabled
        lock.unlock()
    }

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
        let forwardToPresenter = presenterEnabled
        lock.unlock()
        if forwardToPresenter {
            // The data output uses the processor's serial queue, preserving its
            // Vision/request confinement while also proving camera readiness.
            presenterProcessor.captureOutput(output, didOutput: sampleBuffer, from: connection)
        }
    }
}

private final class CameraBubbleView: NSView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    let presenterLayer = CALayer()
    var presenterImage: CGImage? {
        didSet {
            presenterLayer.contents = presenterImage
            needsLayout = true
        }
    }
    /// Round the view into a circle (bubble) vs transparent/rectangular framing.
    var circular: Bool = true
    var onDoubleClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        presenterLayer.isOpaque = false
        presenterLayer.isHidden = true
        presenterLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(presenterLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
        if let image = presenterImage {
            presenterLayer.frame = PresenterLayout.imageFrame(
                imageSize: CGSize(width: image.width, height: image.height), in: bounds
            )
        }
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
