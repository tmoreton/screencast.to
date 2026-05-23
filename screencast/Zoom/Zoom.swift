import Foundation
import AppKit
import QuartzCore
import os

/// Shared zoom state for a recording. Inputs (cursor, capture rect, zoom
/// target) are written from the main actor; `sample(...)` is read once per
/// video frame on the recorder's output queue. A small unfair lock guards the
/// inputs; the derived smoothing state is touched only on the output queue.
/// `sample(...)` runs on the recorder's output queue; the lock makes shared
/// access safe (the project defaults to MainActor isolation, which Swift 5
/// does not enforce at runtime for these synchronous calls).
final class ZoomState: @unchecked Sendable {
    private struct Input {
        var captureRect: CGRect = .zero   // captured area in global, y-up screen points
        var cursor: CGPoint = .zero       // global, y-up screen points
        var animFrom: CGFloat = 1
        var animTarget: CGFloat = 1
        var animStart: CFTimeInterval = 0
    }

    private let lock = OSAllocatedUnfairLock(initialState: Input())
    private let animDuration: CFTimeInterval = 0.6
    /// Cursor-follow smoothing time constant (seconds). Higher = slower, gentler
    /// follow so panning isn't dizzying. ~63% of the way to the cursor per this
    /// interval.
    private let followTau: CFTimeInterval = 0.45

    // Output-queue-only smoothing state.
    private var smoothedCenter: CGPoint?
    private var lastSampleTime: CFTimeInterval = 0

    func setCaptureRect(_ rect: CGRect) { lock.withLock { $0.captureRect = rect } }
    func setCursor(_ point: CGPoint) { lock.withLock { $0.cursor = point } }

    /// Animate toward a new zoom factor, anchoring from the current (possibly
    /// mid-animation) factor so reversing direction looks continuous.
    func zoom(to target: CGFloat, at now: CFTimeInterval) {
        lock.withLock { input in
            input.animFrom = Self.factor(input, now: now, duration: animDuration)
            input.animTarget = target
            input.animStart = now
        }
    }

    /// Reset zoom to 1× immediately (keeps the capture rect for reuse).
    func reset() {
        lock.withLock { input in
            input = Input(captureRect: input.captureRect)
        }
        smoothedCenter = nil
        lastSampleTime = 0
    }

    private nonisolated static func factor(_ i: Input, now: CFTimeInterval, duration: CFTimeInterval) -> CGFloat {
        guard i.animStart > 0 else { return i.animTarget }
        let p = min(1, max(0, (now - i.animStart) / duration))
        // easeInOutQuad
        let e = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
        return i.animFrom + (i.animTarget - i.animFrom) * CGFloat(e)
    }

    /// Returns the current zoom factor and the (smoothed, clamped) center to
    /// scale about, in pixel coordinates of the captured buffer (CI y-up).
    /// Returns `nil` when effectively not zoomed so the caller can skip the
    /// Core Image pass entirely.
    func sample(pixelWidth W: Int, pixelHeight H: Int, at now: CFTimeInterval) -> (factor: CGFloat, center: CGPoint)? {
        let (input, z) = lock.withLock { input -> (Input, CGFloat) in
            (input, Self.factor(input, now: now, duration: animDuration))
        }
        guard z > 1.001 else {
            smoothedCenter = nil
            lastSampleTime = 0
            return nil
        }

        let rect = input.captureRect
        var center: CGPoint
        if rect.width > 0, rect.height > 0 {
            let nx = (input.cursor.x - rect.minX) / rect.width
            let ny = (input.cursor.y - rect.minY) / rect.height
            center = CGPoint(x: nx * CGFloat(W), y: ny * CGFloat(H))
        } else {
            center = CGPoint(x: CGFloat(W) / 2, y: CGFloat(H) / 2)
        }

        // Time-based exponential smoothing so the framing eases after the cursor.
        let dt = lastSampleTime > 0 ? now - lastSampleTime : 0
        lastSampleTime = now
        if let s = smoothedCenter, dt > 0 {
            let a = CGFloat(1 - exp(-dt / followTau))
            center = CGPoint(x: s.x + (center.x - s.x) * a, y: s.y + (center.y - s.y) * a)
        }
        smoothedCenter = center

        // Keep the magnified viewport fully inside the source frame.
        let halfW = CGFloat(W) / z / 2
        let halfH = CGFloat(H) / z / 2
        center.x = min(max(center.x, halfW), CGFloat(W) - halfW)
        center.y = min(max(center.y, halfH), CGFloat(H) - halfH)
        return (z, center)
    }
}

/// Drives zoom during a recording: tracks the cursor and translates
/// hold-to-zoom gestures into animated zoom targets.
@MainActor
final class ZoomController {
    let state = ZoomState()
    private(set) var isZoomedIn = false

    private var cursorTimer: Timer?
    private let zoomFactor: CGFloat = 2.0

    /// Begin tracking for a recording whose captured area is `captureRectGlobal`
    /// (global, y-up screen points).
    func start(captureRectGlobal: CGRect) {
        state.setCaptureRect(captureRectGlobal)
        state.setCursor(NSEvent.mouseLocation)
        isZoomedIn = false
        cursorTimer?.invalidate()
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.state.setCursor(NSEvent.mouseLocation) }
        }
    }

    func stop() {
        cursorTimer?.invalidate()
        cursorTimer = nil
        state.reset()
        isZoomedIn = false
    }

    func zoomIn() {
        guard !isZoomedIn else { return }
        isZoomedIn = true
        state.zoom(to: zoomFactor, at: CACurrentMediaTime())
    }

    func zoomOut() {
        guard isZoomedIn else { return }
        isZoomedIn = false
        state.zoom(to: 1.0, at: CACurrentMediaTime())
    }
}
