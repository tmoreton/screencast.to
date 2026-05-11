import Foundation

enum UploadConfig {
    /// Endpoint for the Cloudflare Worker that mints presigned PUT URLs.
    /// Replace with your deployed `*.workers.dev` host after `wrangler deploy`.
    static let workerEndpoint = URL(string: "https://notloom-uploads.tmoreton89.workers.dev/sign")!

    /// Shared secret sent in the `X-Notloom-Auth` header on every /sign call.
    /// Must match `APP_SECRET` in `worker/.env`. Generate once with:
    ///   `openssl rand -hex 32`
    static let appSecret = "9bfe6edd8063112f0674d7f7f7b3f14248c57b0959487277a228e832fbb2c2a1"
}
