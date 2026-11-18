import SwiftUI
import WebKit

/**
 Shows the Payment Web App (or a direct-API GET redirect) in-app. The returnURL comes back to the demo screen, and
 payment app links (upi:, bank apps) open outside the web view.
 */
struct PaymentWebView: UIViewRepresentable {
    let url: URL
    let onReturn: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onReturn: onReturn) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        if #available(iOS 16.4, *) { webView.isInspectable = true } // test app: inspect the page from Safari's Develop menu
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onReturn: () -> Void

        init(onReturn: @escaping () -> Void) { self.onReturn = onReturn }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }
            if url.absoluteString.hasPrefix(returnURL) {
                decisionHandler(.cancel)
                onReturn()
            } else if url.scheme == "http" || url.scheme == "https" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
                UIApplication.shared.open(url)
            }
        }

        // Path only: query strings carry the token.
        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let httpResponse = response.response as? HTTPURLResponse, httpResponse.statusCode >= 400, let url = httpResponse.url {
                print("SynqtDemo HTTP \(httpResponse.statusCode) \(url.host ?? "")\(url.path)")
            }
            decisionHandler(.allow)
        }
    }
}
