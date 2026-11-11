import SwiftUI
import WebKit
#if os(iOS)
import UIKit
typealias PlatformViewRepresentable = UIViewRepresentable
#else
import AppKit
typealias PlatformViewRepresentable = NSViewRepresentable
#endif

/// Drives the product web view from the bar above it.
@MainActor
public final class WebController: ObservableObject {
    @Published public var canGoBack = false
    @Published public var canGoForward = false
    @Published public var isLoading = false
    /// Set when the page (and every mirror) could not be reached.
    @Published public var loadError: String?
    weak var webView: WKWebView?

    public init() {}

    public func back() { webView?.goBack() }
    public func forward() { webView?.goForward() }
    public func reload() {
        loadError = nil
        if webView?.url == nil, let start = startURL { webView?.load(URLRequest(url: start)) } else { webView?.reload() }
    }
    var startURL: URL?

    func load(_ url: URL) {
        startURL = url
        loadError = nil
        webView?.load(URLRequest(url: url))
    }

    func sync() {
        canGoBack = webView?.canGoBack ?? false
        canGoForward = webView?.canGoForward ?? false
        isLoading = webView?.isLoading ?? false
    }
}

/// The product web app, signed in with the native Cumulus ID session.
struct ProductWebView: PlatformViewRepresentable {
    @ObservedObject var model: AppModel
    let session: CumulusSession
    let controller: WebController

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, controller: controller)
    }

    #if os(iOS)
    func makeUIView(context: Context) -> WKWebView { make(context) }
    func updateUIView(_ view: WKWebView, context: Context) { update(view, context) }
    #else
    func makeNSView(context: Context) -> WKWebView { make(context) }
    func updateNSView(_ view: WKWebView, context: Context) { update(view, context) }
    #endif

    private func make(_ context: Context) -> WKWebView {
        let product = model.product
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = "InfinitumShell/\(product.id)"
        config.userContentController.addUserScript(WKUserScript(
            source: Handoff.sessionScript(product: product, session: session),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        #if os(iOS)
        config.allowsInlineMediaPlayback = true
        #endif
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        #if os(iOS)
        web.backgroundColor = .white
        web.isOpaque = false
        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.pulled(_:)), for: .valueChanged)
        web.scrollView.refreshControl = refresh
        #else
        web.setValue(false, forKey: "drawsBackground")
        #endif
        controller.webView = web
        context.coordinator.loadedHome = model.home
        controller.load(Handoff.startURL(product: product, home: model.home, session: session))
        return web
    }

    private func update(_ view: WKWebView, _ context: Context) {
        // A mirror took over after the main origin failed: load it.
        if context.coordinator.loadedHome != model.home {
            context.coordinator.loadedHome = model.home
            controller.load(Handoff.startURL(product: model.product, home: model.home, session: session))
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: AppModel
        let controller: WebController
        var loadedHome: URL?

        init(model: AppModel, controller: WebController) {
            self.model = model
            self.controller = controller
        }

        #if os(iOS)
        @objc func pulled(_ sender: UIRefreshControl) {
            controller.reload()
            sender.endRefreshing()
        }
        #endif

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            // The web app's own Cumulus ID buttons: sign in, create, or sign out natively.
            if let route = model.cid.route(url) {
                switch route {
                case .authorize(let create): model.signIn(create: create)
                case .end: model.signOut()
                }
                return .cancel
            }
            let scheme = url.scheme?.lowercased() ?? ""
            if ["about", "blob", "data", "javascript"].contains(scheme) { return .allow }
            let mainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            if !mainFrame && (scheme == "https" || scheme == "http") { return .allow }
            if model.product.keepsInApp(url) { return .allow }
            // Anything else (other sites, mail, phone, app links) opens outside the app.
            AppModel.openExternally(url)
            return .cancel
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            controller.sync()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            controller.loadError = nil
            controller.sync()
            if let url = webView.url { model.analytics.pageView(url) }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            controller.sync()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            controller.sync()
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
            if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return } // frame load interrupted by policy
            if model.tryNextMirror() { return }
            let host = model.home.host ?? model.home.absoluteString
            controller.loadError = "Can't reach \(host). \(error.localizedDescription)"
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }

        // target=_blank and window.open
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                if model.product.keepsInApp(url) { webView.load(navigationAction.request) } else { AppModel.openExternally(url) }
            }
            return nil
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
            await Panels.alert(message, title: model.product.name)
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
            await Panels.confirm(message, title: model.product.name)
        }
    }
}

/// JavaScript alert() and confirm() as native dialogs.
@MainActor
enum Panels {
    static func alert(_ message: String, title: String) async {
        _ = await show(message, title: title, cancel: false)
    }

    static func confirm(_ message: String, title: String) async -> Bool {
        await show(message, title: title, cancel: true)
    }

    private static func show(_ message: String, title: String, cancel: Bool) async -> Bool {
        #if os(iOS)
        guard let top = topController() else { return !cancel }
        return await withCheckedContinuation { done in
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            if cancel { alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done.resume(returning: false) }) }
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in done.resume(returning: true) })
            top.present(alert, animated: true)
        }
        #else
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if cancel { alert.addButton(withTitle: "Cancel") }
        return alert.runModal() == .alertFirstButtonReturn
        #endif
    }

    #if os(iOS)
    private static func topController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        var top = (windows.first(where: \.isKeyWindow) ?? windows.first)?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
    #endif
}
