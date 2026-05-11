import AppKit
import AVFoundation
import OSLog

@MainActor
final class CameraBubbleController {
    private var window: NSPanel?
    private var session: AVCaptureSession?
    private var currentDeviceID: String?
    private let log = Logger(subsystem: "com.tmoreton.notloom-opus", category: "CameraBubble")
    private let diameter: CGFloat = 160

    func show(deviceID: String? = nil) {
        if window == nil {
            buildWindow()
        }
        startSession(deviceID: deviceID)
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
        if let session, session.isRunning {
            Task.detached { [session] in
                session.stopRunning()
            }
        }
    }

    private func buildWindow() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: visible.maxX - diameter - 32,
                             y: visible.minY + 32)
        let frame = NSRect(origin: origin, size: NSSize(width: diameter, height: diameter))

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
        host.layer?.cornerRadius = diameter / 2
        host.layer?.masksToBounds = true
        host.layer?.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
        host.layer?.borderWidth = 3
        panel.contentView = host
        self.window = panel
    }

    private func startSession(deviceID: String?) {
        guard let host = window?.contentView as? CameraBubbleView else { return }

        let resolved: AVCaptureDevice?
        if let deviceID,
           let device = AVCaptureDevice(uniqueID: deviceID) {
            resolved = device
        } else {
            resolved = AVCaptureDevice.default(for: .video)
        }

        // If we already have a session running on the requested device, no-op.
        if let existing = session, currentDeviceID == resolved?.uniqueID {
            if !existing.isRunning {
                Task.detached { [existing] in existing.startRunning() }
            }
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
        session.sessionPreset = .medium
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
        Task.detached { [session] in session.startRunning() }
    }
}

private final class CameraBubbleView: NSView {
    var previewLayer: AVCaptureVideoPreviewLayer?

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
        layer?.cornerRadius = bounds.width / 2
    }

    // Drag the bubble window from any point on the bubble's surface,
    // even while a recording is in progress.
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

private final class DraggablePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
