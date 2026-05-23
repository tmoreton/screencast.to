import AppKit
import QuartzCore

@MainActor
final class RecordingControlsController {
    private var window: NSPanel?
    private var onStop: (() -> Void)?
    private var onPauseResume: (() -> Void)?

    // Pause-aware elapsed timer. `accumulated` holds completed active spans;
    // `segmentStart` is non-nil only while actively recording.
    private var accumulated: TimeInterval = 0
    private var segmentStart: Date?
    private var timer: Timer?
    private var isPaused = false

    private weak var timeLabel: NSTextField?
    private weak var pauseButton: NSButton?
    private weak var recDot: NSView?

    func show(onStop: @escaping () -> Void, onPauseResume: @escaping () -> Void) {
        self.onStop = onStop
        self.onPauseResume = onPauseResume
        if window == nil {
            buildWindow()
        }
        accumulated = 0
        segmentStart = Date()
        isPaused = false
        applyPausedAppearance()
        startTimer()
        updateTime()
        window?.orderFrontRegardless()
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        segmentStart = nil
        accumulated = 0
    }

    /// Reflect the recording's paused state: freeze the timer and update visuals.
    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        if paused {
            if let segmentStart {
                accumulated += Date().timeIntervalSince(segmentStart)
            }
            segmentStart = nil
        } else {
            segmentStart = Date()
        }
        applyPausedAppearance()
        updateTime()
    }

    @objc private func stopTapped() {
        onStop?()
    }

    @objc private func pauseTapped() {
        onPauseResume?()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.updateTime() }
        }
    }

    private func updateTime() {
        let active = accumulated + (segmentStart.map { Date().timeIntervalSince($0) } ?? 0)
        let elapsed = Int(active)
        let mm = elapsed / 60
        let ss = elapsed % 60
        timeLabel?.stringValue = String(format: "%02d:%02d", mm, ss)
    }

    private func applyPausedAppearance() {
        let symbolName = isPaused ? "play.fill" : "pause.fill"
        let tooltip = isPaused ? "Resume recording" : "Pause recording"
        pauseButton?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .bold))
        pauseButton?.toolTip = tooltip

        guard let recDot else { return }
        if isPaused {
            recDot.layer?.removeAnimation(forKey: "pulse")
            recDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
            recDot.layer?.opacity = 1.0
        } else {
            recDot.layer?.backgroundColor = NSColor.systemRed.cgColor
            addPulse(to: recDot)
        }
    }

    private func addPulse(to view: NSView) {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.25
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        view.layer?.add(pulse, forKey: "pulse")
    }

    private func buildWindow() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 210, height: 44)
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
        stop.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 24, weight: .bold))
        stop.contentTintColor = .systemRed
        stop.target = self
        stop.action = #selector(stopTapped)
        stop.toolTip = "Stop recording"
        bg.addSubview(stop)

        let pause = NSButton(frame: NSRect(x: 42, y: (size.height - 28) / 2, width: 28, height: 28))
        pause.isBordered = false
        pause.bezelStyle = .regularSquare
        pause.wantsLayer = true
        pause.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        pause.layer?.cornerRadius = 14
        pause.contentTintColor = .labelColor
        pause.target = self
        pause.action = #selector(pauseTapped)
        bg.addSubview(pause)
        self.pauseButton = pause

        let label = NSTextField(labelWithString: "00:00")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        label.textColor = .labelColor
        label.frame = NSRect(x: 78, y: (size.height - 18) / 2, width: 70, height: 18)
        bg.addSubview(label)
        self.timeLabel = label

        let dot = NSView(frame: NSRect(x: size.width - 24, y: (size.height - 10) / 2, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 5
        bg.addSubview(dot)
        self.recDot = dot

        panel.contentView = bg
        self.window = panel
    }
}

private final class NonactivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
