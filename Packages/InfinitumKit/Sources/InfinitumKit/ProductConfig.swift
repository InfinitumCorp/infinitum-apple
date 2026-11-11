import Foundation

/// How the native "Sign in with Cumulus ID" button reaches Cumulus ID.
public enum SignInMode: String, Codable, Sendable {
    /// The system browser sheet (ASWebAuthenticationSession). Needs a return page on the product
    /// origin that bounces `?code&state` to `callbackScheme://cid` (rchtch.app/cid-return.html does).
    case system
    /// Cumulus ID opens inside the app and the redirect back to the product origin is caught before
    /// it loads. Works with every origin Cumulus ID already accepts, with no server change.
    case embedded
}

/// One product's settings, read from `Product.json` in the app bundle.
public struct ProductConfig: Codable, Sendable, Equatable {
    /// Short id, e.g. "scalvs". Also the analytics app name and user-agent tag.
    public var id: String
    /// Display name with marks, e.g. "SCALVS.ai".
    public var name: String
    public var tagline: String
    /// Cumulus ID client id (see infinitum-nexus packages/cid/src/id-clients.ts).
    public var clientId: String
    /// The product web app.
    public var home: URL
    /// Mirrors of the web app to try, in order, when `home` cannot be reached (e.g. from Russia).
    public var mirrors: [URL]
    /// Cumulus ID issuers in order of preference; later ones are mirrors reachable without a VPN.
    public var issuers: [URL]
    /// Extra hosts that stay inside the app (besides home and the mirrors).
    public var inAppHosts: [String]
    public var signIn: SignInMode
    /// `.system` only: the https return page Cumulus ID redirects to.
    public var returnURL: URL?
    /// `.system` only: the scheme the return page opens.
    public var callbackScheme: String?
    /// Amplitude page views and sessions. Off for excluded products (VEIL, internal, defense).
    public var analytics: Bool
    /// The web app reads `#cid_handoff=` on first load (:\ARCHITECT\ Podium does).
    public var handoffFragment: Bool
    /// Bundle id of the Safari Web Extension shipped inside this app, if any.
    public var safariExtension: String?

    public init(
        id: String, name: String, tagline: String, clientId: String, home: URL,
        mirrors: [URL] = [], issuers: [URL] = [URL(string: "https://id.cumuluscloud.app")!],
        inAppHosts: [String] = [], signIn: SignInMode = .embedded, returnURL: URL? = nil,
        callbackScheme: String? = nil, analytics: Bool = false, handoffFragment: Bool = false
    ) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.clientId = clientId
        self.home = home
        self.mirrors = mirrors
        self.issuers = issuers
        self.inAppHosts = inAppHosts
        self.signIn = signIn
        self.returnURL = returnURL
        self.callbackScheme = callbackScheme
        self.analytics = analytics
        self.handoffFragment = handoffFragment
    }

    /// The `Product.json` bundled with the app.
    public static func bundled(_ bundle: Bundle = .main) -> ProductConfig {
        guard let url = bundle.url(forResource: "Product", withExtension: "json") else {
            fatalError("Product.json is missing from the app bundle")
        }
        do {
            return try decode(Data(contentsOf: url))
        } catch {
            fatalError("Product.json is invalid: \(error)")
        }
    }

    public static func decode(_ data: Data) throws -> ProductConfig {
        try JSONDecoder().decode(ProductConfig.self, from: data)
    }

    /// Every host the web view keeps in the app. Lowercased.
    public var appHosts: [String] {
        var out = ([home] + mirrors).compactMap { $0.host?.lowercased() }
        out.append(contentsOf: inAppHosts.map { $0.lowercased() })
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    /// True when the URL belongs to this product and should load inside the app.
    public func keepsInApp(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased() else { return false }
        return appHosts.contains(host)
    }

    /// The `sessionStorage` key the shared Cumulus ID button reads (`cumulus-id:<client>`).
    public var storageKey: String { "cumulus-id:\(clientId)" }
}
