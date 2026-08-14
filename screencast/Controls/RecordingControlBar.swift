import AppKit
import QuartzCore

/// The recording controls (stop / pause / format / elapsed time / zoom badge /
/// rec dot) as a reusable fixed-size view. Hosted by the standalone pill and,
/// when the teleprompter is in use, embedded in the teleprompter's header so
/// everything reads as one unit.
@MainActor
protocol RecordingControlsHost: AnyObject {
    func showControls(onStop: @escaping () -> Void,
                      onPauseResume: @escaping () -> Void,
                      onCycleFormat: @escaping () -> Void)
    func hideControls()
    func beginCountdown(seconds: Int)
    func updateCountdown(seconds: Int)
    func beginRecording()
    func setPaused(_ paused: Bool)
    func setFormat(_ format: CaptureFormat)
    func setZoomActive(_ active: Bool)
}

@MainActor
final class RecordingControlBar: NSView {
    static let contentSize = NSSize(width: 250, height: 44)

    var onStop: (() -> Void)?
    var onPauseResume: (() -> Void)?
    var onCycleFormat: (() -> Void)?

    // Pause-aware elapsed timer. `accumulated` holds completed active spans;
    // `segmentStart` is non-nil only while actively recording.
    private var accumulated: TimeInterval = 0
    private var segmentStart: Date?
    private var timer: Timer?
    private var isPaused = false
    private var isCountingDown = false

    private weak var timeLabel: NSTextField?
    private weak var stopButton: NSButton?
    private weak var pauseButton: NSButton?
    private weak var formatButton: NSButton?
    private weak var recDot: NSView?
    private weak var zoomBadge: NSImageView?

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: frameRect.origin, size: Self.contentSize))
        wantsLayer = true
        buildSubviews()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize { Self.contentSize }

    // MARK: - Lifecycle

    func beginCountdown(seconds: Int) {
        timer?.invalidate()
        timer = nil
        accumulated = 0
        segmentStart = nil
        isPaused = false
        isCountingDown = true
        zoomBadge?.isHidden = true

        stopButton?.toolTip = "Cancel recording"
        pauseButton?.isEnabled = false
        formatButton?.isEnabled = false
        pauseButton?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Countdown")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .bold))
        pauseButton?.toolTip = "Recording starts after countdown"
        timeLabel?.textColor = .systemYellow
        updateCountdown(seconds: seconds)

        if let recDot {
            recDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
            addPulse(to: recDot)
        }
    }

    func updateCountdown(seconds: Int) {
        timeLabel?.stringValue = String(format: "00:%02d", max(0, seconds))
    }

    func begin() {
        accumulated = 0
        segmentStart = Date()
        isPaused = false
        isCountingDown = false
        stopButton?.toolTip = "Stop recording"
        pauseButton?.isEnabled = true
        formatButton?.isEnabled = true
        timeLabel?.textColor = .labelColor
        zoomBadge?.isHidden = true
        applyPausedAppearance()
        startTimer()
        updateTime()
    }

    func end() {
        timer?.invalidate()
        timer = nil
        segmentStart = nil
        accumulated = 0
        isPaused = false
        isCountingDown = false
        stopButton?.toolTip = "Stop recording"
        pauseButton?.isEnabled = true
        formatButton?.isEnabled = true
        timeLabel?.textColor = .labelColor
        timeLabel?.stringValue = "00:00"
        zoomBadge?.isHidden = true
        recDot?.layer?.removeAnimation(forKey: "pulse")
    }

    func setZoomActive(_ active: Bool) {
        guard !isCountingDown else {
            zoomBadge?.isHidden = true
            return
        }
        zoomBadge?.isHidden = !active
    }

    func setFormat(_ format: CaptureFormat) {
        formatButton?.image = NSImage(systemSymbolName: format.symbol, accessibilityDescription: format.menuLabel)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
        formatButton?.toolTip = "\(format.menuLabel) — ⌘⇧C to switch"
    }

    func setPaused(_ paused: Bool) {
        guard !isCountingDown else { return }
        guard paused != isPaused else { return }
        isPaused = paused
        if paused {
            if let segmentStart { accumulated += Date().timeIntervalSince(segmentStart) }
            segmentStart = nil
        } else {
            segmentStart = Date()
        }
        applyPausedAppearance()
        updateTime()
    }

    // MARK: - Actions

    @objc private func stopTapped() { onStop?() }
    @objc private func pauseTapped() { onPauseResume?() }
    @objc private func formatTapped() { onCycleFormat?() }

    // MARK: - Timer

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
        timeLabel?.stringValue = String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
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

    // MARK: - Layout

    private func buildSubviews() {
        let h = Self.contentSize.height

        let stop = NSButton(frame: NSRect(x: 8, y: (h - 30) / 2, width: 30, height: 30))
        stop.isBordered = false
        stop.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 24, weight: .bold))
        stop.contentTintColor = .systemRed
        stop.target = self
        stop.action = #selector(stopTapped)
        stop.toolTip = "Stop recording"
        addSubview(stop)
        self.stopButton = stop

        let pause = roundButton(x: 40, action: #selector(pauseTapped))
        addSubview(pause)
        self.pauseButton = pause

        let format = roundButton(x: 70, action: #selector(formatTapped))
        format.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Format")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
        format.toolTip = "Switch format — ⌘⇧C"
        addSubview(format)
        self.formatButton = format

        let label = NSTextField(labelWithString: "00:00")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        label.textColor = .labelColor
        label.frame = NSRect(x: 104, y: (h - 18) / 2, width: 64, height: 18)
        addSubview(label)
        self.timeLabel = label

        let zoom = NSImageView(frame: NSRect(x: 172, y: (h - 18) / 2, width: 22, height: 18))
        zoom.image = NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "Zoomed in")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        zoom.contentTintColor = .systemYellow
        zoom.isHidden = true
        zoom.toolTip = "Zoomed in (hold ⌘⇧Z)"
        addSubview(zoom)
        self.zoomBadge = zoom

        let dot = NSView(frame: NSRect(x: Self.contentSize.width - 24, y: (h - 10) / 2, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 5
        addSubview(dot)
        self.recDot = dot
    }

    private func roundButton(x: CGFloat, action: Selector) -> NSButton {
        let b = NSButton(frame: NSRect(x: x, y: (Self.contentSize.height - 28) / 2, width: 28, height: 28))
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.wantsLayer = true
        b.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        b.layer?.cornerRadius = 14
        b.contentTintColor = .labelColor
        b.target = self
        b.action = action
        return b
    }
}
