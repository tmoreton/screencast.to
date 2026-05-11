import SwiftUI
import AVFoundation

struct MenuBarView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            primary
                .padding(.horizontal, 12)
                .padding(.vertical, 12)

            Divider()

            section("Capture") {
                toggleRow("Camera bubble", systemImage: "video.bubble.left", isOn: $state.options.showCameraBubble)
                toggleRow("Microphone", systemImage: "mic", isOn: $state.options.includeMicrophone)
                toggleRow("System audio", systemImage: "speaker.wave.2", isOn: $state.options.includeSystemAudio)
            }

            Divider()

            section("Devices") {
                devicePicker(
                    label: "Camera",
                    systemImage: "video",
                    devices: state.devices.cameras,
                    selection: $state.options.cameraDeviceID,
                    enabled: state.options.showCameraBubble
                )
                devicePicker(
                    label: "Microphone",
                    systemImage: "mic",
                    devices: state.devices.microphones,
                    selection: $state.options.microphoneDeviceID,
                    enabled: state.options.includeMicrophone
                )
            }

            if let url = state.lastSharedURL, !state.isRecording {
                Divider()
                lastShare(url: url)
            }

            Divider()
            footer
        }
        .frame(width: 320)
        .background(.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.isRecording ? Color.red : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            Text("notloom")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            statusText
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusText: some View {
        switch state.phase {
        case .idle: Text("Idle")
        case .recording: Text("Recording")
        case .uploading(let p): Text("Uploading \(Int(p * 100))%")
        case .done: Text("Ready")
        case .error: Text("Error")
        }
    }

    // MARK: - Primary

    @ViewBuilder
    private var primary: some View {
        switch state.phase {
        case .uploading(let p):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: p)
                Text("Uploading \(Int(p * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        default:
            Button(action: { state.toggleRecording() }) {
                HStack(spacing: 6) {
                    Image(systemName: state.isRecording ? "stop.circle.fill" : "record.circle")
                    Text(state.isRecording ? "Stop Recording" : "Start Recording")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(state.isRecording ? .red : .accentColor)
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)
                .padding(.top, 10)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(state.isBusy)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func toggleRow(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 12))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
    }

    private func devicePicker(
        label: String,
        systemImage: String,
        devices: [AVCaptureDevice],
        selection: Binding<String?>,
        enabled: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 12))
            Spacer()
            Picker("", selection: selection) {
                Text("System default").tag(String?.none)
                if !devices.isEmpty { Divider() }
                ForEach(devices, id: \.uniqueID) { device in
                    Text(device.localizedName).tag(Optional(device.uniqueID))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 180, alignment: .trailing)
        }
        .opacity(enabled ? 1.0 : 0.45)
    }

    // MARK: - Last share

    private func lastShare(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LAST RECORDING")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)
            Text(url.absoluteString)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button { state.copyLastURL() } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button { state.openLastURL() } label: {
                    Label("Open", systemImage: "safari")
                }
                Spacer()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button { state.quit() } label: {
                Text("Quit notloom")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: [.command])
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
