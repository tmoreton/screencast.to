import SwiftUI
import AVFoundation

struct MenuBarView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if state.lastError != nil {
                errorBanner
            }

            primary
                .padding(.horizontal, 12)
                .padding(.vertical, 12)

            Divider()

            captureSection

            Divider()
            teleprompterSection

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
        }
    }

    // MARK: - Error banner

    private var errorBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Recording failed")
                    .font(.system(size: 12, weight: .semibold))
                Text(state.lastError ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer()
            Button { state.dismissError() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .padding(10)
        .background(Color.gray.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
            formatRow
            areaRow
            devicePicker(
                label: "Camera",
                systemImage: "video",
                devices: state.devices.cameras,
                selection: $state.options.cameraDeviceID,
                enabled: state.options.format.usesCamera
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
                    Text(state.options.captureAspect.badge.isEmpty
                         ? "Region"
                         : "Region · \(state.options.captureAspect.badge)")
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
                Menu(state.options.captureRegion == nil ? "Select…" : "Change") {
                    Button("16:9 — YouTube") { state.selectRegion(aspect: .youtube) }
                    Button("9:16 — Shorts / Reels") { state.selectRegion(aspect: .shorts) }
                    Button("Freeform") { state.selectRegion(aspect: .free) }
                }
                .menuStyle(.button)
                .fixedSize()
                if state.options.captureRegion != nil {
                    Button("Clear") { state.clearRegion() }
                }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .disabled(state.isBusy)
    }

    private var formatRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.on.rectangle")
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text("Format")
                .font(.system(size: 12))
            Spacer()
            Picker("", selection: $state.options.format) {
                Text("Screen only").tag(CaptureFormat.screenOnly)
                Text("Screen + Camera").tag(CaptureFormat.screenAndCamera)
                Text("Camera only").tag(CaptureFormat.cameraOnly)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 180, alignment: .trailing)
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

    // MARK: - Teleprompter

    private var teleprompterSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text("Teleprompter")
                    .font(.system(size: 12))
                Spacer()
                Toggle("", isOn: $state.teleprompterEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            if state.teleprompterEnabled {
                TextEditor(text: $state.teleprompterScript)
                    .font(.system(size: 12))
                    .frame(height: 88)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3))
                    )
                HStack(spacing: 6) {
                    Text("Hidden from recording · ⌘⇧Space to scroll")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Preview") { state.toggleTeleprompterPreview() }
                        .controlSize(.small)
                        .disabled(state.teleprompterScript.isEmpty)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Recordings

    private var recordingsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RECENT RECORDINGS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)
                Spacer()
                Text("\(state.recordings.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            ForEach(state.recordings.prefix(3), id: \.self) { url in
                recordingRow(url: url)
            }
            if state.recordings.count > 3 {
                Button { state.openRecordingsFolder() } label: {
                    Text("Show all \(state.recordings.count) recordings…")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
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
