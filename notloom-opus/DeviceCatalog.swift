import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class DeviceCatalog {
    private(set) var cameras: [AVCaptureDevice] = []
    private(set) var microphones: [AVCaptureDevice] = []

    private var connectedObserver: NSObjectProtocol?
    private var disconnectedObserver: NSObjectProtocol?

    init() {
        refresh()
        connectedObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        disconnectedObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let videoTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .external,
            .continuityCamera,
            .deskViewCamera,
        ]
        cameras = AVCaptureDevice.DiscoverySession(
            deviceTypes: videoTypes,
            mediaType: .video,
            position: .unspecified
        ).devices

        let audioTypes: [AVCaptureDevice.DeviceType] = [.microphone, .external]
        microphones = AVCaptureDevice.DiscoverySession(
            deviceTypes: audioTypes,
            mediaType: .audio,
            position: .unspecified
        ).devices
    }
}
