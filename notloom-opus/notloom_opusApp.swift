import SwiftUI

@main
struct notloom_opusApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            Image(systemName: state.isRecording ? "record.circle.fill" : "record.circle")
                .foregroundStyle(state.isRecording ? .red : .primary)
        }
        .menuBarExtraStyle(.window)
    }
}
