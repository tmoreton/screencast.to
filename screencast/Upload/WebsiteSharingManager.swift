import AppKit
@preconcurrency import AuthenticationServices
import CryptoKit
import Foundation
import Security

enum WebsiteSharingError: LocalizedError {
    case notConfigured
    case notConnected
    case cancelled
    case connectionFailed
    case invalidCallback
    case invalidResponse
    case verificationRequired
    case requestFailed(Int)
    case keychainUnavailable
    case randomGenerationFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Website sharing is not configured in this build."
        case .notConnected: return "Connect your Screencast.to purchase to enable cloud sharing."
        case .cancelled: return "Connecting cloud sharing was cancelled."
        case .connectionFailed: return "The browser could not connect cloud sharing. Try connecting again."
        case .invalidCallback: return "The sharing connection could not be verified. Please connect again."
        case .invalidResponse: return "The website returned an unexpected sharing response. Please connect again."
        case .verificationRequired: return "Cloud sharing could not verify your website purchase. Connect again to verify your purchase."
        case .requestFailed(let status): return "The website could not authorize cloud sharing (status \(status)). Please try again."
        case .keychainUnavailable: return "Cloud sharing could not access the Mac Keychain. Unlock your Keychain and try again."
        case .randomGenerationFailed: return "A secure sharing connection could not be created. Please try again."
        }
    }
}

/// Pure protocol helpers shared by the native browser flow and its checks.
nonisolated enum WebsiteSharingAuthorization {
    static let callbackScheme = "to.screencast.app"

    static func makeCodeChallenge(verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func connectURL(baseURL: URL, challenge: String, state: String) throws -> URL {
        guard let base = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              base.scheme?.lowercased() == "https", base.host?.isEmpty == false,
              base.user == nil, base.password == nil, base.port == nil,
              base.query == nil, base.fragment == nil,
              base.path.isEmpty || base.path == "/",
              !challenge.isEmpty, !state.isEmpty,
              var components = URLComponents(url: baseURL.appending(path: "connect-sharing.html"),
                                             resolvingAgainstBaseURL: false) else {
            throw WebsiteSharingError.notConfigured
        }
        components.queryItems = [
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else { throw WebsiteSharingError.notConfigured }
        return url
    }

    static func callbackCode(from url: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == callbackScheme,
              components.percentEncodedHost == "sharing", components.percentEncodedPath == "/callback",
              components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil,
              let items = components.queryItems else {
            throw WebsiteSharingError.invalidCallback
        }
        let states = items.filter { $0.name == "state" }
        let codes = items.filter { $0.name == "code" }
        guard states.count == 1, states[0].value == expectedState, !expectedState.isEmpty,
              codes.count == 1, let code = codes[0].value,
              code.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              items.allSatisfy({ $0.name == "code" || $0.name == "state" }) else {
            throw WebsiteSharingError.invalidCallback
        }
        return code
    }

    static func randomValue() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw WebsiteSharingError.randomGenerationFailed
        }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Persist only the opaque, revocable website grant. Short-lived service JWTs
/// live in memory and never enter preferences or application logs.
private nonisolated struct WebsiteSharingGrantStore {
    private let service = "to.screencast.app.website-sharing"
    private let account = "sharing-grant"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func load() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let grant = String(data: data, encoding: .utf8), !grant.isEmpty else {
            throw WebsiteSharingError.keychainUnavailable
        }
        return grant
    }

    func save(_ grant: String) throws {
        guard !grant.isEmpty else { throw WebsiteSharingError.invalidResponse }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(grant.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw WebsiteSharingError.keychainUnavailable }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw WebsiteSharingError.keychainUnavailable
        }
    }
}

/// Authorization responses stay out of disk caches, and redirects never carry
/// a grant or PKCE verifier to another URL.
private nonisolated final class WebsiteSharingRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
@Observable
final class WebsiteSharingManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebsiteSharingManager()

    private(set) var isConnected = false
    private(set) var isConnecting = false

    private struct CachedToken {
        let value: String
        let expiresAt: Date
    }
    private struct ExchangeRequest: Encodable {
        let code: String
        let codeVerifier: String
        let state: String
    }
    private struct TokenRequest: Encodable {
        let sharingGrant: String
    }
    private struct AuthorizationResponse: Decodable {
        let sharingGrant: String?
        let serviceToken: String
        let expiresAt: Int64
    }
    private struct PendingAuthentication {
        let id: UUID
        let expectedState: String
        let continuation: CheckedContinuation<URL, Error>
    }

    private let grantStore = WebsiteSharingGrantStore()
    private let networkSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration, delegate: WebsiteSharingRedirectPolicy(), delegateQueue: nil)
    }()
    private var cachedServiceToken: CachedToken?
    private var authenticationSession: ASWebAuthenticationSession?
    private var pendingAuthentication: PendingAuthentication?
    private var connectionTask: Task<Void, Error>?
    private var tokenTask: Task<String, Error>?
    private var authorizationGeneration = 0

    private override init() {
        super.init()
        isConnected = (try? grantStore.load()) != nil
    }

    func connect() async throws {
        if let connectionTask { return try await connectionTask.value }
        let task = Task { try await self.performConnect() }
        connectionTask = task
        defer { connectionTask = nil }
        try await task.value
    }

    func disconnect() throws {
        try grantStore.delete()
        authorizationGeneration &+= 1
        cachedServiceToken = nil
        isConnected = false
        completeAuthentication(.failure(WebsiteSharingError.cancelled))
        authenticationSession?.cancel()
        connectionTask?.cancel()
        tokenTask?.cancel()
    }

    /// Called after a website authorization or signing rejection. A later,
    /// explicit cloud-button click can reconnect; this call never opens a browser.
    func requirePurchaseVerification() {
        authorizationGeneration &+= 1
        cachedServiceToken = nil
        isConnected = false
        try? grantStore.delete()
    }

    /// A recovery email can open a separate browser tab. Route its custom URL
    /// back to the same pending in-memory flow; never create a flow on relaunch.
    @discardableResult
    func handleCallbackURL(_ url: URL) -> Bool {
        guard let pendingAuthentication,
              (try? WebsiteSharingAuthorization.callbackCode(
                from: url, expectedState: pendingAuthentication.expectedState
              )) != nil else { return false }
        completeAuthentication(.success(url))
        return true
    }

    func serviceToken() async throws -> String {
        if let cachedServiceToken, cachedServiceToken.expiresAt.timeIntervalSinceNow > 30 {
            return cachedServiceToken.value
        }
        if let tokenTask { return try await tokenTask.value }
        let task = Task { try await self.refreshServiceToken() }
        tokenTask = task
        defer { tokenTask = nil }
        return try await task.value
    }

    private func performConnect() async throws {
        guard UploadConfig.sharingMode == .website, UploadConfig.isUploadConfigured,
              let baseURL = UploadConfig.websiteBaseURL,
              let endpoint = UploadConfig.websiteExchangeEndpoint else {
            throw WebsiteSharingError.notConfigured
        }
        isConnecting = true
        defer { isConnecting = false }
        let generation = authorizationGeneration
        let verifier = try WebsiteSharingAuthorization.randomValue()
        let state = try WebsiteSharingAuthorization.randomValue()
        let url = try WebsiteSharingAuthorization.connectURL(
            baseURL: baseURL,
            challenge: WebsiteSharingAuthorization.makeCodeChallenge(verifier: verifier),
            state: state
        )
        let callback = try await authenticate(at: url, expectedState: state)
        let code = try WebsiteSharingAuthorization.callbackCode(from: callback, expectedState: state)
        try checkGeneration(generation)
        let response: AuthorizationResponse = try await post(
            ExchangeRequest(code: code, codeVerifier: verifier, state: state), to: endpoint
        )
        try checkGeneration(generation)
        guard let grant = response.sharingGrant, !grant.isEmpty else {
            throw WebsiteSharingError.invalidResponse
        }
        try store(response, sharingGrant: grant)
    }

    private func refreshServiceToken() async throws -> String {
        guard UploadConfig.sharingMode == .website, let endpoint = UploadConfig.websiteTokenEndpoint else {
            throw WebsiteSharingError.notConfigured
        }
        guard let grant = try grantStore.load() else {
            isConnected = false
            throw WebsiteSharingError.notConnected
        }
        let generation = authorizationGeneration
        let response: AuthorizationResponse = try await post(TokenRequest(sharingGrant: grant), to: endpoint)
        try checkGeneration(generation)
        try store(response, sharingGrant: response.sharingGrant ?? grant)
        return response.serviceToken
    }

    private func store(_ response: AuthorizationResponse, sharingGrant: String) throws {
        let expiresAt = Date(timeIntervalSince1970: TimeInterval(response.expiresAt))
        guard !response.serviceToken.isEmpty, expiresAt.timeIntervalSinceNow > 30 else {
            throw WebsiteSharingError.invalidResponse
        }
        try grantStore.save(sharingGrant)
        cachedServiceToken = CachedToken(value: response.serviceToken,
                                         expiresAt: min(expiresAt, Date().addingTimeInterval(15 * 60)))
        isConnected = true
    }

    private func checkGeneration(_ generation: Int) throws {
        guard generation == authorizationGeneration, !Task.isCancelled else {
            throw WebsiteSharingError.cancelled
        }
    }

    private func post<Body: Encodable, Response: Decodable>(_ body: Body, to url: URL) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await networkSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WebsiteSharingError.invalidResponse }
        if http.statusCode == 401 {
            requirePurchaseVerification()
            throw WebsiteSharingError.verificationRequired
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WebsiteSharingError.requestFailed(http.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw WebsiteSharingError.invalidResponse
        }
        return decoded
    }

    private func authenticate(at url: URL, expectedState: String) async throws -> URL {
        defer { authenticationSession = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let authenticationID = UUID()
            pendingAuthentication = PendingAuthentication(id: authenticationID, expectedState: expectedState,
                                                          continuation: continuation)
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: WebsiteSharingAuthorization.callbackScheme
            ) { [weak self] callback, error in
                Task { @MainActor [weak self] in
                    guard let self, self.pendingAuthentication?.id == authenticationID else { return }
                    if let callback {
                        if !self.handleCallbackURL(callback) {
                            self.completeAuthentication(.failure(WebsiteSharingError.invalidCallback))
                        }
                    } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        self.completeAuthentication(.failure(WebsiteSharingError.cancelled))
                    } else {
                        self.completeAuthentication(.failure(WebsiteSharingError.connectionFailed))
                    }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authenticationSession = session
            if !session.start() {
                completeAuthentication(.failure(WebsiteSharingError.connectionFailed))
            }
        }
    }

    private func completeAuthentication(_ result: Result<URL, Error>) {
        guard let pending = pendingAuthentication else { return }
        pendingAuthentication = nil
        // Clear the continuation before cancel(), whose callback may race an
        // off-tab URL open. Only the first matching callback can exchange a code.
        authenticationSession?.cancel()
        pending.continuation.resume(with: result)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) ?? ASPresentationAnchor()
    }
}
