import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import OSLog

enum RecordingState: Equatable {
    case idle
    case preparing
    case recording
    case stopping
    case failed(String)
}

@MainActor
@Observable
final class RecordingEngine: NSObject {
    private(set) var state: RecordingState = .idle
    private(set) var lastOutputURL: URL?

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var pendingOutputURL: URL?
    private var stopContinuation: CheckedContinuation<URL, Error>?

    private let log = Logger(subsystem: "com.tmoreton.notloom-opus", category: "RecordingEngine")
    private let outputQueue = DispatchQueue(label: "com.tmoreton.notloom-opus.stream-output")

    func start(options: RecordingOptions) async throws {
        guard case .idle = state else { return }
        state = .preparing

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                throw RecordingError.noDisplay
            }

            // Capture everything on the main display, including our floating
            // camera bubble. The caller is responsible for hiding the main
            // control window before calling start().
            let filter = SCContentFilter(display: display, excludingWindows: [])

            let config = SCStreamConfiguration()
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            if let region = options.captureRegion {
                config.sourceRect = region
                config.width = max(2, Int(region.width * scale))
                config.height = max(2, Int(region.height * scale))
            } else {
                config.width = Int(display.width) * Int(scale)
                config.height = Int(display.height) * Int(scale)
            }
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = true
            config.capturesAudio = true       // system audio: always on
            config.captureMicrophone = options.microphone.isOn
            if let micID = options.microphone.deviceID {
                config.microphoneCaptureDeviceID = micID
            }

            let outputURL = try makeOutputURL()
            pendingOutputURL = outputURL

            let recConfig = SCRecordingOutputConfiguration()
            recConfig.outputURL = outputURL
            recConfig.outputFileType = .mov
            recConfig.videoCodecType = .h264

            let output = SCRecordingOutput(configuration: recConfig, delegate: self)
            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addRecordingOutput(output)

            // Register no-op stream outputs for every enabled frame type.
            // SCStream's internal pipeline expects an SCStreamOutput handler
            // per enabled type; without these it logs "streamOutput NOT found.
            // Dropping frame" repeatedly even though SCRecordingOutput writes
            // the file via a separate pipeline.
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: outputQueue)
            if options.microphone.isOn {
                try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: outputQueue)
            }

            try await stream.startCapture()

            self.stream = stream
            self.recordingOutput = output
            state = .recording
            log.info("Recording started -> \(outputURL.path, privacy: .public)")
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func stop() async throws -> URL {
        guard case .recording = state, let stream else {
            throw RecordingError.notRecording
        }
        state = .stopping

        let finalURL: URL = try await withCheckedThrowingContinuation { cont in
            self.stopContinuation = cont
            Task {
                do {
                    try await stream.stopCapture()
                    // Wait for the delegate's didFinishRecording to fire and
                    // resume the continuation with the finalized file.
                } catch {
                    self.stopContinuation?.resume(throwing: error)
                    self.stopContinuation = nil
                }
            }
        }

        self.stream = nil
        self.recordingOutput = nil
        self.pendingOutputURL = nil
        self.lastOutputURL = finalURL
        self.state = .idle
        return finalURL
    }

    private func makeOutputURL() throws -> URL {
        let fm = FileManager.default
        let caches = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = caches.appendingPathComponent("notloom", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("\(UUID().uuidString).mov")
    }
}

extension RecordingEngine: SCStreamOutput, SCStreamDelegate {
    // No-op: SCRecordingOutput handles writing. We register handlers per type
    // purely to satisfy SCStream's internal pipeline and silence the
    // "streamOutput NOT found. Dropping frame" warnings.
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {}

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.log.error("Stream stopped with error: \(error.localizedDescription, privacy: .public)")
            if let cont = self.stopContinuation {
                self.stopContinuation = nil
                cont.resume(throwing: error)
            } else {
                self.state = .failed(error.localizedDescription)
            }
        }
    }
}

extension RecordingEngine: SCRecordingOutputDelegate {
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            self.log.info("Recording output: didStart")
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        Task { @MainActor in
            self.log.error("Recording output failed: \(error.localizedDescription, privacy: .public)")
            if let cont = self.stopContinuation {
                self.stopContinuation = nil
                cont.resume(throwing: error)
            } else {
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            self.log.info("Recording output: didFinish")
            guard let url = self.pendingOutputURL else { return }
            if let cont = self.stopContinuation {
                self.stopContinuation = nil
                cont.resume(returning: url)
            }
        }
    }
}

enum RecordingError: LocalizedError {
    case noDisplay
    case notRecording

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display available to capture."
        case .notRecording: return "Not currently recording."
        }
    }
}
