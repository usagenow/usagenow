import SwiftUI
import WebKit

/// Created only after an explicit Sign In click. No existing browser
/// profile, app database, environment token or browser Keychain is read.
struct ProviderBrowserSignIn: View {
    let definition: ProviderDefinition
    let connected: (String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session: ProviderLoginSession
    @State private var checking = false
    @State private var failure: String?
    @State private var checkTask: Task<Void, Never>?

    init(definition: ProviderDefinition, connected: @escaping (String) throws -> Void) {
        self.definition = definition
        self.connected = connected
        _session = StateObject(wrappedValue: ProviderLoginSession(connection: definition.apiKey!))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to \(definition.displayName)").font(.headline)
                Spacer()
                Label(session.host, systemImage: "lock.fill")
                    .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .padding(14)
            Divider()
            LoginWebView(webView: session.webView)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Sign in on the official website, then click Connect. Save the connection in Settings to keep only its session cookie in Keychain. If this window cannot sign you in, cancel and use a session cookie from your browser.")
                    .font(.callout).foregroundStyle(.secondary)
                if let failure { Text(failure).font(.callout).foregroundStyle(.red) }
                HStack {
                    Button("Reload") { session.webView.reload() }.disabled(checking)
                    Spacer()
                    Button("Cancel", role: .cancel) { close() }.keyboardShortcut(.cancelAction)
                    if checking { ProgressView().controlSize(.small) }
                    Button("Connect", action: connect).disabled(checking)
                }
            }
            .padding(14)
        }
        .frame(width: 720, height: 620)
        .onDisappear { checkTask?.cancel(); session.webView.stopLoading() }
    }

    private func close() { checkTask?.cancel(); session.webView.stopLoading(); dismiss() }

    private func connect() {
        guard let connection = definition.apiKey else { return }
        checking = true
        failure = nil
        checkTask = Task { @MainActor in
            defer { checking = false }
            do {
                let cookies = await session.webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                let credential = try LoginCookieSelection.select(cookies, connection: connection)
                // A cookie's presence alone isn't proof of a completed login.
                _ = try await ProviderConnectionVerifier().verify(credential, for: definition.id)
                try Task.checkCancellation()
                try connected(credential)
                dismiss()
            } catch is CancellationError {
                // Cancel must never persist a credential or display an error.
            } catch APIKeyClient.Failure.invalidCredential {
                failure = String(localized: "No valid session yet. Finish signing in, or use the manual session cookie option.")
            } catch {
                // Never display raw provider responses or URLs containing
                // OAuth callback parameters in errors or logs.
                failure = ConnectionCheckFailure(error).message
            }
        }
    }
}

@MainActor
private final class ProviderLoginSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    @Published var host: String

    init(connection: APIKeyConnection) {
        host = connection.keysPage.host ?? connection.host
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: connection.keysPage))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Official SSO may navigate to another HTTPS identity provider.
        // Never hand arbitrary custom schemes, local files or downloads to
        // macOS, and never override TLS validation or the browser User-Agent.
        guard let url = navigationAction.request.url, url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return .cancel }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        host = webView.url?.host ?? ""
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, navigationAction.request.url?.scheme == "https" {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

private struct LoginWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// Reused by the first-account and additional-account credential sheets.
struct ConnectionCredentialField: View {
    let definition: ProviderDefinition
    @Binding var credential: String
    @State private var showsBrowser = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if definition.apiKey?.authentication.isSession == true {
                Button("Sign In…") { showsBrowser = true }
                if !credential.isEmpty {
                    Text("Save to finish connecting.").font(.callout).foregroundStyle(.secondary)
                }
                Text("Or paste a named session cookie (name=value):")
                    .font(.callout).foregroundStyle(.secondary)
            }
            SecureField(text: $credential) {
                Text(definition.apiKey?.credentialTitle ?? "API key")
            }
            .textFieldStyle(.roundedBorder)
        }
        .sheet(isPresented: $showsBrowser) {
            ProviderBrowserSignIn(definition: definition) { credential = $0 }
        }
    }
}
