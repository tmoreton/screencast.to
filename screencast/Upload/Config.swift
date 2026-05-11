import Foundation

enum UploadConfig {
    /// Endpoint for the Cloudflare Worker that mints presigned PUT URLs.
    /// Canonical URL is the custom domain; the workers.dev URL also works
    /// while the custom domain is being provisioned.
    static let workerEndpoint = URL(string: "https://screencast.to/sign")!

    // `appSecret` is defined in Config.local.swift (gitignored) so secrets
    // never enter source control. Copy Config.local.swift.example to
    // Config.local.swift and fill in the value from worker/.env APP_SECRET.
}
