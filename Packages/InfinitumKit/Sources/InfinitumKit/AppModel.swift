import AuthenticationServices
import Foundation
import SwiftUI
import WebKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// App state: the Cumulus ID session, sign-in in progress, and which web origin is in use.
@MainActor
public final class AppModel: ObservableObject {
    public let product: ProductConfig
    public let cid: CumulusID
    public let analytics: ProductAnalytics

    @Published public private(set) var session: CumulusSession?
    @Published public var note: String?
    @Published public private(set) var busy = false
    /// Embedded mode: the sign-in sheet is up while this is set.
    @Published public var embeddedAuth: AuthRequest?
    /// The web origin in use: `home`, or a mirror after `home` failed to load.
    @Published public private(set) var home: URL

    private let store: SessionStore
    private var pending: AuthRequest?
    private var issuer: URL
    private var webAuth: ASWebAuthenticationSession?
    private let anchor = AnchorProvider()

    public init(product: ProductConfig, bundle: Bundle = .main) {
        self.product = product
        self.cid = CumulusID(product: product)
        self.home = product.home
        self.issuer = product.issuers.first ?? URL(string: "https://id.cumuluscloud.app")!
        self.store = SessionStore(service: (bundle.bundleIdentifier ?? "app.infinitum.\(product.id)") + ".cumulus-id")
        let key = bundle.object(forInfoDictionaryKey: "AmplitudeAPIKey") as? String
        self.analytics = ProductAnalytics(product: product, apiKey: key)
        if let saved = store.load(), saved.isValid() {
            session = saved
        } else {
            store.clear()
        }
    }

    // MARK: Sign in

    /// "Sign in with Cumulus ID" (create: false) or "Create a Cumulus ID" (create: true). A new
    /// Cumulus ID comes straight back here signed in.
    public func signIn(create: Bool) {
        guard !busy else { return }
        busy = true
        note = nil
        Task { await begin(create: create) }
    }

    private func begin(create: Bool) async {
        issuer = await cid.reachableIssuer()
        let request = cid.authorizeRequest(issuer: issuer, home: home, create: create)
        pending = request
        switch product.signIn {
        case .embedded:
            embeddedAuth = request
        case .system:
            guard let scheme = product.callbackScheme else {
                fail("This app has no sign-in return address.")
                return
            }
            let session = ASWebAuthenticationSession(url: request.url, callbackURLScheme: scheme) { [weak self] url, error in
                Task { @MainActor in self?.finishSystem(url: url, error: error) }
            }
            session.presentationContextProvider = anchor
            session.prefersEphemeralWebBrowserSession = false
            webAuth = session
            if !session.start() { fail("Sign-in could not start. Please try again.") }
        }
    }

    private func finishSystem(url: URL?, error: Error?) {
        webAuth = nil
        if let url {
            handleCallback(url)
        } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
            pending = nil
            busy = false
        } else {
            fail(error?.localizedDescription ?? "Sign-in was cancelled.")
        }
    }

    /// The code coming back: from the embedded sheet, the system sheet, or `onOpenURL`.
    public func handleCallback(_ url: URL) {
        guard let request = pending else { return }
        pending = nil
        embeddedAuth = nil
        let params = CumulusID.callbackParams(url)
        if let error = params.error {
            fail(error)
            return
        }
        guard let code = params.code, params.state == request.state else {
            fail(CumulusIDError.mismatch.localizedDescription)
            return
        }
        Task {
            do {
                let signedIn = try await cid.exchange(code: code, request: request)
                store.save(signedIn)
                session = signedIn
                busy = false
            } catch {
                fail("Sign-in failed: \(error.localizedDescription)")
            }
        }
    }

    public func cancelSignIn() {
        pending = nil
        embeddedAuth = nil
        webAuth?.cancel()
        webAuth = nil
        busy = false
    }

    private func fail(_ message: String) {
        pending = nil
        embeddedAuth = nil
        busy = false
        note = message
    }

    // MARK: Session

    /// Signs out here and at Cumulus ID, and clears the web app's stored data.
    public func signOut(note: String? = "Signed out.") {
        let old = session
        session = nil
        store.clear()
        self.note = note
        let issuer = self.issuer
        let cid = self.cid
        Task {
            if let old { await cid.signOut(old, issuer: issuer) }
        }
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
    }

    /// Called when the app comes forward: an expired session goes back to the sign-in screen.
    public func checkSession() {
        if let s = session, !s.isValid() {
            signOut(note: "Your session ended. Please sign in again.")
        }
    }

    // MARK: Web origin

    /// The main page failed to load. Returns true when a mirror is next to try.
    public func tryNextMirror() -> Bool {
        let all = [product.home] + product.mirrors
        guard let i = all.firstIndex(where: { $0.host == home.host }), i + 1 < all.count else { return false }
        home = all[i + 1]
        return true
    }

    public func resetOrigin() {
        home = product.home
    }

    // MARK: Opening things outside the app

    public static func openExternally(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }
}

/// The window the system sign-in sheet attaches to.
final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if os(iOS)
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
            return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
            #else
            return NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
            #endif
        }
    }
}
