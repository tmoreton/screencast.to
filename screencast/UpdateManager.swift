import Combine
import Foundation

#if SPARKLE_UPDATER
import Sparkle
#endif

@MainActor
final class UpdateManager: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isEnabled = false

#if SPARKLE_UPDATER
    private var updaterController: SPUStandardUpdaterController?
    private var canCheckCancellable: AnyCancellable?
#endif

    init() {
#if SPARKLE_UPDATER
        guard let configuration = Self.configuration else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.httpHeaders = [
            "Authorization": "Bearer \(configuration.updateToken)"
        ]
        controller.updater.sendsSystemProfile = false
        updaterController = controller
        isEnabled = true
        canCheckCancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
        controller.startUpdater()
#endif
    }

    func checkForUpdates() {
#if SPARKLE_UPDATER
        updaterController?.checkForUpdates(nil)
#endif
    }

#if SPARKLE_UPDATER
    private struct Configuration {
        let updateToken: String
    }

    private static var configuration: Configuration? {
        let info = Bundle.main.infoDictionary ?? [:]
        let feedURL = info["SUFeedURL"] as? String ?? ""
        let publicKey = info["SUPublicEDKey"] as? String ?? ""
        let updateToken = info["ScreencastUpdateToken"] as? String ?? ""
        guard URL(string: feedURL)?.scheme == "https",
              !publicKey.isEmpty,
              updateToken.count >= 32 else { return nil }
        return Configuration(updateToken: updateToken)
    }
#endif
}
