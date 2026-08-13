import Foundation

enum UploadConfig {
    private static let uploadSecretInfoKey = "ScreencastUploadSecret"
    private static let workerEndpointInfoKey = "ScreencastWorkerEndpoint"

    /// Endpoint for the Cloudflare Worker that mints presigned PUT URLs.
    static var workerEndpoint: URL {
        if let raw = bundleString(for: workerEndpointInfoKey),
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://share.screencast.to/sign")!
    }

    /// Official builds inject this value at release time. Public/dev builds
    /// intentionally compile without it, which disables upload sharing.
    static var appSecret: String? {
        bundleString(for: uploadSecretInfoKey)
    }

    static var isUploadConfigured: Bool {
        appSecret != nil
    }

    private static func bundleString(for key: String) -> String? {
        let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty || value == "REPLACE_ME" { return nil }
        return value
    }
}
