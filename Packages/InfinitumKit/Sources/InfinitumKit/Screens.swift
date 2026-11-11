import SwiftUI

/// Signed out: the Cumulus ID sign-in screen. Signed in: the product.
public struct RootView: View {
    @ObservedObject var model: AppModel
    @Environment(\.scenePhase) private var phase

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if let session = model.session {
                ProductScreen(model: model, session: session)
                    .id(session.token)
            } else {
                SignInScreen(model: model)
            }
        }
        .background(Theme.paper)
        .preferredColorScheme(.light)
        .sheet(item: $model.embeddedAuth) { request in
            AuthSheet(model: model, request: request)
        }
        .onOpenURL { model.handleCallback($0) }
        .onChange(of: phase) { _, now in
            if now == .active { model.checkSession() }
        }
    }
}

/// "Sign in with Cumulus ID", and "Create a Cumulus ID" for people without one, in the same flow.
struct SignInScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.product.name)
                    .font(Theme.font(30, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(model.product.tagline)
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 8)
                Rectangle().fill(Theme.hairline).frame(height: 1).padding(.vertical, 28)
                Text("Sign in with your Cumulus ID. No Cumulus ID yet? Create one here and you come straight back signed in.")
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Sign in with Cumulus ID") { model.signIn(create: false) }
                    .buttonStyle(InkButtonStyle(primary: true))
                    .padding(.top, 24)
                    .keyboardShortcut(.defaultAction)
                Button("Create a Cumulus ID") { model.signIn(create: true) }
                    .buttonStyle(InkButtonStyle(primary: false))
                    .padding(.top, 12)
                if model.busy {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for Cumulus ID…").font(Theme.font(14)).foregroundStyle(Theme.muted)
                    }
                    .padding(.top, 20)
                }
                if let note = model.note {
                    Text(note)
                        .font(Theme.font(14))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 20)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Text("Infinitum Corporation®")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 48)
            }
            .disabled(model.busy)
            .frame(maxWidth: 440, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper)
    }
}

/// The product web app under a slim bar: back, forward, reload, and the account menu.
struct ProductScreen: View {
    @ObservedObject var model: AppModel
    let session: CumulusSession
    @StateObject private var web = WebController()

    var body: some View {
        VStack(spacing: 0) {
            bar
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ZStack {
                ProductWebView(model: model, session: session, controller: web)
                if let error = web.loadError {
                    offline(error)
                }
            }
        }
        .background(Theme.paper)
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 520)
        #endif
    }

    private var bar: some View {
        HStack(spacing: 18) {
            Button { web.back() } label: { Image(systemName: "chevron.left") }
                .disabled(!web.canGoBack)
                .accessibilityLabel("Back")
                .keyboardShortcut("[", modifiers: .command)
            Button { web.forward() } label: { Image(systemName: "chevron.right") }
                .disabled(!web.canGoForward)
                .accessibilityLabel("Forward")
                .keyboardShortcut("]", modifiers: .command)
            Spacer()
            Text(model.product.name)
                .font(Theme.font(15, weight: .medium))
                .lineLimit(1)
            Spacer()
            Button { web.reload() } label: { Image(systemName: "arrow.clockwise") }
                .accessibilityLabel("Reload")
                .keyboardShortcut("r", modifiers: .command)
            Menu {
                if let who = session.displayName { Text("Signed in as \(who)") }
                Button("Open in Browser") { AppModel.openExternally(web.webView?.url ?? model.home) }
                #if os(macOS)
                if let ext = model.product.safariExtension {
                    Button("Turn On the Safari Extension…") { SafariExtension.showSettings(ext) }
                }
                #endif
                Button("Sign out", role: .destructive) { model.signOut() }
            } label: {
                Image(systemName: "person.crop.circle")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Account")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Theme.paper)
    }

    private func offline(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Can't connect").font(Theme.font(22, weight: .medium)).foregroundStyle(Theme.ink)
            Text(message).font(Theme.font(15)).foregroundStyle(Theme.muted)
            Button("Try again") {
                model.resetOrigin()
                web.reload()
            }
            .buttonStyle(InkButtonStyle(primary: true))
            .frame(maxWidth: 240)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.paper)
    }
}
