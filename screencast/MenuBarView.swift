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

            captureSection

            if !state.recordings.isEmpty, !state.isActive {
                Divider()
                recordingsList
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
            Image(nsImage: NSApp.applicationIconImage ?? NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
            Text("Screencast")
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
        case .paused: Text("Paused")
        case .saving: Text("Saving…")
        case .error: Text("Error")
        }
    }

    // MARK: - Primary

    @ViewBuilder
    private var primary: some View {
        switch state.phase {
        case .saving:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Saving recording…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Recording failed")
                        .fontWeight(.semibold)
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Button { state.toggleRecording() } label: {
                    Text("New Recording")
                }
                .controlSize(.small)
            }
        default:
            VStack(spacing: 8) {
                Button(action: { state.toggleRecording() }) {
                    HStack(spacing: 6) {
                        Image(systemName: state.isActive ? "stop.circle.fill" : "record.circle")
                        Text(state.isActive ? "Stop Recording" : "Start Recording")
                            .fontWeight(.semibold)
                        Spacer()
                        Text("⌘⇧R")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(state.isActive ? .red : .accentColor)

                if state.isActive {
                    Button(action: { state.togglePauseResume() }) {
                        HStack(spacing: 6) {
                            Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                            Text(state.isPaused ? "Resume" : "Pause")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Capture

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            toggleRow("Camera bubble", systemImage: "video.bubble.left", isOn: $state.options.showCameraBubble)
            areaRow
            devicePicker(
                label: "Camera",
                systemImage: "video",
                devices: state.devices.cameras,
                selection: $state.options.cameraDeviceID,
                enabled: state.options.showCameraBubble
            )
            microphonePicker
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(state.isBusy)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var areaRow: some View {
        HStack(spacing: 6) {
            Image(systemName: state.options.captureRegion == nil ? "display" : "crop")
                .foregroundStyle(.secondary)
                .frame(width: 14)
            if let r = state.options.captureRegion {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Region")
                        .font(.system(size: 12))
                    Text("\(Int(r.width)) × \(Int(r.height))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Full screen")
                    .font(.system(size: 12))
            }
            Spacer()
            HStack(spacing: 4) {
                Button(state.options.captureRegion == nil ? "Select…" : "Change") {
                    state.selectRegion()
                }
                if state.options.captureRegion != nil {
                    Button("Clear") { state.clearRegion() }
                }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .disabled(state.isBusy)
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

    private var microphonePicker: some View {
        HStack(spacing: 6) {
            Image(systemName: state.options.microphone.isOn ? "mic" : "mic.slash")
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text("Microphone")
                .font(.system(size: 12))
            Spacer()
            Picker("", selection: $state.options.microphone) {
                Text("None").tag(MicrophoneSelection.off)
                Text("System default").tag(MicrophoneSelection.systemDefault)
                if !state.devices.microphones.isEmpty { Divider() }
                ForEach(state.devices.microphones, id: \.uniqueID) { device in
                    Text(device.localizedName).tag(MicrophoneSelection.device(device.uniqueID))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 180, alignment: .trailing)
        }
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

    // MARK: - Recordings

    private var recordingsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RECORDINGS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)
                Spacer()
                Text("\(state.recordings.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            ForEach(state.recordings.prefix(6), id: \.self) { url in
                recordingRow(url: url)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func recordingRow(url: URL) -> some View {
        HStack(spacing: 8) {
            Button { state.playRecording(url) } label: {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .help("Play")
            .buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text(fileSizeString(url: url))
                    Text("·")
                    Text(relativeDate(modificationDate(url)))
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button { state.revealInFinder(url) } label: {
                Image(systemName: "folder")
            }
            .help("Reveal in Finder")
            .buttonStyle(.borderless)
            Button { state.deleteRecording(url) } label: {
                Image(systemName: "trash")
            }
            .help("Move to Trash")
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button { state.openRecordingsFolder() } label: {
                Label("Show Recordings", systemImage: "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Spacer()
            Button { state.quit() } label: {
                Text("⌘Q Quit")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: [.command])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Formatters

    private func fileSizeString(url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
