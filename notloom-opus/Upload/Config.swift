import Foundation

enum UploadConfig {
    /// Endpoint for the Cloudflare Worker that mints presigned PUT URLs.
    /// Replace with your deployed `*.workers.dev` host after `wrangler deploy`.
    static let workerEndpoint = URL(string: "https://notloom-uploads.tmoreton89.workers.dev/sign")!

    // `appSecret` is defined in Config.local.swift (gitignored) so secrets
    // never enter source control. Copy Config.local.swift.example to
    // Config.local.swift and fill in the value from worker/.env APP_SECRET.
}
