import Foundation

struct RecordingOptions: Sendable {
    /// What the recording shows. Switchable live while recording.
    var format: CaptureFormat = .screenAndCamera

    /// `uniqueID` of the camera device for the bubble. `nil` = system default.
    var cameraDeviceID: String? = nil

    /// Microphone selection: off, system default, or a specific device.
    var microphone: MicrophoneSelection = .systemDefault

    /// Rectangle to capture, in **points**, top-left origin, relative to the main display.
    /// `nil` = full screen.
    var captureRegion: CGRect? = nil

    /// Aspect ratio the current region was selected with (for display only).
    var captureAspect: CaptureAspect = .free
}

/// Aspect-ratio constraint for region selection so recordings fit common
/// destinations without letterboxing.
enum CaptureAspect: String, CaseIterable, Sendable {
    case free
    case youtube   // 16:9 landscape
    case shorts    // 9:16 portrait

    /// width / height, or `nil` for unconstrained.
    var ratio: CGFloat? {
        switch self {
        case .free: return nil
        case .youtube: return 16.0 / 9.0
        case .shorts: return 9.0 / 16.0
        }
    }

    var menuLabel: String {
        switch self {
        case .free: return "Freeform"
        case .youtube: return "16:9 — YouTube"
        case .shorts: return "9:16 — Shorts / Reels"
        }
    }

    /// Short tag shown next to a selected region.
    var badge: String {
        switch self {
        case .free: return ""
        case .youtube: return "16:9"
        case .shorts: return "9:16"
        }
    }
}

/// The three filming formats, cycled live while recording.
enum CaptureFormat: String, CaseIterable, Sendable {
    case screenOnly        // screen, no camera
    case screenAndCamera   // screen + camera bubble (bottom-right)
    case cameraOnly        // camera fills the frame

    var usesCamera: Bool { self != .screenOnly }

    var next: CaptureFormat {
        switch self {
        case .screenOnly: return .screenAndCamera
        case .screenAndCamera: return .cameraOnly
        case .cameraOnly: return .screenOnly
        }
    }

    var menuLabel: String {
        switch self {
        case .screenOnly: return "Screen only"
        case .screenAndCamera: return "Screen + Camera"
        case .cameraOnly: return "Camera only"
        }
    }

    /// SF Symbol shown on the pill's format button.
    var symbol: String {
        switch self {
        case .screenOnly: return "display"
        case .screenAndCamera: return "rectangle.inset.bottomright.filled"
        case .cameraOnly: return "person.crop.square.fill"
        }
    }
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
