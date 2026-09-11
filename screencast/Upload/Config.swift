import Foundation

enum SharingMode: String {
    case disabled
    case appStore = "app-store"
    case selfHosted = "self-hosted"
}

enum ProductLinks {
    static let marketingURL = bundleHTTPSURL(for: "ScreencastMarketingURL")
    static let privacyURL = bundleHTTPSURL(for: "ScreencastPrivacyURL")
    static let supportURL = bundleHTTPSURL(for: "ScreencastSupportURL")

    private static func bundleHTTPSURL(for key: String) -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }
}

enum UploadConfig {
    private static let sharingModeInfoKey = "ScreencastSharingMode"
    private static let workerBaseURLInfoKey = "ScreencastWorkerBaseURL"
    private static let selfHostedTokenInfoKey = "ScreencastSelfHostedUploadToken"

    /// Public source builds are deliberately disabled unless a developer opts
    /// into a self-hosted service. App Store archives select `app-store` in
    /// `scripts/app-store-release.sh`.
    static var sharingMode: SharingMode {
        guard let value = bundleString(for: sharingModeInfoKey) else {
            return .disabled
        }
        return SharingMode(rawValue: value) ?? .disabled
    }

    static var workerBaseURL: URL? {
        guard let raw = bundleString(for: workerBaseURLInfoKey),
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || (scheme == "http" && url.host == "localhost") else {
            return nil
        }
        return url
    }

    static var signEndpoint: URL? {
        endpoint(path: "sign")
    }

    static var entitlementEndpoint: URL? {
        endpoint(path: "entitlements/token")
    }

    /// Optional bearer credential for a developer's own Worker. It is never
    /// used by official App Store builds and does not grant access to the
    /// first-party Screencast.to service.
    static var selfHostedToken: String? {
        bundleString(for: selfHostedTokenInfoKey)
    }

    static var isUploadConfigured: Bool {
        guard workerBaseURL != nil else { return false }
        switch sharingMode {
        case .disabled:
            return false
        case .appStore:
            return true
        case .selfHosted:
            return selfHostedToken != nil
        }
    }

    private static func endpoint(path: String) -> URL? {
        workerBaseURL?.appending(path: path)
    }

    private static func bundleString(for key: String) -> String? {
        let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty || value == "REPLACE_ME" { return nil }
        return value
    }
}
