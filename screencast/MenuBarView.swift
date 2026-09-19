import SwiftUI
import AVFoundation
import AppKit

struct MenuBarView: View {
    @Bindable var state: AppState
    @ObservedObject var updateManager: UpdateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if state.lastError != nil {
                errorBanner
            }

            if !state.captureInputIssues.isEmpty {
                captureInputBanner
            }

            primary
                .padding(.horizontal, 12)
                .padding(.vertical, 12)

            Divider()

            captureSection

            Divider()
            teleprompterSection

            if !state.recordings.isEmpty, !state.isBusy {
                Divider()
                recordingsList
            }

            Divider()
            footer
        }
        .frame(width: 320)
        .background(.background)
        .onAppear { state.refreshOptionalInputAvailability() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshOptionalInputAvailability()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in
            state.refreshOptionalInputAvailability()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in
            state.refreshOptionalInputAvailability()
        }
        .onChange(of: state.options.cameraDeviceID) {
            state.refreshOptionalInputAvailability()
        }
        .onChange(of: state.options.microphone) {
            state.refreshOptionalInputAvailability()
        }
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
            if updateManager.isEnabled {
                Button(action: updateManager.checkForUpdates) {
                    Image(systemName: "arrow.clockwise.circle")
                }
                .buttonStyle(.borderless)
                .disabled(!updateManager.canCheckForUpdates)
                .accessibilityLabel("Check for Updates")
                .help("Check for Updates…")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusText: some View {
        switch state.phase {
        case .idle: Text("Idle")
        case .starting(let remaining):
            if let remaining {
                Text("Starting in \(remaining)…")
            } else {
                Text("Starting…")
            }
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

    private var captureInputBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 5) {
                Text("Optional input unavailable")
                    .font(.system(size: 12, weight: .semibold))
                ForEach(state.captureInputIssues, id: \.self) { issue in
                    Text(inputIssueMessage(issue))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    if state.captureInputIssues.contains(where: cameraIssueHasSettings) {
                        Button("Camera Settings") { state.openCameraPrivacySettings() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                    if state.captureInputIssues.contains(where: microphoneIssueHasSettings) {
                        Button("Microphone Settings") { state.openMicrophonePrivacySettings() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }
            Spacer()
            Button { state.dismissCaptureInputIssues() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .padding(10)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Primary

    @ViewBuilder
    private var primary: some View {
        switch state.phase {
        case .starting(let remaining):
            VStack(spacing: 8) {
                Button(action: { state.toggleRecording() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                        Text("Cancel Recording")
                            .fontWeight(.semibold)
                        Spacer()
                        if let remaining {
                            Text("00:\(String(format: "%02d", remaining))")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
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
                enabled: state.options.format.usesCamera && state.canSelectCamera
            )
            cameraAvailabilityHelp
            systemAudioToggle
            microphonePicker
            microphoneAvailabilityHelp
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
                Text("Screen + Camera")
                    .tag(CaptureFormat.screenAndCamera)
                    .disabled(!state.canSelectCamera)
                Text("Camera only")
                    .tag(CaptureFormat.cameraOnly)
                    .disabled(!state.canSelectCamera)
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
                Text("System default")
                    .tag(MicrophoneSelection.systemDefault)
                    .disabled(!state.canSelectMicrophone)
                if !state.devices.microphones.isEmpty { Divider() }
                ForEach(state.devices.microphones, id: \.uniqueID) { device in
                    Text(device.localizedName)
                        .tag(MicrophoneSelection.device(device.uniqueID))
                        .disabled(!state.canSelectMicrophone)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 180, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var cameraAvailabilityHelp: some View {
        switch state.cameraInputAvailability {
        case .denied:
            inputAvailabilityHelp(
                "Camera access is off. Screen-only recording is still available.",
                settingsAction: state.openCameraPrivacySettings
            )
        case .restricted:
            inputAvailabilityHelp("Camera access is restricted by this Mac's policy.")
        case .unavailable:
            inputAvailabilityHelp("No selected camera is currently available.")
        case .available, .requestable:
            EmptyView()
        }
    }

    @ViewBuilder
    private var microphoneAvailabilityHelp: some View {
        switch state.microphoneInputAvailability {
        case .denied:
            inputAvailabilityHelp(
                "Microphone access is off. Recording can continue without your voice.",
                settingsAction: state.openMicrophonePrivacySettings
            )
        case .restricted:
            inputAvailabilityHelp("Microphone access is restricted by this Mac's policy.")
        case .unavailable:
            inputAvailabilityHelp("No selected microphone is currently available.")
        case .available, .requestable:
            EmptyView()
        }
    }

    private func inputAvailabilityHelp(
        _ message: String,
        settingsAction: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 2)
            if let settingsAction {
                Button("Settings", action: settingsAction)
                    .buttonStyle(.link)
            }
        }
        .font(.system(size: 10))
        .padding(.leading, 20)
    }

    private var systemAudioToggle: some View {
        HStack(spacing: 6) {
            Image(systemName: state.options.systemAudio ? "speaker.wave.2" : "speaker.slash")
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Toggle("System audio", isOn: $state.options.systemAudio)
                .font(.system(size: 12))
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
        .disabled(!enabled)
    }

    private func inputIssueMessage(_ issue: CaptureInputIssue) -> String {
        switch issue {
        case .cameraPermissionRequired:
            return "Camera was not added while recording. Stop, choose a camera format, and press Record to allow access."
        case .cameraDenied:
            return "Camera access was denied. Camera capture was disabled; screen-only recording remains available."
        case .cameraRestricted:
            return "Camera access is restricted. Camera capture was disabled; screen-only recording remains available."
        case .cameraUnavailable:
            return "The selected camera was unavailable, so camera capture was disabled."
        case .microphonePermissionRequired:
            return "Microphone access must be granted when starting a new recording."
        case .microphoneDenied:
            return "Microphone access was denied, so voice capture was disabled."
        case .microphoneRestricted:
            return "Microphone access is restricted, so voice capture was disabled."
        case .microphoneUnavailable:
            return "The selected microphone was unavailable, so voice capture was disabled."
        }
    }

    private func cameraIssueHasSettings(_ issue: CaptureInputIssue) -> Bool {
        issue == .cameraDenied
    }

    private func microphoneIssueHasSettings(_ issue: CaptureInputIssue) -> Bool {
        issue == .microphoneDenied
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
                    .font(.system(size: 12, design: .monospaced))
                    .autocorrectionDisabled(true)
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
            uploadControl(url: url)
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

    @ViewBuilder
    private func uploadControl(url: URL) -> some View {
        switch state.uploadState(for: url) {
        case .idle:
            if UploadConfig.isUploadConfigured {
                Button { state.uploadRecording(url) } label: {
                    Image(systemName: "icloud.and.arrow.up")
                }
                .help("Upload & copy a temporary link")
                .buttonStyle(.borderless)
            } else {
                Image(systemName: "icloud.slash")
                    .foregroundStyle(.secondary)
                    .help("Hosted sharing is disabled in this build")
            }
        case .uploading(let progress):
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .controlSize(.small)
                .frame(width: 16, height: 16)
                .help("Uploading \(Int(progress * 100))%")
        case .done(let link, let at):
            HStack(spacing: 2) {
                Button { state.copyLink(link) } label: {
                    Image(systemName: "checkmark.icloud")
                        .foregroundStyle(.green)
                }
                .help("Copy link · hidden here in \(rememberedLinkText(at))")
                .buttonStyle(.borderless)

                Button { state.copyIssueNote(for: url, link: link, sharedAt: at) } label: {
                    Image(systemName: "doc.text")
                }
                .help("Copy issue note")
                .buttonStyle(.borderless)
            }
        case .failed(let message):
            Button { state.uploadRecording(url) } label: {
                Image(systemName: "exclamationmark.icloud")
                    .foregroundStyle(.orange)
            }
            .help("Upload failed: \(message) — click to retry")
            .buttonStyle(.borderless)
        }
    }

    private func rememberedLinkText(_ at: Date) -> String {
        let remaining = AppState.rememberedLinkLifetime - Date().timeIntervalSince(at)
        guard remaining > 0 else { return "0m" }
        let hours = Int(remaining / 3600)
        if hours > 0 { return "\(hours)h" }
        return "\(max(1, Int(remaining / 60)))m"
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
            Button("Privacy") { state.openPrivacyPolicy() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .disabled(ProductLinks.privacyURL == nil)
            Button("Support") { state.openSupport() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .disabled(ProductLinks.supportURL == nil)
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
