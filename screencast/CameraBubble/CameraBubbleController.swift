import AppKit
import AVFoundation
import OSLog

@MainActor
final class CameraBubbleController {
    private var window: NSPanel?
    private var session: AVCaptureSession?
    private var currentDeviceID: String?
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
    func apply(format: CaptureFormat, deviceID: String? = nil, region: CGRect? = nil) async {
        currentRegion = region
        guard format.usesCamera else {
            window?.orderOut(nil)
            return
        }
        if window == nil { buildWindow() }
        await ensureRunning(deviceID: deviceID)
        guard let window, let host = window.contentView as? CameraBubbleView else { return }

        switch format {
        case .screenAndCamera:
            host.circular = true
            host.layer?.borderWidth = 3
            window.ignoresMouseEvents = false
            window.setFrame(bubbleFrame(region: region), display: true)
        case .cameraOnly:
            host.circular = false
            host.layer?.borderWidth = 0
            window.ignoresMouseEvents = true
            window.setFrame(fillFrame(region: region), display: true)
        case .screenOnly:
            break  // handled by the guard above
        }
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        window.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
        bubbleScale = 1
        if let session, session.isRunning {
            Task.detached { [session] in session.stopRunning() }
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

    private func ensureRunning(deviceID: String?) async {
        guard let host = window?.contentView as? CameraBubbleView else { return }

        let resolved: AVCaptureDevice?
        if let deviceID, let device = AVCaptureDevice(uniqueID: deviceID) {
            resolved = device
        } else {
            resolved = AVCaptureDevice.default(for: .video)
        }

        // Reuse a session already running on the requested device.
        if let existing = session, currentDeviceID == resolved?.uniqueID {
            if !existing.isRunning { await Self.start(existing) }
            return
        }

        // Replace any existing session (device changed).
        if let existing = session {
            Task.detached { [existing] in existing.stopRunning() }
            host.previewLayer?.removeFromSuperlayer()
            host.previewLayer = nil
            self.session = nil
        }

        guard let device = resolved,
              let input = try? AVCaptureDeviceInput(device: device) else {
            log.error("No camera input available")
            return
        }

        let session = AVCaptureSession()
        session.sessionPreset = .high
        guard session.canAddInput(input) else {
            log.error("Cannot add camera input")
            return
        }
        session.addInput(input)

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = host.bounds
        host.layer?.addSublayer(preview)
        host.previewLayer = preview

        self.session = session
        self.currentDeviceID = device.uniqueID
        await Self.start(session)
    }

    /// Start the capture session off the main thread and return once it is
    /// running, plus a short buffer so the preview layer has a frame to show.
    private static func start(_ session: AVCaptureSession) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            Task.detached {
                session.startRunning()
                cont.resume()
            }
        }
        try? await Task.sleep(for: .milliseconds(200))
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
