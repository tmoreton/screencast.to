import AVFoundation
import CoreImage
import OSLog
import Vision
import os

/// Camera frames, Vision state and rendering stay on `queue`. Only the latest
/// rendered frame is handed to the main actor, so a busy UI cannot build a backlog.
nonisolated final class PresenterFrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "to.screencast.app.presenter", qos: .userInitiated)

    private let onFrame: @MainActor @Sendable (CGImage?, UInt64) -> Void
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let log = Logger(subsystem: "to.screencast.app", category: "Presenter")
    private var generation: UInt64?
    private var request: VNGeneratePersonSegmentationRequest?
    private var lastFrameTime: CMTime?
    private var loggedFailure = false

    private struct Delivery {
        var frame: (image: CGImage?, generation: UInt64)?
        var scheduled = false
    }
    private let delivery = OSAllocatedUnfairLock(initialState: Delivery())

    init(onFrame: @escaping @MainActor @Sendable (CGImage?, UInt64) -> Void) {
        self.onFrame = onFrame
    }

    func setActive(generation: UInt64?) {
        queue.async {
            self.generation = generation
            self.lastFrameTime = nil
            self.loggedFailure = false
            // A new request drops temporal masks from the previous camera/mode.
            self.request = generation.map { _ in
                let request = VNGeneratePersonSegmentationRequest()
                request.qualityLevel = .balanced
                request.outputPixelFormat = kCVPixelFormatType_OneComponent8
                return request
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let generation, let request,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        // The screen remains at 60 fps; foreground processing is capped at 30.
        if let lastFrameTime, time.isValid, time >= lastFrameTime,
           CMTimeGetSeconds(time - lastFrameTime) < 1.0 / 30.0 { return }
        lastFrameTime = time

        autoreleasepool {
            do {
                let image = PresenterCompositor.processingImage(CIImage(cvPixelBuffer: buffer))
                try VNImageRequestHandler(ciImage: image, options: [:]).perform([request])
                guard let mask = request.results?.first?.pixelBuffer else {
                    publish(nil, generation: generation)
                    return
                }
                let cutout = PresenterCompositor.cutout(image: image, mask: CIImage(cvPixelBuffer: mask))
                let rendered = context.createCGImage(cutout, from: image.extent,
                                                     format: .RGBA8, colorSpace: colorSpace)
                publish(rendered, generation: generation)
            } catch {
                // Keep the overlay transparent on failure; never reveal the room.
                publish(nil, generation: generation)
                if !loggedFailure {
                    log.error("Presenter background removal failed: \(error.localizedDescription, privacy: .public)")
                    loggedFailure = true
                }
            }
        }
    }

    private func publish(_ image: CGImage?, generation: UInt64) {
        let shouldSchedule = delivery.withLock { pending in
            pending.frame = (image, generation)
            guard !pending.scheduled else { return false }
            pending.scheduled = true
            return true
        }
        guard shouldSchedule else { return }
        Task { @MainActor in
            let frame = delivery.withLock { pending in
                let frame = pending.frame
                pending.frame = nil
                pending.scheduled = false
                return frame
            }
            if let frame { onFrame(frame.image, frame.generation) }
        }
    }
}

nonisolated enum PresenterCompositor {
    /// Bound segmentation/rendering cost independently of the camera's resolution.
    static func processingImage(_ image: CIImage) -> CIImage {
        let scale = min(1, 1280 / image.extent.width, 720 / image.extent.height)
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    static func cutout(image: CIImage, mask: CIImage) -> CIImage {
        let scaledMask = mask.transformed(by: CGAffineTransform(
            scaleX: image.extent.width / mask.extent.width,
            y: image.extent.height / mask.extent.height
        ))
        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: image.extent),
            kCIInputMaskImageKey: scaledMask
        ]).cropped(to: image.extent)
    }
}

nonisolated enum PresenterLayout {
    /// Preserve the whole camera frame within the bottom half of any capture.
    /// Transparent space at either side lets the desktop show through.
    static func imageFrame(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / imageSize.width, bounds.height * 0.5 / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.minY,
                      width: size.width, height: size.height)
    }
}
