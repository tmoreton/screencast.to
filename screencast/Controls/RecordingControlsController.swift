import AppKit

/// The standalone recording pill (used when the teleprompter is off). Hosts a
/// `RecordingControlBar` inside a floating capsule excluded from capture.
@MainActor
final class RecordingControlsController: RecordingControlsHost {
    private var window: NSPanel?
    private var bar: RecordingControlBar?

    func showControls(
        onStop: @escaping () -> Void,
        onPauseResume: @escaping () -> Void,
        onCycleFormat: @escaping () -> Void
    ) {
        if window == nil { buildWindow() }
        bar?.onStop = onStop
        bar?.onPauseResume = onPauseResume
        bar?.onCycleFormat = onCycleFormat
        bar?.begin()
        window?.orderFrontRegardless()
    }

    func hideControls() {
        bar?.end()
        window?.orderOut(nil)
    }

    func setPaused(_ paused: Bool) { bar?.setPaused(paused) }
    func setFormat(_ format: CaptureFormat) { bar?.setFormat(format) }
    func setZoomActive(_ active: Bool) { bar?.setZoomActive(active) }

    private func buildWindow() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = RecordingControlBar.contentSize
        let origin = NSPoint(x: visible.midX - size.width / 2,
                             y: visible.maxY - size.height - 16)
        let frame = NSRect(origin: origin, size: size)

        let panel = NonactivatingPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Above the camera-fill window so the controls stay clickable.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.sharingType = .none  // exclude from screen capture
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true

        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = size.height / 2
        bg.layer?.masksToBounds = true

        let bar = RecordingControlBar(frame: NSRect(origin: .zero, size: size))
        bg.addSubview(bar)

        panel.contentView = bg
        self.window = panel
        self.bar = bar
    }
}

final class NonactivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
