import Foundation
import OSLog

struct SignResponse: Decodable {
    let uploadUrl: String
    let publicUrl: String
}

private struct SignRequest: Encodable {
    let ext: String
    let contentType: String
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
    private let log = Logger(subsystem: "com.tmoreton.notloom-opus", category: "Upload")
    private var progressObservation: NSKeyValueObservation?

    func upload(fileURL: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        let sign = try await fetchPresignedURL()
        guard let uploadURL = URL(string: sign.uploadUrl),
              let publicURL = URL(string: sign.publicUrl) else {
            throw UploadError.malformedResponse
        }
        try await putFile(fileURL: fileURL, to: uploadURL, progress: progress)
        return publicURL
    }

    private func fetchPresignedURL() async throws -> SignResponse {
        var req = URLRequest(url: UploadConfig.workerEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(UploadConfig.appSecret, forHTTPHeaderField: "X-Notloom-Auth")
        req.httpBody = try JSONEncoder().encode(SignRequest(ext: "mov", contentType: "video/quicktime"))

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
