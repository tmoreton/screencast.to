import Foundation

enum UploadConfig {
    /// Endpoint for the Cloudflare Worker that mints presigned PUT URLs.
    /// Replace with your deployed `*.workers.dev` host after `wrangler deploy`.
    static let workerEndpoint = URL(string: "https://notloom-uploads.tmoreton89.workers.dev/sign")!
}
