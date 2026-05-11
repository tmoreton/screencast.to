import Foundation

struct RecordingOptions: Sendable {
    var showCameraBubble: Bool = true

    /// `uniqueID` of the camera device for the bubble. `nil` = system default.
    var cameraDeviceID: String? = nil

    /// Microphone selection: off, system default, or a specific device.
    var microphone: MicrophoneSelection = .systemDefault

    /// Rectangle to capture, in **points**, top-left origin, relative to the main display.
    /// `nil` = full screen.
    var captureRegion: CGRect? = nil
}

enum MicrophoneSelection: Hashable, Sendable {
    case off
    case systemDefault
    case device(String)  // uniqueID

    var isOn: Bool {
        if case .off = self { return false }
        return true
    }

    var deviceID: String? {
        if case .device(let id) = self { return id }
        return nil
    }
}
