import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var step = 0
    @State private var permissions = PermissionsModel()

    var body: some View {
        ZStack {
            BackgroundLayer()
            VStack(spacing: 0) {
                Group {
                    switch step {
                    case 0: WelcomeStep()
                    default: PermissionsStep(permissions: permissions)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomBar
            }
        }
        .frame(width: 520, height: 600)
        .preferredColorScheme(.dark)
        .onAppear {
            permissions.refresh()
            permissions.startPolling()
        }
        .onDisappear { permissions.stopPolling() }
    }

    private var bottomBar: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? Color.white : Color.white.opacity(0.18))
                        .frame(width: i == step ? 20 : 7, height: 7)
                        .animation(.easeInOut(duration: 0.2), value: step)
                }
            }
            Spacer()

            if step == 1 {
                Button("Back") { step = 0 }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }

            Button(step == 0 ? "Get Started" : "Finish") {
                if step == 0 {
                    step = 1
                } else {
                    onFinish()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            // Finish is never gated — users can skip any permission and grant
            // it later from System Settings (or be re-prompted on first use).
        }
        .padding(24)
    }
}

// MARK: - Welcome step

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 28) {
            Spacer().frame(height: 20)
            BrandMark()
            VStack(spacing: 12) {
                Text("Welcome to Screencast")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.5)
                Text("Record your screen. Share a link.\nA tiny menu-bar app for macOS.")
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineSpacing(2)
            }

            HStack(spacing: 24) {
                feature(icon: "rectangle.dashed", text: "Full screen,\nwindow, or region")
                feature(icon: "video.bubble.left.fill", text: "Camera\nbubble")
                feature(icon: "link", text: "Instant\nshare link")
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private func feature(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.red.opacity(0.9))
                .frame(width: 38, height: 38)
                .background(Color.red.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(text)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.white.opacity(0.7))
                .lineSpacing(2)
        }
        .frame(width: 110)
    }
}

private struct BrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.30, blue: 0.30),
                        Color(red: 0.82, green: 0.18, blue: 0.18)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 120, height: 120)
                .shadow(color: Color.red.opacity(0.55), radius: 28, x: 0, y: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 30)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            Circle()
                .stroke(Color.white.opacity(0.95), lineWidth: 5)
                .frame(width: 70, height: 70)
            Circle()
                .fill(Color.white)
                .frame(width: 40, height: 40)
        }
    }
}

// MARK: - Permissions step

private struct PermissionsStep: View {
    @Bindable var permissions: PermissionsModel

    var body: some View {
        VStack(spacing: 22) {
            Spacer().frame(height: 30)
            VStack(spacing: 10) {
                Text("Grant a few permissions")
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.3)
                Text("macOS requires these for screen capture, voice, and camera.\nYou can change them anytime in System Settings.")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineSpacing(2)
            }

            VStack(spacing: 10) {
                PermissionRow(
                    icon: "rectangle.on.rectangle",
                    title: "Screen Recording",
                    detail: screenRecordingDetail,
                    required: true,
                    status: permissions.screenRecording,
                    actionOverride: screenRecordingActionOverride,
                    onAction: handleScreenRecordingTap
                )
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    detail: "Record your voice in the recording.",
                    required: false,
                    status: permissions.microphone,
                    onAction: {
                        Task { await permissions.requestMicrophone() }
                    }
                )
                PermissionRow(
                    icon: "video.fill",
                    title: "Camera",
                    detail: "Optional camera bubble overlay.",
                    required: false,
                    status: permissions.camera,
                    onAction: {
                        Task { await permissions.requestCamera() }
                    }
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            Text(footerHint)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.bottom, 4)
        }
    }

    private var footerHint: String {
        if permissions.allGranted {
            return "You're all set."
        }
        return "You can grant any of these later in System Settings."
    }

    private var screenRecordingDetail: String {
        if permissions.screenRecording == .granted { return "Capture what's on your screen." }
        if permissions.screenRecordingPrompted {
            return "After enabling in Settings, quit & relaunch for the change to apply."
        }
        return "Capture what's on your screen."
    }

    private var screenRecordingActionOverride: String? {
        if permissions.screenRecording == .granted { return nil }
        if permissions.screenRecordingPrompted { return "Quit & Relaunch" }
        return nil
    }

    private func handleScreenRecordingTap() {
        if permissions.screenRecordingPrompted {
            permissions.relaunchApp()
            return
        }
        if permissions.screenRecording == .notDetermined {
            permissions.requestScreenRecording()
        } else {
            permissions.openScreenRecordingSettings()
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let required: Bool
    let status: PermissionStatus
    var actionOverride: String? = nil
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.red.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    if required {
                        Text("REQUIRED")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.18))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                }
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.55))
            }

            Spacer()

            statusControl
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var statusControl: some View {
        switch status {
        case .granted:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Granted")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
            }
        case .notDetermined:
            Button(actionOverride ?? "Allow", action: onAction)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
        case .denied:
            Button(actionOverride ?? "Open Settings", action: onAction)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

// MARK: - Background

private struct BackgroundLayer: View {
    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.05, blue: 0.07)
            RadialGradient(
                colors: [Color.red.opacity(0.22), Color.clear],
                center: .init(x: 0.5, y: 0),
                startRadius: 0,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}
