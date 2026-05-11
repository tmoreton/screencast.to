import Foundation
import OSLog

struct SignResponse: Decodable {
    let uploadUrl: String
    let publicUrl: String
}

private struct SignRequest: Encodable {
    let ext: String
}

enum UploadError: LocalizedError {
    case signFailed(Int)
    case uploadFailed(Int)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .signFailed(let code): return "Failed to sign upload (status \(code))."
        case .uploadFailed(let code): return "Upload to R2 failed (status \(code))."
        case .malformedResponse: return "Unexpected response from signing service."
        }
    }
}

@MainActor
final class UploadClient {
    private var progressObservation: NSKeyValueObservation?
    private let log = Logger(subsystem: "to.screencast.app", category: "Upload")

    /// Total attempts (initial + retries). Backoff between attempts: 1s, 2s.
    private let maxAttempts = 3

    func upload(fileURL: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                let sign = try await fetchPresignedURL()
                guard let uploadURL = URL(string: sign.uploadUrl),
                      let publicURL = URL(string: sign.publicUrl) else {
                    throw UploadError.malformedResponse
                }
                try await putFile(fileURL: fileURL, to: uploadURL, progress: progress)
                if attempt > 1 {
                    log.info("Upload succeeded on attempt \(attempt)")
                }
                return publicURL
            } catch {
                lastError = error
                let canRetry = attempt < maxAttempts && Self.isRetryable(error)
                if !canRetry {
                    log.error("Upload failed (attempt \(attempt)/\(self.maxAttempts), giving up): \(error.localizedDescription, privacy: .public)")
                    throw error
                }
                // Exponential-ish backoff: 1s after attempt 1, 2s after attempt 2.
                let delaySeconds = attempt
                log.notice("Upload attempt \(attempt) failed (\(error.localizedDescription, privacy: .public)); retrying in \(delaySeconds)s")
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
                progress(0)  // reset progress UI for the next attempt
            }
        }

        throw lastError ?? UploadError.uploadFailed(-1)
    }

    /// Returns `true` for errors that are likely transient (network blip,
    /// gateway hiccup, server 5xx). Auth failures, malformed responses, and
    /// rate-limited responses are NOT retried — re-attempting won't fix them
    /// within our short backoff window.
    private static func isRetryable(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .networkConnectionLost,
                 .notConnectedToInternet,
                 .timedOut,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .dataNotAllowed,
                 .internationalRoamingOff:
                return true
            default:
                return false
            }
        }
        if let uploadError = error as? UploadError {
            switch uploadError {
            case .signFailed(let code), .uploadFailed(let code):
                return code == -1 || code == 408 || (code >= 500 && code < 600)
            case .malformedResponse:
                return false
            }
        }
        return false
    }

    private func fetchPresignedURL() async throws -> SignResponse {
        var req = URLRequest(url: UploadConfig.workerEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(UploadConfig.appSecret, forHTTPHeaderField: "X-Screencast-Auth")
        req.httpBody = try JSONEncoder().encode(SignRequest(ext: "mov"))

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UploadError.signFailed(code)
        }
        return try JSONDecoder().decode(SignResponse.self, from: data)
    }

    private func putFile(fileURL: URL, to uploadURL: URL, progress: @escaping (Double) -> Void) async throws {
        var req = URLRequest(url: uploadURL)
        req.httpMethod = "PUT"
        // Intentionally do NOT set Content-Type — the Worker signs only host.

        defer {
            self.progressObservation?.invalidate()
            self.progressObservation = nil
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let task = URLSession.shared.uploadTask(with: req, fromFile: fileURL) { _, response, error in
                if let error = error {
                    cont.resume(throwing: error)
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    cont.resume(throwing: UploadError.uploadFailed(-1))
                    return
                }
                if (200..<300).contains(http.statusCode) {
                    cont.resume(returning: ())
                } else {
                    cont.resume(throwing: UploadError.uploadFailed(http.statusCode))
                }
            }
            self.progressObservation = task.progress.observe(\.fractionCompleted, options: [.new]) { prog, _ in
                let value = prog.fractionCompleted
                Task { @MainActor in progress(value) }
            }
            task.resume()
        }
    }
}
