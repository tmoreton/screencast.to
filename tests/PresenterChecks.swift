import AVFoundation
import CoreImage
import Darwin
import Foundation

/// A standalone executable so these checks exercise production code without an
/// app launch, camera permission, or a separate Xcode test target.
@main
@MainActor
struct PresenterChecks {
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func main() async {
        do {
            try checkAlphaCompositing()
            try checkProcessingBounds()
            try checkLayout()
            try checkFormatCycle()
            try await checkSyntheticCameraFrame()
            print("Presenter checks passed: alpha, scaling, layout, format cycle, and synthetic camera processing.")
        } catch {
            FileHandle.standardError.write(Data("Presenter check failed: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private struct CheckFailure: Error, CustomStringConvertible {
        let description: String
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(description: message) }
    }

    private static func near(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.001
    }

    private static func solid(_ color: CIColor, size: CGSize) -> CIImage {
        CIImage(color: color).cropped(to: CGRect(origin: .zero, size: size))
    }

    private static func pixels(_ image: CIImage) -> [UInt8] {
        let bounds = image.extent.integral
        let rowBytes = Int(bounds.width) * 4
        var result = [UInt8](repeating: 0, count: rowBytes * Int(bounds.height))
        result.withUnsafeMutableBytes { bytes in
            context.render(image, toBitmap: bytes.baseAddress!, rowBytes: rowBytes,
                           bounds: bounds, format: .RGBA8, colorSpace: colorSpace)
        }
        return result
    }

    private static func alphas(_ image: CIImage) -> [UInt8] {
        let rgba = pixels(image)
        return stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
    }

    private static func checkAlphaCompositing() throws {
        let size = CGSize(width: 8, height: 4)
        let image = solid(CIColor(red: 0.2, green: 0.6, blue: 0.9), size: size)
        let maskSize = CGSize(width: 4, height: 2)

        let zero = PresenterCompositor.cutout(image: image, mask: solid(.black, size: maskSize))
        try require(alphas(zero).allSatisfy { $0 == 0 }, "A zero mask must remove every background pixel.")
        try require(pixels(zero).allSatisfy { $0 == 0 }, "Removed pixels must be transparent black.")

        let full = PresenterCompositor.cutout(image: image, mask: solid(.white, size: maskSize))
        try require(pixels(full) == pixels(image), "A full mask must retain the original foreground and alpha.")
        try require(full.extent == image.extent, "Compositing must retain the camera image bounds.")

        // Use an untagged single-channel buffer like Vision's mask. A constant
        // CIColor would be color-managed and need not represent 50% mask data.
        let halfGray = CIImage(bitmapData: Data(repeating: 128, count: 8), bytesPerRow: 4,
                               size: maskSize, format: .L8, colorSpace: nil)
        let soft = PresenterCompositor.cutout(image: image, mask: halfGray)
        try require(alphas(soft).allSatisfy { abs(Int($0) - 128) <= 1 },
                    "A 50% mask must preserve soft edges through partial alpha.")

        // Lower-resolution masks must scale with the camera image, rather than
        // leaving the foreground in the original mask's small top-left region.
        let halfMask = solid(.white, size: CGSize(width: 2, height: 2))
            .composited(over: solid(.black, size: maskSize))
        let split = PresenterCompositor.cutout(image: image, mask: halfMask)
        let splitAlpha = alphas(split)
        for row in 0..<4 {
            try require(splitAlpha[row * 8 + 6] == 0 && splitAlpha[row * 8 + 7] == 0,
                        "Lower-resolution background masks must remain transparent after scaling.")
        }
        for row in 1..<3 {
            try require(splitAlpha[row * 8 + 1] == 255 && splitAlpha[row * 8 + 2] == 255,
                        "Lower-resolution foreground masks must scale to the output width.")
        }
    }

    private static func checkProcessingBounds() throws {
        let cases: [(CGSize, CGSize)] = [
            (CGSize(width: 3840, height: 2160), CGSize(width: 1280, height: 720)),
            (CGSize(width: 1080, height: 1920), CGSize(width: 405, height: 720)),
            (CGSize(width: 2048, height: 2048), CGSize(width: 720, height: 720)),
            (CGSize(width: 320, height: 180), CGSize(width: 320, height: 180)),
            (CGSize(width: 1280, height: 720), CGSize(width: 1280, height: 720))
        ]
        for (sourceSize, expectedSize) in cases {
            let result = PresenterCompositor.processingImage(solid(.white, size: sourceSize)).extent
            try require(near(result.width, expectedSize.width) && near(result.height, expectedSize.height),
                        "Unexpected processing size for \(sourceSize): \(result.size).")
            try require(result.width <= 1280 && result.height <= 720, "Processing must stay within 1280×720.")
            try require(near(result.width / result.height, sourceSize.width / sourceSize.height),
                        "Processing must preserve the camera aspect ratio.")
            try require(result.width <= sourceSize.width && result.height <= sourceSize.height,
                        "Processing must not enlarge a small camera frame.")
        }
    }

    private static func checkLayout() throws {
        let camera = CGSize(width: 1280, height: 720)
        let cases: [(CGSize, CGRect, CGRect)] = [
            (camera, CGRect(x: 0, y: 0, width: 1280, height: 720),
             CGRect(x: 320, y: 0, width: 640, height: 360)),
            (camera, CGRect(x: 0, y: 0, width: 900, height: 1600),
             CGRect(x: 0, y: 0, width: 900, height: 506.25)),
            (camera, CGRect(x: 103, y: 87, width: 1920, height: 1080),
             CGRect(x: 583, y: 87, width: 960, height: 540)),
            (CGSize(width: 720, height: 1280), CGRect(x: 0, y: 0, width: 1920, height: 1080),
             CGRect(x: 808.125, y: 0, width: 303.75, height: 540))
        ]
        for (imageSize, bounds, expected) in cases {
            let frame = PresenterLayout.imageFrame(imageSize: imageSize, in: bounds)
            try require(near(frame.minX, expected.minX) && near(frame.minY, expected.minY)
                        && near(frame.width, expected.width) && near(frame.height, expected.height),
                        "Unexpected presenter frame in \(bounds): \(frame).")
            try require(near(frame.minY, bounds.minY) && near(frame.midX, bounds.midX),
                        "The presenter must stay centered on the capture's bottom edge.")
            try require(frame.width <= bounds.width && frame.height <= bounds.height / 2,
                        "The whole camera frame must fit within the bottom half of the capture.")
            try require(near(frame.width / frame.height, imageSize.width / imageSize.height),
                        "Layout must not crop or distort the presenter's head.")
        }
        try require(PresenterLayout.imageFrame(imageSize: .zero, in: cases[0].1) == .zero,
                    "Missing image dimensions must produce an empty layout.")
        try require(PresenterLayout.imageFrame(imageSize: camera, in: .zero) == .zero,
                    "An empty capture area must produce an empty layout.")
    }

    private static func checkFormatCycle() throws {
        let expected: [CaptureFormat] = [.screenOnly, .screenAndCamera, .presenter, .cameraOnly]
        var format = CaptureFormat.screenOnly
        for next in expected {
            try require(format == next, "Live format cycling must include Presenter in the expected order.")
            try require(format.usesCamera == (format != .screenOnly), "Camera availability must match each format.")
            try require(!format.menuLabel.isEmpty && !format.symbol.isEmpty,
                        "Every format needs a visible label and symbol.")
            format = format.next
        }
        try require(format == .screenOnly && CaptureFormat.allCases.count == expected.count,
                    "The format cycle must return to Screen only after visiting all four formats.")
    }

    private final class FrameReceipt {
        var frames: [(CGImage?, UInt64)] = []
    }

    /// AVFoundation's legacy delegate types lack Sendable annotations. These
    /// immutable test inputs are used only on the processor's serial queue.
    private nonisolated struct SyntheticSample: @unchecked Sendable {
        let buffer: CMSampleBuffer
        let output: AVCaptureVideoDataOutput
        let connection: AVCaptureConnection
    }

    private static func checkSyntheticCameraFrame() async throws {
        var optionalBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32BGRA,
                                        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
                                        &optionalBuffer)
        try require(status == kCVReturnSuccess && optionalBuffer != nil, "Unable to allocate a synthetic camera buffer.")
        let buffer = optionalBuffer!
        context.render(solid(CIColor(red: 0.1, green: 0.8, blue: 0.3), size: CGSize(width: 320, height: 180)),
                       to: buffer, bounds: CGRect(x: 0, y: 0, width: 320, height: 180), colorSpace: colorSpace)

        var formatDescription: CMVideoFormatDescription?
        try require(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                        imageBuffer: buffer, formatDescriptionOut: &formatDescription) == noErr,
                    "Unable to describe the synthetic camera buffer.")
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                       presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        try require(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                        imageBuffer: buffer, formatDescription: formatDescription!, sampleTiming: &timing,
                        sampleBufferOut: &sampleBuffer) == noErr,
                    "Unable to construct the synthetic camera sample.")

        let receipt = FrameReceipt()
        let processor = PresenterFrameProcessor { image, generation in
            receipt.frames.append((image, generation))
        }
        let output = AVCaptureVideoDataOutput()
        // No input ports or session: no camera hardware or privacy prompt.
        let connection = AVCaptureConnection(inputPorts: [], output: output)
        let sample = SyntheticSample(buffer: sampleBuffer!, output: output, connection: connection)
        processor.setActive(generation: 17)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            processor.queue.async {
                processor.captureOutput(sample.output, didOutput: sample.buffer, from: sample.connection)
                continuation.resume()
            }
        }
        for _ in 0..<100 {
            if !receipt.frames.isEmpty { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try require(receipt.frames.count == 1 && receipt.frames[0].1 == 17,
                    "Synthetic processing must deliver a frame with the active generation.")
        guard let image = receipt.frames[0].0 else {
            throw CheckFailure(description: "Vision did not render the blank synthetic camera frame; inspect the Presenter log for a processing failure.")
        }
        try require(image.width == 320 && image.height == 180, "Vision output must retain camera dimensions.")
        try require(alphas(CIImage(cgImage: image)).allSatisfy { $0 <= 1 },
                    "A blank camera frame must never expose the unsegmented room.")
        print("Synthetic Vision frame: no person detected; output is transparent.")

        processor.setActive(generation: nil)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            processor.queue.async {
                processor.captureOutput(sample.output, didOutput: sample.buffer, from: sample.connection)
                continuation.resume()
            }
        }
        try await Task.sleep(for: .milliseconds(100))
        try require(receipt.frames.count == 1, "An inactive processor must not publish camera frames.")
    }
}
