import Foundation

@main
struct SharingChecks {
    static func main() throws {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let challenge = WebsiteSharingAuthorization.makeCodeChallenge(verifier: verifier)
        precondition(challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "RFC 7636 S256 vector")
        let state = "state&with spaces/+"
        let url = try WebsiteSharingAuthorization.connectURL(
            baseURL: URL(string: "https://screencast.to")!, challenge: challenge, state: state
        )
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        precondition(components.path == "/connect-sharing.html")
        precondition(components.queryItems?.first(where: { $0.name == "state" })?.value == state)
        let code = String(repeating: "c", count: 43)
        let valid = URL(string: "to.screencast.app://sharing/callback?code=\(code)&state=expected")!
        let callbackCode = try WebsiteSharingAuthorization.callbackCode(from: valid, expectedState: "expected")
        precondition(callbackCode == code)
        let invalid = [
            "https://sharing/callback?code=approved&state=expected",
            "to.screencast.app://other/callback?code=approved&state=expected",
            "to.screencast.app://sharing/other?code=approved&state=expected",
            "to.screencast.app://sharing/%63allback?code=approved&state=expected",
            "to.screencast.app://user@sharing/callback?code=approved&state=expected",
            "to.screencast.app://sharing:443/callback?code=approved&state=expected",
            "to.screencast.app://sharing/callback?code=approved&state=wrong",
            "to.screencast.app://sharing/callback?code=approved&state=expected#fragment",
            "to.screencast.app://sharing/callback?code=approved&code=second&state=expected",
            "to.screencast.app://sharing/callback?code=approved&state=expected&state=expected",
            "to.screencast.app://sharing/callback?state=expected",
            "to.screencast.app://sharing/callback?code=&state=expected",
            "to.screencast.app://sharing/callback?code=approved&state=expected&error=denied",
            "to.screencast.app://sharing/callback?code=approved&state=expected&unknown=value",
        ].map { $0.replacingOccurrences(of: "code=approved", with: "code=\(code)") } + [
            "to.screencast.app://sharing/callback?code=short&state=expected",
            "to.screencast.app://sharing/callback?code=\(String(repeating: "c", count: 44))&state=expected",
            "to.screencast.app://sharing/callback?code=\(String(repeating: "c", count: 42))%2B&state=expected",
        ]
        for raw in invalid {
            do {
                _ = try WebsiteSharingAuthorization.callbackCode(from: URL(string: raw)!, expectedState: "expected")
                preconditionFailure("Rejected callback was accepted")
            } catch WebsiteSharingError.invalidCallback { }
        }
        for raw in ["http://screencast.to", "https://user@screencast.to", "https://screencast.to?next=evil", "https://screencast.to/other"] {
            do {
                _ = try WebsiteSharingAuthorization.connectURL(baseURL: URL(string: raw)!, challenge: challenge, state: state)
                preconditionFailure("Invalid website base URL was accepted")
            } catch WebsiteSharingError.notConfigured { }
        }
        let first = try WebsiteSharingAuthorization.randomValue()
        let second = try WebsiteSharingAuthorization.randomValue()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        precondition(first != second && first.count == 43 && second.count == 43)
        precondition(first.unicodeScalars.allSatisfy { allowed.contains($0) })
        print("Website sharing checks passed: RFC S256, URL encoding, exact callback/state rejection, and secure random format.")
    }
}
