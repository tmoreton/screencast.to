import AppKit

/// A floating teleprompter the presenter can read while recording. The window
/// is excluded from screen capture via `sharingType = .none`, so it never
/// appears in the recording — the same trick the recording pill uses.
@MainActor
final class TeleprompterController {
    private var window: NSPanel?
    private var scrollView: NSScrollView?
    private var textView: NSTextView?
    private weak var playButton: NSButton?
    private weak var speedLabel: NSTextField?

    private var timer: Timer?
    private var isScrolling = false
    private var script = ""

    private var speed: CGFloat = 40          // points per second
    private let speedRange: ClosedRange<CGFloat> = 10...160
    private var fontSize: CGFloat = 30
    private let fontRange: ClosedRange<CGFloat> = 18...60

    var isVisible: Bool { window?.isVisible ?? false }

    func show(script: String) {
        self.script = script
        if window == nil { buildWindow() }
        applyText()
        resetToTop()
        isScrolling = false
        stopTimer()
        updatePlayButton()
        window?.orderFrontRegardless()
    }

    func hide() {
        stopTimer()
        isScrolling = false
        window?.orderOut(nil)
    }

    /// Start/pause auto-scroll (also driven by the ⌘⇧Space hotkey).
    func toggleScroll() {
        guard isVisible else { return }
        isScrolling.toggle()
        if isScrolling { startTimer() } else { stopTimer() }
        updatePlayButton()
    }

    // MARK: - Scrolling

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.step() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func step() {
        guard let scrollView else { return }
        let clip = scrollView.contentView
        let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - clip.bounds.height)
        let newY = min(maxY, clip.bounds.origin.y + speed / 60.0)
        clip.scroll(to: NSPoint(x: 0, y: newY))
        scrollView.reflectScrolledClipView(clip)
        if newY >= maxY {
            isScrolling = false
            stopTimer()
            updatePlayButton()
        }
    }

    private func resetToTop() {
        guard let scrollView else { return }
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - Actions

    @objc private func playTapped() { toggleScroll() }
    @objc private func resetTapped() {
        resetToTop()
        isScrolling = false
        stopTimer()
        updatePlayButton()
    }
    @objc private func closeTapped() { hide() }
    @objc private func speedUp() { setSpeed(speed + 10) }
    @objc private func speedDown() { setSpeed(speed - 10) }
    @objc private func fontUp() { setFont(fontSize + 4) }
    @objc private func fontDown() { setFont(fontSize - 4) }

    private func setSpeed(_ value: CGFloat) {
        speed = min(max(value, speedRange.lowerBound), speedRange.upperBound)
        speedLabel?.stringValue = String(format: "%.0f", speed)
    }

    private func setFont(_ value: CGFloat) {
        fontSize = min(max(value, fontRange.lowerBound), fontRange.upperBound)
        applyText()
    }

    private func updatePlayButton() {
        let name = isScrolling ? "pause.fill" : "play.fill"
        playButton?.image = NSImage(systemSymbolName: name, accessibilityDescription: isScrolling ? "Pause" : "Play")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .bold))
    }

    private func applyText() {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 8
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: style
        ]
        let text = script.isEmpty ? "Add a script in the menu to use the teleprompter." : script
        textView?.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attrs))
    }

    // MARK: - Window

    private func buildWindow() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(760, visible.width - 80), height: 200)
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 24)

        let panel = NonactivatingTeleprompterPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Above the camera-fill window, and excluded from the recording.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.sharingType = .none  // never captured
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.setFrameAutosaveName("ScreencastTeleprompter")

        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 12
        bg.layer?.masksToBounds = true
        bg.autoresizingMask = [.width, .height]

        let barHeight: CGFloat = 34
        let controls = buildControlBar(width: size.width, height: barHeight)
        controls.frame = NSRect(x: 0, y: size.height - barHeight, width: size.width, height: barHeight)
        controls.autoresizingMask = [.width, .minYMargin]
        bg.addSubview(controls)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height - barHeight))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false

        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.isSelectable = false
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 28, height: 18)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text

        bg.addSubview(scroll)
        panel.contentView = bg

        self.window = panel
        self.scrollView = scroll
        self.textView = text
        setSpeed(speed)
        updatePlayButton()
    }

    private func buildControlBar(width: CGFloat, height: CGFloat) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        func button(_ symbol: String, _ action: Selector, tip: String) -> NSButton {
            let b = NSButton()
            b.isBordered = false
            b.bezelStyle = .regularSquare
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
            b.contentTintColor = .white
            b.target = self
            b.action = action
            b.toolTip = tip
            return b
        }

        let play = button("play.fill", #selector(playTapped), tip: "Play / pause (⌘⇧Space)")
        self.playButton = play

        let speedField = NSTextField(labelWithString: "40")
        speedField.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        speedField.textColor = .white
        speedField.alignment = .center
        speedField.toolTip = "Scroll speed (points/sec)"
        self.speedLabel = speedField

        let left = NSStackView(views: [
            play,
            button("minus", #selector(speedDown), tip: "Slower"),
            speedField,
            button("plus", #selector(speedUp), tip: "Faster")
        ])
        left.orientation = .horizontal
        left.spacing = 8
        left.translatesAutoresizingMaskIntoConstraints = false

        let right = NSStackView(views: [
            button("textformat.size.smaller", #selector(fontDown), tip: "Smaller text"),
            button("textformat.size.larger", #selector(fontUp), tip: "Larger text"),
            button("arrow.counterclockwise", #selector(resetTapped), tip: "Back to top"),
            button("xmark", #selector(closeTapped), tip: "Hide teleprompter")
        ])
        right.orientation = .horizontal
        right.spacing = 8
        right.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(left)
        bar.addSubview(right)
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            left.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            right.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
        ])
        return bar
    }
}

private final class NonactivatingTeleprompterPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
