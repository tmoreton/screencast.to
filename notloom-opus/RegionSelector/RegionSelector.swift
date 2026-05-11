import AppKit

@MainActor
final class RegionSelector {
    private var window: NSWindow?
    private var completion: ((CGRect?) -> Void)?

    /// Presents a full-screen overlay on the main display and reports back the
    /// selected rect in **display coordinates** (points, top-left origin),
    /// or `nil` if the user cancelled (pressed ESC / clicked without dragging).
    func select(completion: @escaping (CGRect?) -> Void) {
        cancel()
        self.completion = completion

        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            completion(nil)
            return
        }

        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        win.level = .screenSaver
        win.backgroundColor = .clear
        win.isOpaque = false
        win.ignoresMouseEvents = false
        win.acceptsMouseMovedEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        win.hasShadow = false

        let view = RegionSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onConfirm = { [weak self] viewRect in
            // viewRect is bottom-left origin in view coords. The view fills the
            // screen, so flip Y to get top-left origin display coords.
            let displayRect = CGRect(
                x: viewRect.minX,
                y: screen.frame.height - viewRect.maxY,
                width: viewRect.width,
                height: viewRect.height
            )
            self?.finish(with: displayRect)
        }
        view.onCancel = { [weak self] in self?.finish(with: nil) }

        win.contentView = view
        self.window = win
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.set()
    }

    func cancel() {
        completion?(nil)
        completion = nil
        window?.orderOut(nil)
        window = nil
        NSCursor.arrow.set()
    }

    private func finish(with rect: CGRect?) {
        let cb = completion
        completion = nil
        window?.orderOut(nil)
        window = nil
        NSCursor.arrow.set()
        cb?(rect)
    }
}

private final class RegionSelectionView: NSView {
    var onConfirm: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var dragStart: NSPoint?
    private var dragEnd: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        dragEnd = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragEnd = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let s = dragStart, let e = dragEnd else {
            onCancel?()
            return
        }
        let rect = NSRect(
            x: min(s.x, e.x), y: min(s.y, e.y),
            width: abs(e.x - s.x), height: abs(e.y - s.y)
        )
        if rect.width >= 12 && rect.height >= 12 {
            onConfirm?(rect)
        } else {
            onCancel?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // ESC
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dim everything.
        NSColor.black.withAlphaComponent(0.32).setFill()
        bounds.fill()

        guard let s = dragStart, let e = dragEnd else {
            drawHint()
            return
        }
        let rect = NSRect(
            x: min(s.x, e.x), y: min(s.y, e.y),
            width: abs(e.x - s.x), height: abs(e.y - s.y)
        )

        // Punch the selection rect transparent.
        NSColor.clear.setFill()
        rect.fill(using: .copy)

        // Border.
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.stroke()

        // Size readout above the rect (or below, if near top).
        let label = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let size = str.size()
        let pad: CGFloat = 6
        var origin = NSPoint(x: rect.midX - (size.width + pad * 2) / 2,
                             y: rect.maxY + 6)
        if origin.y + size.height + pad * 2 > bounds.maxY {
            origin.y = rect.minY - size.height - pad * 2 - 6
        }
        let chip = NSRect(x: origin.x, y: origin.y,
                          width: size.width + pad * 2, height: size.height + pad * 2)
        let chipPath = NSBezierPath(roundedRect: chip, xRadius: 6, yRadius: 6)
        NSColor.black.withAlphaComponent(0.7).setFill()
        chipPath.fill()
        str.draw(at: NSPoint(x: chip.minX + pad, y: chip.minY + pad))
    }

    private func drawHint() {
        let label = "Drag to select an area  ·  ESC to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let size = str.size()
        let pad: CGFloat = 10
        let chip = NSRect(x: bounds.midX - (size.width + pad * 2) / 2,
                          y: bounds.midY - (size.height + pad * 2) / 2,
                          width: size.width + pad * 2, height: size.height + pad * 2)
        let path = NSBezierPath(roundedRect: chip, xRadius: 10, yRadius: 10)
        NSColor.black.withAlphaComponent(0.55).setFill()
        path.fill()
        str.draw(at: NSPoint(x: chip.minX + pad, y: chip.minY + pad))
    }
}
