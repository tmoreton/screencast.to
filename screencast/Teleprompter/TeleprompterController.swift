import AppKit

/// A floating teleprompter the presenter reads while recording. Excluded from
/// capture via `sharingType = .none`. When recording, the recording controls
/// are embedded in its header (`RecordingControlsHost`) so the teleprompter and
/// the controls are one single unit.
@MainActor
final class TeleprompterController: RecordingControlsHost {
    private var window: NSPanel?
    private var scrollView: NSScrollView?
    private var textView: NSTextView?
    private weak var playButton: NSButton?
    private weak var speedLabel: NSTextField?
    private weak var closeButton: NSButton?
    private var recordingBar: RecordingControlBar?

    private var timer: Timer?
    private var isScrolling = false
    private var script = ""

    private var speed: CGFloat = 40          // points per second
    private let speedRange: ClosedRange<CGFloat> = 10...160
    private var fontSize: CGFloat = 30
    private let fontRange: ClosedRange<CGFloat> = 10...60

    private let headerHeight: CGFloat = 48
    private let textInset = NSSize(width: 28, height: 18)
    private let minimumWindowSize = NSSize(width: 460, height: 160)

    var isVisible: Bool { window?.isVisible ?? false }

    func loadScript(_ text: String) {
        script = text
        if window != nil { applyText() }
    }

    // MARK: - Preview (no recording)

    /// Show for positioning/previewing when not recording: teleprompter only,
    /// with a close button and no recording controls.
    func showPreview() {
        present(recording: false, onStop: nil, onPauseResume: nil, onCycleFormat: nil)
    }

    func togglePreview() {
        if isVisible { hide() } else { showPreview() }
    }

    // MARK: - RecordingControlsHost (unit with recording controls)

    func showControls(
        onStop: @escaping () -> Void,
        onPauseResume: @escaping () -> Void,
        onCycleFormat: @escaping () -> Void
    ) {
        present(recording: true, onStop: onStop, onPauseResume: onPauseResume, onCycleFormat: onCycleFormat)
    }

    func hideControls() { hide() }
    func beginCountdown(seconds: Int) { recordingBar?.beginCountdown(seconds: seconds) }
    func updateCountdown(seconds: Int) { recordingBar?.updateCountdown(seconds: seconds) }
    func beginRecording() { recordingBar?.begin() }
    func setPaused(_ paused: Bool) { recordingBar?.setPaused(paused) }
    func setFormat(_ format: CaptureFormat) { recordingBar?.setFormat(format) }
    func setZoomActive(_ active: Bool) { recordingBar?.setZoomActive(active) }

    private func present(
        recording: Bool,
        onStop: (() -> Void)?,
        onPauseResume: (() -> Void)?,
        onCycleFormat: (() -> Void)?
    ) {
        if window == nil { buildWindow() }
        applyText()
        resetToTop()
        isScrolling = false
        stopTimer()
        updatePlayButton()

        recordingBar?.isHidden = !recording
        closeButton?.isHidden = recording
        if recording {
            recordingBar?.onStop = onStop
            recordingBar?.onPauseResume = onPauseResume
            recordingBar?.onCycleFormat = onCycleFormat
            recordingBar?.end()
        } else {
            recordingBar?.end()
        }
        window?.orderFrontRegardless()
    }

    func hide() {
        stopTimer()
        isScrolling = false
        recordingBar?.end()
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
    @objc private func fontUp() { setFont(fontSize + fontStep) }
    @objc private func fontDown() { setFont(fontSize - fontStep) }

    private var fontStep: CGFloat {
        fontSize <= 18 ? 2 : 4
    }

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
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 8
        style.alignment = .left
        style.lineBreakMode = .byWordWrapping
        style.defaultTabInterval = "    ".size(withAttributes: [.font: font]).width
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
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
        let size = NSSize(width: min(760, visible.width - 80), height: 220)
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 24)

        let panel = NonactivatingTeleprompterPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.minSize = minimumWindowSize
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.sharingType = .none  // never captured
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.setFrameAutosaveName("ScreencastTeleprompter")

        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: panel.frame.size))
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 14
        bg.layer?.masksToBounds = true
        bg.autoresizingMask = [.width, .height]

        let header = buildHeader(width: panel.frame.width)
        header.frame = NSRect(x: 0, y: panel.frame.height - headerHeight, width: panel.frame.width, height: headerHeight)
        header.autoresizingMask = [.width, .minYMargin]
        bg.addSubview(header)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: panel.frame.width, height: panel.frame.height - headerHeight))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false

        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.isSelectable = false
        text.drawsBackground = false
        text.textContainerInset = textInset
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = text

        bg.addSubview(scroll)

        let resizeHandle = TeleprompterResizeHandle(
            frame: NSRect(x: panel.frame.width - 22, y: 0, width: 22, height: 22),
            minimumSize: minimumWindowSize
        )
        resizeHandle.autoresizingMask = [.minXMargin, .maxYMargin]
        bg.addSubview(resizeHandle)

        panel.contentView = bg

        self.window = panel
        self.scrollView = scroll
        self.textView = text
        setSpeed(speed)
        updatePlayButton()
    }

    private func buildHeader(width: CGFloat) -> NSView {
        let header = NSView(frame: NSRect(x: 0, y: 0, width: width, height: headerHeight))

        // Recording controls (left), hidden until recording.
        let bar = RecordingControlBar(frame: NSRect(x: 10, y: (headerHeight - RecordingControlBar.contentSize.height) / 2,
                                                    width: RecordingControlBar.contentSize.width,
                                                    height: RecordingControlBar.contentSize.height))
        bar.autoresizingMask = [.maxXMargin]
        bar.isHidden = true
        header.addSubview(bar)
        self.recordingBar = bar

        // Teleprompter controls (right).
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

        let close = button("xmark", #selector(closeTapped), tip: "Hide teleprompter")
        self.closeButton = close

        let stack = NSStackView(views: [
            play,
            button("minus", #selector(speedDown), tip: "Slower"),
            speedField,
            button("plus", #selector(speedUp), tip: "Faster"),
            button("textformat.size.smaller", #selector(fontDown), tip: "Smaller text"),
            button("textformat.size.larger", #selector(fontUp), tip: "Larger text"),
            button("arrow.counterclockwise", #selector(resetTapped), tip: "Back to top"),
            close
        ])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])
        return header
    }
}

private final class NonactivatingTeleprompterPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class TeleprompterResizeHandle: NSView {
    private let minimumSize: NSSize
    private var initialFrame = NSRect.zero
    private var initialMouseLocation = NSPoint.zero

    init(frame frameRect: NSRect, minimumSize: NSSize) {
        self.minimumSize = minimumSize
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath()
        path.lineWidth = 1
        NSColor.white.withAlphaComponent(0.35).setStroke()

        for offset in [7.0, 12.0, 17.0] {
            path.move(to: NSPoint(x: bounds.maxX - offset, y: 4))
            path.line(to: NSPoint(x: bounds.maxX - 4, y: offset))
        }

        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        initialFrame = window.frame
        initialMouseLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }

        let current = NSEvent.mouseLocation
        let deltaX = current.x - initialMouseLocation.x
        let deltaY = current.y - initialMouseLocation.y
        let top = initialFrame.maxY
        let width = max(minimumSize.width, initialFrame.width + deltaX)
        let height = max(minimumSize.height, initialFrame.height - deltaY)

        var frame = NSRect(x: initialFrame.minX, y: top - height, width: width, height: height)
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin.y = max(visible.minY, top - frame.height)
        }

        window.setFrame(frame, display: true)
    }
}
