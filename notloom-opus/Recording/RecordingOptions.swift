import Foundation

struct RecordingOptions: Sendable {
    var includeMicrophone: Bool = true
    var includeSystemAudio: Bool = true
    var showCameraBubble: Bool = true

    /// `uniqueID` of the camera device for the bubble. `nil` = system default.
    var cameraDeviceID: String? = nil
    /// `uniqueID` of the microphone device. `nil` = system default.
    var microphoneDeviceID: String? = nil
}
