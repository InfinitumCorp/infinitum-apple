import CryptoKit
import Foundation
import Security

/// URL-safe base64 without padding (RFC 4648 §5), as PKCE and the handoff use.
public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ text: String) -> Data? {
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        return Data(base64Encoded: s)
    }

    static func random(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "No secure random bytes")
        return encode(Data(bytes))
    }
}

/// PKCE (RFC 7636) with S256. The verifier never leaves the app.
public struct PKCE: Sendable, Equatable {
    public let verifier: String
    public let challenge: String

    public init(verifier: String = Base64URL.random(48)) {
        self.verifier = verifier
        self.challenge = PKCE.challenge(for: verifier)
    }

    public static func challenge(for verifier: String) -> String {
        Base64URL.encode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
}

/// A signed-in Cumulus ID session. `profileJSON` is the profile object exactly as Cumulus ID sent it.
public struct CumulusSession: Codable, Sendable, Equatable {
    public var token: String
    public var profileJSON: String
    public var until: Date

    public init(token: String, profileJSON: String, until: Date) {
        self.token = token
        self.profileJSON = profileJSON
        self.until = until
    }

    /// Valid for at least another minute.
    public func isValid(at now: Date = Date()) -> Bool {
        !token.isEmpty && until > now.addingTimeInterval(60)
    }

    var profile: [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(profileJSON.utf8))) as? [String: Any] ?? [:]
    }

    /// Email or username, for "Signed in as".
    public var displayName: String? {
        let p = profile
        return (p["email"] as? String) ?? (p["username"] as? String) ?? (p["name"] as? String)
    }

    /// `{ token, profile, until }` with `until` in epoch milliseconds: the shape the web Cumulus ID
    /// button keeps in sessionStorage and the shape `#cid_handoff` carries.
    public func webValue() -> [String: Any] {
        ["token": token, "profile": profile, "until": Int64(until.timeIntervalSince1970 * 1000)]
    }
}

/// One sign-in attempt: what was sent to Cumulus ID and what must come back.
public struct AuthRequest: Identifiable, Sendable, Equatable {
    public var id: String { state }
    public let issuer: URL
    public let url: URL
    public let redirectURI: URL
    public let state: String
    public let pkce: PKCE
    public let create: Bool
}

public enum CumulusIDError: LocalizedError, Equatable {
    case mismatch
    case refused(String)
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .mismatch: return "That sign-in didn't match. Please try again."
        case .refused(let why): return why
        case .server(let why): return why
        }
    }
}

/// Where a URL inside the product web app points at Cumulus ID.
public enum IssuerRoute: Equatable {
    case authorize(create: Bool)
    case end
}

/// Cumulus ID (id.cumuluscloud.app) for one product.
public struct CumulusID: Sendable {
    public let product: ProductConfig

    public init(product: ProductConfig) {
        self.product = product
    }

    /// Where Cumulus ID sends the code. System mode: the product's return page. Embedded mode:
    /// the root of the web origin in use (Cumulus ID accepts any path on a registered origin).
    public func redirectURI(home: URL) -> URL {
        if product.signIn == .system, let returnURL = product.returnURL { return returnURL }
        var c = URLComponents()
        c.scheme = home.scheme ?? "https"
        c.host = home.host
        c.port = home.port
        c.path = "/"
        return c.url!
    }

    public func authorizeRequest(issuer: URL, home: URL, create: Bool, pkce: PKCE = PKCE(), state: String = Base64URL.random(16)) -> AuthRequest {
        let redirect = redirectURI(home: home)
        var c = URLComponents(url: issuer.appendingPathComponent("api/id/authorize"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: product.clientId),
            URLQueryItem(name: "redirect_uri", value: redirect.absoluteString),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        if create { items.append(URLQueryItem(name: "prompt", value: "create")) }
        c.queryItems = items
        return AuthRequest(issuer: issuer, url: c.url!, redirectURI: redirect, state: state, pkce: pkce, create: create)
    }

    /// True when `url` is Cumulus ID returning to this request (embedded mode), before it loads.
    public static func isReturn(_ url: URL, for request: AuthRequest) -> Bool {
        guard url.scheme == request.redirectURI.scheme, url.host == request.redirectURI.host,
              url.port == request.redirectURI.port else { return false }
        let path = url.path.isEmpty ? "/" : url.path
        let want = request.redirectURI.path.isEmpty ? "/" : request.redirectURI.path
        guard path == want else { return false }
        let p = callbackParams(url)
        return p.code != nil || p.error != nil
    }

    public static func callbackParams(_ url: URL) -> (code: String?, state: String?, error: String?) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        return (value("code"), value("state"), value("error_description") ?? value("error"))
    }

    /// The issuer and product routes the web app uses for its own Cumulus ID buttons.
    public func route(_ url: URL) -> IssuerRoute? {
        guard let host = url.host?.lowercased(),
              product.issuers.contains(where: { $0.host?.lowercased() == host }) else { return nil }
        switch url.path {
        case "/api/id/authorize":
            return .authorize(create: Self.query(url, "prompt") == "create")
        case "/api/id/end":
            return .end
        default:
            return nil
        }
    }

    static func query(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == name })?.value
    }

    /// Trades the one-time code for a session (POST /api/id/token).
    public func exchange(code: String, request: AuthRequest, session: URLSession = .shared, now: Date = Date()) async throws -> CumulusSession {
        var req = URLRequest(url: request.issuer.appendingPathComponent("api/id/token"))
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("application/json", forHTTPHeaderField: "accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "code": code,
            "code_verifier": request.pkce.verifier,
            "client_id": product.clientId,
            "redirect_uri": request.redirectURI.absoluteString,
        ])
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try Self.parseToken(data, status: status, now: now)
    }

    static func parseToken(_ data: Data, status: Int, now: Date) throws -> CumulusSession {
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status), let token = body["access_token"] as? String, !token.isEmpty else {
            throw CumulusIDError.server((body["error"] as? String) ?? "Cumulus ID answered \(status).")
        }
        let expires = (body["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        var profileJSON = "{}"
        if let profile = body["profile"], JSONSerialization.isValidJSONObject(profile),
           let encoded = try? JSONSerialization.data(withJSONObject: profile),
           let text = String(data: encoded, encoding: .utf8) {
            profileJSON = text
        }
        return CumulusSession(token: token, profileJSON: profileJSON, until: now.addingTimeInterval(expires))
    }

    /// Ends the session at Cumulus ID. Signed out on this device either way.
    public func signOut(_ s: CumulusSession, issuer: URL, session: URLSession = .shared) async {
        var req = URLRequest(url: issuer.appendingPathComponent("api/id/signout"))
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("Bearer \(s.token)", forHTTPHeaderField: "authorization")
        _ = try? await session.data(for: req)
    }

    /// The first issuer that answers, so people in Russia reach the mirror without a VPN.
    public func reachableIssuer(session: URLSession = .shared) async -> URL {
        for issuer in product.issuers.dropLast() {
            if await Self.answers(issuer, session: session) { return issuer }
        }
        return product.issuers.last ?? URL(string: "https://id.cumuluscloud.app")!
    }

    static func answers(_ url: URL, session: URLSession) async -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 5
        guard let (_, response) = try? await session.data(for: req),
              let status = (response as? HTTPURLResponse)?.statusCode else { return false }
        return status < 500
    }
}
