import AppKit
import QuartzCore

@MainActor
final class RecordingControlsController {
    private var window: NSPanel?
    private var onStop: (() -> Void)?
    private var startedAt: Date?
    private var timer: Timer?
    private weak var timeLabel: NSTextField?

    func show(onStop: @escaping () -> Void) {
        self.onStop = onStop
        if window == nil {
            buildWindow()
        }
        startedAt = Date()
        startTimer()
        updateTime()
        window?.orderFrontRegardless()
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
    }

    @objc private func stopTapped() {
        onStop?()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateTime() }
        }
    }

    private func updateTime() {
        guard let startedAt else { return }
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        let mm = elapsed / 60
        let ss = elapsed % 60
        timeLabel?.stringValue = String(format: "%02d:%02d", mm, ss)
    }

    private func buildWindow() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 180, height: 44)
        let origin = NSPoint(x: visible.midX - size.width / 2,
                             y: visible.maxY - size.height - 16)
        let frame = NSRect(origin: origin, size: size)

        let panel = NonactivatingPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
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

        let stop = NSButton(frame: NSRect(x: 8, y: (size.height - 30) / 2, width: 30, height: 30))
        stop.isBordered = false
        let symbol = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop")
        stop.image = symbol?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 24, weight: .bold)
        )
        stop.contentTintColor = .systemRed
        stop.target = self
        stop.action = #selector(stopTapped)
        stop.toolTip = "Stop recording"
        bg.addSubview(stop)

        let label = NSTextField(labelWithString: "00:00")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        label.textColor = .labelColor
        label.frame = NSRect(x: 46, y: (size.height - 18) / 2, width: 70, height: 18)
        bg.addSubview(label)
        self.timeLabel = label

        let recDot = NSView(frame: NSRect(x: size.width - 24, y: (size.height - 10) / 2, width: 10, height: 10))
        recDot.wantsLayer = true
        recDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        recDot.layer?.cornerRadius = 5
        bg.addSubview(recDot)

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.25
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        recDot.layer?.add(pulse, forKey: "pulse")

        panel.contentView = bg
        self.window = panel
    }
}

private final class NonactivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
