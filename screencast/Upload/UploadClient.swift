import Foundation
import OSLog
import StoreKit

struct SignResponse: Decodable {
    let uploadUrl: String
    let publicUrl: String
    let requiredHeaders: [String: String]?
}

private struct SignRequest: Encodable {
    let ext: String
    let sizeBytes: Int64
}

private struct EntitlementRequest: Encodable {
    let appTransactionJWS: String
}

private struct EntitlementResponse: Decodable {
    let serviceToken: String
    let expiresAt: Int64
}

enum UploadError: LocalizedError {
    case uploadNotConfigured
    case purchaseNotVerified
    case entitlementFailed(Int)
    case fileSizeUnavailable
    case fileTooLarge(maxBytes: Int64)
    case signFailed(Int)
    case uploadFailed(Int)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .uploadNotConfigured: return "Upload sharing is not configured in this build."
        case .purchaseNotVerified: return "The App Store purchase could not be verified."
        case .entitlementFailed(let code): return "Hosted sharing could not verify this App Store purchase (status \(code))."
        case .fileSizeUnavailable: return "Could not determine the recording size."
        case .fileTooLarge(let maxBytes): return "Recording is larger than the upload limit (\(ByteCountFormatter.string(fromByteCount: maxBytes, countStyle: .file)))."
        case .signFailed(413): return "Recording is larger than the upload limit."
        case .signFailed(let code): return "Failed to prepare upload (status \(code))."
        case .uploadFailed(let code): return "Upload to the temporary sharing service failed (status \(code))."
        case .malformedResponse: return "Unexpected response from the sharing service."
        }
    }
}

@MainActor
final class UploadClient {
    private struct CachedToken {
        let value: String
        let expiresAt: Date
    }

    private var progressObservation: NSKeyValueObservation?
    private static var cachedServiceToken: CachedToken?
    private let log = Logger(subsystem: "to.screencast.app", category: "Upload")

    /// Total attempts (initial + retries). Backoff between attempts: 1s, 2s.
    private let maxAttempts = 3
    private let defaultMaxUploadBytes: Int64 = 1_073_741_824

    /// Dedicated session sized for large recordings. The default
    /// `session` request timeout is 60s, which a 10-minute screen
    /// recording can blow through on a slow uplink. `timeoutIntervalForRequest`
    /// is the inactivity timeout between bytes; `timeoutIntervalForResource`
    /// caps the whole upload.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300           // 5 min of no data before giving up
        config.timeoutIntervalForResource = 60 * 60      // 1 hour total cap
        config.waitsForConnectivity = true               // tolerate brief network drops
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        return URLSession(configuration: config)
    }()

    func upload(fileURL: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                let sign = try await fetchPresignedURL(for: fileURL)
                guard let uploadURL = URL(string: sign.uploadUrl),
                      let publicURL = URL(string: sign.publicUrl) else {
                    throw UploadError.malformedResponse
                }
                try await putFile(
                    fileURL: fileURL,
                    to: uploadURL,
                    requiredHeaders: sign.requiredHeaders ?? [:],
                    progress: progress
                )
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
                let delaySeconds = attempt
                log.notice("Upload attempt \(attempt) failed (\(error.localizedDescription, privacy: .public)); retrying in \(delaySeconds)s")
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
                progress(0)
            }
        }

        throw lastError ?? UploadError.uploadFailed(-1)
    }

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
            case .entitlementFailed(let code), .signFailed(let code), .uploadFailed(let code):
                return code == -1 || code == 408 || (code >= 500 && code < 600)
            case .uploadNotConfigured, .purchaseNotVerified, .fileSizeUnavailable,
                 .fileTooLarge, .malformedResponse:
                return false
            }
        }
        return false
    }

    private func fetchPresignedURL(for fileURL: URL) async throws -> SignResponse {
        guard let signEndpoint = UploadConfig.signEndpoint else {
            throw UploadError.uploadNotConfigured
        }
        guard let bytes = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw UploadError.fileSizeUnavailable
        }
        let sizeBytes = Int64(bytes)
        if sizeBytes > defaultMaxUploadBytes {
            throw UploadError.fileTooLarge(maxBytes: defaultMaxUploadBytes)
        }

        let token = try await serviceToken()
        var req = URLRequest(url: signEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(SignRequest(ext: "mov", sizeBytes: sizeBytes))

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if code == 401, UploadConfig.sharingMode == .appStore {
                Self.cachedServiceToken = nil
            }
            throw UploadError.signFailed(code)
        }
        return try JSONDecoder().decode(SignResponse.self, from: data)
    }

    private func serviceToken() async throws -> String {
        switch UploadConfig.sharingMode {
        case .disabled:
            throw UploadError.uploadNotConfigured
        case .selfHosted:
            guard let token = UploadConfig.selfHostedToken else {
                throw UploadError.uploadNotConfigured
            }
            return token
        case .appStore:
            if let cachedServiceToken = Self.cachedServiceToken,
               cachedServiceToken.expiresAt.timeIntervalSinceNow > 30 {
                return cachedServiceToken.value
            }
            return try await exchangeAppTransaction()
        }
    }

    private func exchangeAppTransaction() async throws -> String {
        guard let endpoint = UploadConfig.entitlementEndpoint else {
            throw UploadError.uploadNotConfigured
        }

        let appTransaction = try await verifiedAppTransaction()

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(
            EntitlementRequest(appTransactionJWS: appTransaction.jwsRepresentation)
        )

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UploadError.entitlementFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let entitlement = try? JSONDecoder().decode(EntitlementResponse.self, from: data),
              !entitlement.serviceToken.isEmpty else {
            throw UploadError.malformedResponse
        }

        Self.cachedServiceToken = CachedToken(
            value: entitlement.serviceToken,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(entitlement.expiresAt))
        )
        return entitlement.serviceToken
    }

    private func verifiedAppTransaction() async throws -> VerificationResult<AppTransaction> {
        // The cached proof may be absent, throw during lookup, or be present
        // but unverified. The upload button is an explicit user action, so all
        // three cases may ask StoreKit to refresh (and authenticate if needed).
        if let cached = try? await AppTransaction.shared,
           case .verified = cached {
            return cached
        }

        do {
            let refreshed = try await AppTransaction.refresh()
            guard case .verified = refreshed else {
                throw UploadError.purchaseNotVerified
            }
            return refreshed
        } catch {
            throw UploadError.purchaseNotVerified
        }
    }

    private func putFile(
        fileURL: URL,
        to uploadURL: URL,
        requiredHeaders: [String: String],
        progress: @escaping (Double) -> Void
    ) async throws {
        var req = URLRequest(url: uploadURL)
        req.httpMethod = "PUT"
        for (name, value) in requiredHeaders {
            req.setValue(value, forHTTPHeaderField: name)
        }

        defer {
            self.progressObservation?.invalidate()
            self.progressObservation = nil
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let task = session.uploadTask(with: req, fromFile: fileURL) { _, response, error in
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
