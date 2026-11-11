import SwiftUI
import WebKit

/// Embedded mode: Cumulus ID's own sign-in and create pages, in the app. When Cumulus ID redirects
/// back to the product origin with `?code&state`, the redirect is caught before it loads and the
/// code is traded natively with the PKCE verifier that never left the app.
struct AuthSheet: View {
    @ObservedObject var model: AppModel
    let request: AuthRequest

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(request.create ? "Create a Cumulus ID" : "Sign in with Cumulus ID")
                    .font(Theme.font(15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button("Cancel") { model.cancelSignIn() }
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.ink)
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            AuthWebView(model: model, request: request)
        }
        .background(Theme.paper)
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 640, idealHeight: 720)
        #endif
    }
}

struct AuthWebView: PlatformViewRepresentable {
    let model: AppModel
    let request: AuthRequest

    func makeCoordinator() -> Coordinator { Coordinator(model: model, request: request) }

    #if os(iOS)
    func makeUIView(context: Context) -> WKWebView { make(context) }
    func updateUIView(_ view: WKWebView, context: Context) {}
    #else
    func makeNSView(context: Context) -> WKWebView { make(context) }
    func updateNSView(_ view: WKWebView, context: Context) {}
    #endif

    private func make(_ context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = "InfinitumShell/\(model.product.id)"
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: request.url))
        return web
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let model: AppModel
        let request: AuthRequest
        private var done = false

        init(model: AppModel, request: AuthRequest) {
            self.model = model
            self.request = request
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            if CumulusID.isReturn(url, for: request) {
                if !done {
                    done = true
                    model.handleCallback(url)
                }
                return .cancel
            }
            return .allow
        }
    }
}
