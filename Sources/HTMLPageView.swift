import SwiftUI
import WebKit

/// Renders one HTML page of the library in a WKWebView, like a Claude artifact.
///
/// - Read access covers the whole library, so relative links, images and pages in sibling
///   folders resolve.
/// - Clicking a link to another file in the library calls `onOpenLocal` instead of
///   navigating, so the sidebar selection follows; web links open in the default browser.
/// - `[[Wiki Links]]` resolve and internal links get Obsidian-style styling and hover
///   previews via `linkScript`.
/// - When `revision` (the file's modification date) changes — the agent or the source editor
///   rewrote the page — it reloads in place.
struct HTMLPageView {
    let url: URL
    let readAccessURL: URL
    var revision: Date?
    /// Script run after each load — the library's wikilink/backlink layer (`LinkIndex.script`).
    var linkScript: String? = nil
    var onOpenLocal: (URL) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func makeWebView(_ coordinator: Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        if #available(macOS 13.3, iOS 16.4, *) { webView.isInspectable = true }
        #if os(macOS)
        webView.allowsMagnification = true
        #endif
        return webView
    }

    private func load(_ webView: WKWebView, _ coordinator: Coordinator) {
        coordinator.parent = self
        if coordinator.loadedURL != url {
            coordinator.loadedURL = url
            coordinator.loadedRevision = revision
            coordinator.retries = 0
            webView.loadFileURL(url, allowingReadAccessTo: readAccessURL)
        } else if coordinator.loadedRevision != revision {
            // Re-issue loadFileURL rather than reload(): WebKit can drop the file read-access
            // grant on reload() and render a blank page after the agent rewrites the file.
            coordinator.loadedRevision = revision
            let url = url, readAccessURL = readAccessURL
            // Keep the reader's place: adding a tag rewrites the file too.
            webView.evaluateJavaScript("window.scrollY") { offset, _ in
                coordinator.restoreScrollY = (offset as? NSNumber)?.doubleValue
                webView.loadFileURL(url, allowingReadAccessTo: readAccessURL)
            }
        } else if webView.url == nil, !webView.isLoading {
            // Nothing on screen (an earlier load failed or the web process died): load again.
            coordinator.reload(webView)
        } else if coordinator.finished, coordinator.appliedScript != linkScript {
            coordinator.applyScript(webView)   // the link index was rebuilt
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: HTMLPageView
        var loadedURL: URL?
        var loadedRevision: Date?
        var appliedScript: String?
        var finished = false
        /// Scroll offset to return to once a rewritten page has reloaded.
        var restoreScrollY: Double?

        init(_ parent: HTMLPageView) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            finished = false
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finished = true
            retries = 0
            applyScript(webView)
            if let y = restoreScrollY {
                restoreScrollY = nil
                webView.evaluateJavaScript("window.scrollTo(0, \(y))")
            }
        }

        // MARK: Blank-page recovery
        // WebKit leaves the view white when its content process is killed (memory pressure,
        // long idle) or when a load fails — e.g. the agent is mid-way through rewriting the
        // file. Load the page again instead of staying blank.

        var retries = 0

        func reload(_ webView: WKWebView) {
            guard let url = loadedURL else { return }
            finished = false
            webView.loadFileURL(url, allowingReadAccessTo: parent.readAccessURL)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            reload(webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            retryAfterFailure(webView, error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            retryAfterFailure(webView, error)
        }

        private func retryAfterFailure(_ webView: WKWebView, _ error: Error) {
            // A newer load replacing this one is not a failure.
            if (error as NSError).code == NSURLErrorCancelled { return }
            guard retries < 3 else { return }
            retries += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 * Double(retries)) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.reload(webView)
            }
        }

        func applyScript(_ webView: WKWebView) {
            appliedScript = parent.linkScript
            guard let script = parent.linkScript, !script.isEmpty else { return }
            webView.evaluateJavaScript(script) { _, error in
                if let error { print("wikilink script:", error.localizedDescription) }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType == .linkActivated, let target = action.request.url else {
                decisionHandler(.allow); return
            }
            decisionHandler(route(target) ? .cancel : .allow)
        }

        /// `target="_blank"` links arrive here rather than as a navigation.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let target = action.request.url, !route(target) { webView.load(action.request) }
            return nil
        }

        /// Handles a clicked link; returns true when it was taken care of outside the view.
        private func route(_ target: URL) -> Bool {
            if target.isFileURL {
                // Same page, different #anchor: let the web view scroll.
                if target.standardizedFileURL.path == loadedURL?.standardizedFileURL.path { return false }
                var parts = URLComponents(url: target, resolvingAgainstBaseURL: false)
                parts?.fragment = nil
                parent.onOpenLocal((parts?.url ?? target).standardizedFileURL)
                return true
            }
            if let scheme = target.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
                #if os(macOS)
                NSWorkspace.shared.open(target)
                #else
                UIApplication.shared.open(target)
                #endif
                return true
            }
            return false
        }
    }
}

#if os(macOS)
extension HTMLPageView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let webView = makeWebView(context.coordinator)
        load(webView, context.coordinator)
        return webView
    }
    func updateNSView(_ webView: WKWebView, context: Context) { load(webView, context.coordinator) }
}
#else
extension HTMLPageView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let webView = makeWebView(context.coordinator)
        load(webView, context.coordinator)
        return webView
    }
    func updateUIView(_ webView: WKWebView, context: Context) { load(webView, context.coordinator) }
}
#endif
