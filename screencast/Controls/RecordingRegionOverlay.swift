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
    /// Dims everything outside the recorded region so the captured area is
    /// obvious at a glance.
    private let dimLayer = CAShapeLayer()
    private let outerHalo = CAShapeLayer()
    private let border = CAShapeLayer()
    private let badge = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.45).cgColor
        dimLayer.fillRule = .evenOdd
        layer?.addSublayer(dimLayer)

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

        badge.attributedStringValue = Self.badgeText()
        badge.drawsBackground = true
        badge.backgroundColor = NSColor.black.withAlphaComponent(0.7)
        badge.isBezeled = false
        badge.isEditable = false
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 5
        badge.layer?.masksToBounds = true
        badge.alignment = .center
        addSubview(badge)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setTargetRect(_ rect: NSRect) {
        let outline = rect.insetBy(dx: -1, dy: -1)
        let path = CGPath(rect: outline, transform: nil)
        border.path = path
        outerHalo.path = path

        // Even-odd path of (whole screen) + (region) fills only the surround.
        let mask = CGMutablePath()
        mask.addRect(bounds)
        mask.addRect(rect)
        dimLayer.path = mask

        // Badge sits just above the region (or just inside if near the top).
        badge.sizeToFit()
        let bw = badge.frame.width + 14
        let bh = badge.frame.height + 6
        var by = rect.maxY + 6
        if by + bh > bounds.maxY { by = rect.maxY - bh - 6 }
        badge.frame = NSRect(x: rect.minX, y: by, width: bw, height: bh)
    }

    private static func badgeText() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let dot = NSAttributedString(string: "● ", attributes: [
            .foregroundColor: NSColor.systemRed,
            .font: NSFont.systemFont(ofSize: 11, weight: .bold)
        ])
        let label = NSAttributedString(string: "REC · recording this area", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
        ])
        result.append(dot)
        result.append(label)
        return result
    }
}
