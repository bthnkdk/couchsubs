// SPDX-License-Identifier: AGPL-3.0-only

import RemotePlay
import SwiftUI
import WebKit

struct PSNLoginStep: View {
    @Environment(AppModel.self) private var model
    @State private var showLogin = false
    @State private var working = false
    @State private var error: String?
    /// Pencere yönlendirmeyi yakaladı mı; yakalamadan kapanırsa kullanıcıya söylenir (eskiden sessizdi).
    @State private var redirected = false
    /// Giriş sayfasının son sorunu (açılamadı, Sony'nin HTTP hatası).
    @State private var pageProblem: String?

    var body: some View {
        StepLayout(symbol: "person.crop.circle.badge.checkmark", title: "Sign in with the second account",
                   message: "Sign in to PlayStation Network with the second account you just created. Your password goes directly to Sony; CouchSubs only keeps the account ID.") {
            VStack(alignment: .leading, spacing: Theme.space("m")) {
                if model.accountId != nil {
                    DoneLabel(text: String(localized: "Signed in"))
                }
                Button(model.accountId == nil ? "Sign in" : "Sign in again") {
                    redirected = false
                    pageProblem = nil
                    showLogin = true
                }
                .buttonStyle(CSButtonStyle(kind: model.accountId == nil ? .primary : .secondary))
                .disabled(working)
                if working { ProgressView().controlSize(.small) }
                ErrorText(error: error).textSelection(.enabled)
            }
        }
        .sheet(isPresented: $showLogin, onDismiss: sheetClosed) {
            PSNLoginSheet(onRedirect: received, onProblem: { pageProblem = $0 })
        }
    }

    /// Pencere yönlendirmesiz kapandıysa nedeni söylenir (eskiden sessizce dönülüyordu).
    private func sheetClosed() {
        guard !redirected else { return }
        let failure: Error = model.loginWindowError(problem: pageProblem)
        error = failure.localizedDescription
    }

    private func received(_ url: URL) {
        redirected = true
        showLogin = false
        working = true
        error = nil
        Task {
            do { try await model.completePSNLogin(redirect: url) } catch { self.error = error.localizedDescription }
            working = false
        }
    }
}

/// Sony'nin giriş sayfasını açar; giriş bitince yönlendirme adresini yakalar.
struct PSNLoginSheet: View {
    let onRedirect: (URL) -> Void
    /// Sayfa açılamadı ya da Sony hata kodu döndürdü (nil: sorun giderildi).
    let onProblem: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: "PlayStation Network").font(.csHeadline)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.secondary)
            }
            .padding(Theme.space("m"))
            Divider()
            LoginWebView(onRedirect: onRedirect, onProblem: onProblem)
        }
        .frame(width: 520, height: 680)
    }
}

struct LoginWebView: NSViewRepresentable {
    let onRedirect: (URL) -> Void
    let onProblem: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onRedirect: onRedirect, onProblem: onProblem) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: PSNAccount.authorizeURL))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onRedirect: (URL) -> Void
        let onProblem: (String?) -> Void
        private var redirected = false

        init(onRedirect: @escaping (URL) -> Void, onProblem: @escaping (String?) -> Void) {
            self.onRedirect = onRedirect
            self.onProblem = onProblem
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            // Kodlu ya da Sony'nin hatasını taşıyan her yönlendirme yakalanır; eskiden hatalı yönlendirme boş sayfada kalıyordu.
            if let url = action.request.url, !redirected,
               PSNAccount.code(fromRedirect: url) != nil || PSNAccount.error(fromRedirect: url) != nil {
                redirected = true
                onRedirect(url)
                return .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            if response.isForMainFrame, let http = response.response as? HTTPURLResponse {
                if http.statusCode >= 400 {
                    RemotePlayLog.write("PSN giriş sayfası: HTTP \(http.statusCode)")
                    onProblem("HTTP \(http.statusCode)")
                } else {
                    onProblem(nil)
                }
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        private func report(_ error: Error) {
            // Yönlendirmeyi kendimiz iptal ediyoruz; o bir sorun değildir.
            let nsError = error as NSError
            let canceled = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
            // WebKitErrorFrameLoadInterruptedByPolicyChange: yönlendirmeyi iptal etmemiz.
            let interrupted = nsError.domain == "WebKitErrorDomain" && nsError.code == 102
            if redirected || canceled || interrupted { return }
            RemotePlayLog.write("PSN giriş sayfası açılamadı: \(nsError.domain) \(nsError.code) \(nsError.localizedDescription)")
            onProblem(nsError.localizedDescription)
        }
    }
}
