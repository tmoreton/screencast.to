import Foundation
import AppKit
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import CoreImage
import Accelerate
import Metal
import OSLog

enum RecordingState: Equatable {
    case idle
    case preparing
    case recording
    case paused
    case stopping
    case failed(String)
}

/// Coordinates a single screen recording. Owns the lightweight state machine
/// on the main actor and delegates all capture/encode/mix work to a
/// `RecordingSession` that is confined to a serial sample-handler queue.
@MainActor
@Observable
final class RecordingEngine: NSObject {
    private(set) var state: RecordingState = .idle

    private var session: RecordingSession?

    private let log = Logger(subsystem: "to.screencast.app", category: "RecordingEngine")

    func start(options: RecordingOptions, zoomState: ZoomState) async throws {
        guard case .idle = state else { return }
        state = .preparing
        do {
            let session = try await RecordingSession.makeAndStart(options: options, zoomState: zoomState)
            self.session = session
            state = .recording
            log.info("Recording started")
        } catch {
            session = nil
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Pause: stop writing samples while keeping the stream alive. The paused
    /// wall-clock gap is removed from the output timeline on resume.
    func pause() {
        guard case .recording = state, let session else { return }
        session.pause()
        state = .paused
    }

    func resume() {
        guard case .paused = state, let session else { return }
        session.resume()
        state = .recording
    }

    func stop() async throws -> URL {
        guard let session, state == .recording || state == .paused else {
            throw RecordingError.notRecording
        }
        state = .stopping
        do {
            let url = try await session.finish()
            self.session = nil
            state = .idle
            return url
        } catch {
            self.session = nil
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Persistent on-disk location for recordings. Lives in Application Support
    /// so macOS will not purge it under disk pressure (unlike `.cachesDirectory`).
    nonisolated static func recordingsDirectory() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = appSupport.appendingPathComponent("Screencast/Recordings", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}

// MARK: - RecordingSession

/// Drives the SCStream and an AVAssetWriter for one recording. All sample
/// processing (video append + real-time audio mix + pause retiming) happens on
/// `outputQueue`, a single serial queue, so the mutable mixer state needs no
/// locking. Marked `@unchecked Sendable` on that discipline.
private final class RecordingSession: NSObject, @unchecked Sendable {
    let outputURL: URL

    private let outputQueue = DispatchQueue(label: "to.screencast.app.stream-output")
    private let log = Logger(subsystem: "to.screencast.app", category: "RecordingSession")

    private var stream: SCStream?
    private var writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let pixelAdaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput

    // Zoom (live, recording-only). When zoomed, video frames are re-rendered
    // via Core Image; otherwise the raw pixel buffer is appended unchanged.
    private let videoWidth: Int
    private let videoHeight: Int
    private let zoomState: ZoomState?
    private lazy var ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device)
        }
        return CIContext()
    }()
    private let renderColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    // Timeline state (outputQueue only).
    private var sessionStarted = false
    private var sessionStartPTS: CMTime = .zero
    private var totalPaused: CMTime = .zero
    private var latestPTS: CMTime = .zero
    private var lastWrittenSourceEndPTS: CMTime?
    private var lastVideoOutputEndPTS: CMTime?
    private var lastAudioOutputEndPTS: CMTime?
    private var isPaused = false
    private var pauseAnchor: CMTime = .zero
    private var resuming = false
    private let videoFrameDuration = CMTime(value: 1, timescale: 60)

    // Audio mix state (outputQueue only).
    private let micEnabled: Bool
    private let mixFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: true
    )!
    private var systemConverter: AVAudioConverter?
    private var micConverter: AVAudioConverter?
    /// Microphone samples (interleaved float, mix format) waiting to be folded
    /// into the next system-audio buffer. System audio is the master clock.
    private var micQueue: [Float] = []
    private let maxMicQueueFloats = 48_000 * 2 * 2  // ~2s of stereo backlog

    private init(options: RecordingOptions, width: Int, height: Int, zoomState: ZoomState?) throws {
        self.micEnabled = options.microphone.isOn
        self.videoWidth = width
        self.videoHeight = height
        self.zoomState = zoomState

        let dir = try RecordingEngine.recordingsDirectory()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        self.outputURL = dir.appendingPathComponent("Screencast \(formatter.string(from: Date())).mov")

        self.writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        self.videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        let pixelAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        self.pixelAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput, sourcePixelBufferAttributes: pixelAttrs
        )

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 48_000,
            AVEncoderBitRateKey: 128_000
        ]
        self.audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true

        super.init()

        if writer.canAdd(videoInput) { writer.add(videoInput) }
        if writer.canAdd(audioInput) { writer.add(audioInput) }
    }

    /// Build + start the capture stream and the asset writer.
    static func makeAndStart(options: RecordingOptions, zoomState: ZoomState?) async throws -> RecordingSession {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw RecordingError.noDisplay
        }

        let config = SCStreamConfiguration()
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }
        let width: Int
        let height: Int
        if let region = options.captureRegion {
            config.sourceRect = region
            width = max(2, Int(region.width * scale))
            height = max(2, Int(region.height * scale))
        } else {
            width = Int(display.width) * Int(scale)
            height = Int(display.height) * Int(scale)
        }
        config.width = width
        config.height = height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        // Steady cadence so live zoom pans/animates smoothly.
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.capturesAudio = true            // system audio: always on
        config.sampleRate = 48_000
        config.channelCount = 2
        config.captureMicrophone = options.microphone.isOn
        if let micID = options.microphone.deviceID {
            config.microphoneCaptureDeviceID = micID
        }

        let session = try RecordingSession(options: options, width: width, height: height, zoomState: zoomState)

        // Capture everything on the main display, including the floating camera
        // bubble. The caller hides the main control window before start().
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: session)
        try stream.addStreamOutput(session, type: .screen, sampleHandlerQueue: session.outputQueue)
        try stream.addStreamOutput(session, type: .audio, sampleHandlerQueue: session.outputQueue)
        if options.microphone.isOn {
            try stream.addStreamOutput(session, type: .microphone, sampleHandlerQueue: session.outputQueue)
        }

        guard session.writer.startWriting() else {
            throw RecordingError.writerFailed(session.writer.error?.localizedDescription ?? "startWriting failed")
        }
        try await stream.startCapture()
        session.stream = stream
        return session
    }

    func pause() {
        outputQueue.async {
            guard !self.isPaused else { return }
            self.isPaused = true
            self.pauseAnchor = self.lastWrittenSourceEndPTS ?? self.latestPTS
            self.micQueue.removeAll(keepingCapacity: true)
            self.systemConverter?.reset()
            self.micConverter?.reset()
        }
    }

    func resume() {
        outputQueue.async {
            guard self.isPaused else { return }
            self.isPaused = false
            self.resuming = true
            self.micQueue.removeAll(keepingCapacity: true)
        }
    }

    func finish() async throws -> URL {
        if let stream {
            try? await stream.stopCapture()
        }
        // Barrier: let any in-flight sample append complete before finishing.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            outputQueue.async { cont.resume() }
        }
        if videoInput.isReadyForMoreMediaData || writer.status == .writing { videoInput.markAsFinished() }
        if audioInput.isReadyForMoreMediaData || writer.status == .writing { audioInput.markAsFinished() }
        await writer.finishWriting()
        if writer.status == .completed {
            return outputURL
        }
        throw RecordingError.writerFailed(writer.error?.localizedDescription ?? "finishWriting failed")
    }
}

// MARK: - Sample handling (outputQueue)

extension RecordingSession: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts.isValid else { return }
        latestPTS = pts

        if isPaused { return }
        if resuming {
            // Microphone is mixed into system audio and can be delivered before
            // screen/audio after a long pause. Let a writer-backed track anchor
            // the resumed timeline.
            guard type == .screen || type == .audio else { return }
            if sessionStarted {
                totalPaused = CMTimeAdd(totalPaused, CMTimeSubtract(pts, pauseAnchor))
            }
            resuming = false
        }
        if !sessionStarted {
            // Anchor the output timeline at zero on the first sample of any type.
            writer.startSession(atSourceTime: .zero)
            sessionStartPTS = pts
            sessionStarted = true
        }
        let outPTS = CMTimeSubtract(CMTimeSubtract(pts, sessionStartPTS), totalPaused)
        guard outPTS >= .zero else { return }

        switch type {
        case .screen:
            let videoPTS = clampedOutputPTS(outPTS, after: lastVideoOutputEndPTS)
            if appendVideo(sampleBuffer, at: videoPTS) {
                lastVideoOutputEndPTS = CMTimeAdd(videoPTS, videoFrameDuration)
                updateLastWrittenSourceEnd(CMTimeAdd(pts, sourceDuration(sampleBuffer, fallback: videoFrameDuration)))
            }
        case .audio:
            let audioPTS = clampedOutputPTS(outPTS, after: lastAudioOutputEndPTS)
            if let duration = appendMixedAudio(systemBuffer: sampleBuffer, at: audioPTS) {
                lastAudioOutputEndPTS = CMTimeAdd(audioPTS, duration)
                updateLastWrittenSourceEnd(CMTimeAdd(pts, sourceDuration(sampleBuffer, fallback: duration)))
            }
        case .microphone:
            enqueueMic(sampleBuffer)
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        log.error("Stream stopped with error: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: Video

    private func appendVideo(_ sampleBuffer: CMSampleBuffer, at pts: CMTime) -> Bool {
        // Skip idle / blank frames SCStream emits when the screen is static.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let raw = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: raw),
           status != .complete {
            return false
        }
        guard videoInput.isReadyForMoreMediaData,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return false }

        if let zoom = zoomState?.sample(pixelWidth: videoWidth, pixelHeight: videoHeight, at: CACurrentMediaTime()),
           let zoomed = renderZoomed(pixelBuffer, factor: zoom.factor, center: zoom.center) {
            return pixelAdaptor.append(zoomed, withPresentationTime: pts)
        } else {
            return pixelAdaptor.append(pixelBuffer, withPresentationTime: pts)
        }
    }

    /// Scale `source` about `center` by `factor` into a fresh pool buffer.
    /// Returns nil on any failure so the caller falls back to the raw frame.
    private func renderZoomed(_ source: CVPixelBuffer, factor: CGFloat, center: CGPoint) -> CVPixelBuffer? {
        guard let pool = pixelAdaptor.pixelBufferPool else { return nil }
        var output: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output) == kCVReturnSuccess,
              let output else { return nil }

        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .scaledBy(x: factor, y: factor)
            .translatedBy(x: -center.x, y: -center.y)
        let bounds = CGRect(x: 0, y: 0, width: videoWidth, height: videoHeight)
        let image = CIImage(cvPixelBuffer: source)
            .transformed(by: transform)
            .clampedToExtent()
            .cropped(to: bounds)
        ciContext.render(image, to: output, bounds: bounds, colorSpace: renderColorSpace)
        return output
    }

    // MARK: Audio mix (system audio is the master clock)

    private func appendMixedAudio(systemBuffer: CMSampleBuffer, at pts: CMTime) -> CMTime? {
        guard audioInput.isReadyForMoreMediaData,
              let pcm = normalize(systemBuffer, converter: &systemConverter) else { return nil }

        let frames = Int(pcm.frameLength)
        let floats = frames * Int(mixFormat.channelCount)
        let abl = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
        guard let dst = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return nil }

        if micEnabled, !micQueue.isEmpty {
            let take = min(floats, micQueue.count)
            micQueue.withUnsafeBufferPointer { mic in
                vDSP_vadd(dst, 1, mic.baseAddress!, 1, dst, 1, vDSP_Length(take))
            }
            micQueue.removeFirst(take)
            // Guard against clipping after summing two sources.
            var lo: Float = -1, hi: Float = 1
            vDSP_vclip(dst, 1, &lo, &hi, dst, 1, vDSP_Length(floats))
        }

        guard let out = makeAudioSampleBuffer(from: pcm, at: pts) else { return nil }
        return audioInput.append(out) ? audioDuration(frames: frames) : nil
    }

    private func enqueueMic(_ micBuffer: CMSampleBuffer) {
        guard let pcm = normalize(micBuffer, converter: &micConverter) else { return }
        let floats = Int(pcm.frameLength) * Int(mixFormat.channelCount)
        let abl = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
        guard let src = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        micQueue.append(contentsOf: UnsafeBufferPointer(start: src, count: floats))
        if micQueue.count > maxMicQueueFloats {
            micQueue.removeFirst(micQueue.count - maxMicQueueFloats)
        }
    }

    // MARK: Audio helpers

    /// Convert an incoming audio CMSampleBuffer to the canonical mix format
    /// (48 kHz / stereo / interleaved float), reusing one converter per source
    /// so the resampler keeps continuity across buffers.
    private func normalize(_ sampleBuffer: CMSampleBuffer, converter: inout AVAudioConverter?) -> AVAudioPCMBuffer? {
        guard let source = makePCM(from: sampleBuffer) else { return nil }
        if converter == nil || converter?.inputFormat != source.format {
            converter = AVAudioConverter(from: source.format, to: mixFormat)
        }
        guard let converter else { return nil }

        let ratio = mixFormat.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: mixFormat, frameCapacity: capacity) else { return nil }

        var supplied = false
        var convError: NSError?
        let status = converter.convert(to: out, error: &convError) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return source
        }
        guard status != .error, out.frameLength > 0 else { return nil }
        return out
    }

    private func makePCM(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let fd = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd),
              let format = AVAudioFormat(streamDescription: asbd) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList
        )
        return status == noErr ? pcm : nil
    }

    private func makeAudioSampleBuffer(from pcm: AVAudioPCMBuffer, at pts: CMTime) -> CMSampleBuffer? {
        let frames = CMItemCount(pcm.frameLength)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(mixFormat.sampleRate)),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        var status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
            makeDataReadyCallback: nil, refcon: nil,
            formatDescription: pcm.format.formatDescription,
            sampleCount: frames, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else { return nil }
        status = CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer, blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0,
            bufferList: pcm.mutableAudioBufferList
        )
        return status == noErr ? sampleBuffer : nil
    }

    private func clampedOutputPTS(_ pts: CMTime, after previousEnd: CMTime?) -> CMTime {
        guard let previousEnd, pts < previousEnd else { return pts }
        return previousEnd
    }

    private func updateLastWrittenSourceEnd(_ pts: CMTime) {
        if let lastWrittenSourceEndPTS, pts <= lastWrittenSourceEndPTS { return }
        lastWrittenSourceEndPTS = pts
    }

    private func sourceDuration(_ sampleBuffer: CMSampleBuffer, fallback: CMTime) -> CMTime {
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        if duration.isValid, duration > .zero { return duration }
        return fallback
    }

    private func audioDuration(frames: Int) -> CMTime {
        CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(mixFormat.sampleRate))
    }
}

enum RecordingError: LocalizedError {
    case noDisplay
    case notRecording
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display available to capture."
        case .notRecording: return "Not currently recording."
        case .writerFailed(let detail): return "Recording writer failed: \(detail)"
        }
    }
}
