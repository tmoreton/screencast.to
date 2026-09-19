import SwiftUI

@main
struct ScreencastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState()
    @StateObject private var updateManager = UpdateManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: state, updateManager: updateManager)
        } label: {
            Image(systemName: (state.isActive || state.isStarting) ? "record.circle.fill" : "record.circle")
                .foregroundStyle(state.isPaused || state.isStarting ? .orange : (state.isRecording ? .red : .primary))
        }
        .menuBarExtraStyle(.window)
    }
}
