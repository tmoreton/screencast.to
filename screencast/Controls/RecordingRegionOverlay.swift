import AppKit
import QuartzCore

@MainActor
final class RecordingRegionOverlay {
    private var window: NSPanel?

    /// `rect` is in display points, top-left origin (same convention as
    /// `SCStreamConfiguration.sourceRect`).
    func show(rect: CGRect) {
        hide()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        // Convert top-left display coords → bottom-left AppKit coords.
        let appkitRect = NSRect(
            x: rect.minX,
            y: screen.frame.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )

        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.sharingType = .none  // exclude from screen capture
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = RegionOutlineView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.setTargetRect(appkitRect)
        panel.contentView = view

        self.window = panel
        panel.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

private final class RegionOutlineView: NSView {
    private let outerHalo = CAShapeLayer()
    private let border = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        // Soft white halo behind the red line so it's visible on any background.
        outerHalo.strokeColor = NSColor.white.withAlphaComponent(0.35).cgColor
        outerHalo.fillColor = nil
        outerHalo.lineWidth = 4
        layer?.addSublayer(outerHalo)

        border.strokeColor = NSColor.systemRed.cgColor
        border.fillColor = nil
        border.lineWidth = 2
        layer?.addSublayer(border)

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.45
        pulse.duration = 1.1
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        border.add(pulse, forKey: "pulse")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setTargetRect(_ rect: NSRect) {
        let path = CGPath(rect: rect.insetBy(dx: -1, dy: -1), transform: nil)
        border.path = path
        outerHalo.path = path
    }
}
