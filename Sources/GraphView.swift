#if os(macOS)
import SwiftUI
import WebKit

/// Obsidian-style 3D graph of the whole library: every page is a node coloured by its topic
/// and sized by its connections, every link between pages (`<a href>` or `[[wikilink]]`, from
/// `LinkIndex`) is an edge. Hovering lights a page's neighbours; clicking flies to it and shows
/// its connections, and "Open page" selects it in the sidebar.
///
/// The page and its renderer (`3d-force-graph`, MIT, which bundles three.js) ship in
/// `Resources/Graph`, so it works offline. The graph updates in place when the index changes.
struct LibraryGraphView: View {
    @EnvironmentObject var store: VaultStore
    var onOpen: (URL) -> Void

    var body: some View {
        if let root = store.rootURL {
            GraphWebView(json: Self.graphJSON(store.links, root: root),
                         focus: store.selectedFileURL.flatMap { store.pageURL(for: $0) }?.standardizedFileURL.path,
                         onOpen: onOpen)
        } else {
            ContentUnavailableView("No library open", systemImage: "point.3.connected.trianglepath.dotted")
        }
    }

    /// `{ nodes: [{id, title, topic, summary}], links: [{source, target}] }`. Pages under `_`
    /// or `.` folders (assets, the template, agent files) and `raw/` sources are left out.
    static func graphJSON(_ links: LinkIndex, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        func topic(of url: URL) -> String? {
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(rootPath + "/") else { return nil }
            let parts = path.dropFirst(rootPath.count + 1).split(separator: "/").map(String.init)
            guard parts.count >= 2,
                  !parts.contains(where: { $0.hasPrefix("_") || $0.hasPrefix(".") || $0 == "raw" })
            else { return nil }
            return parts[0]
        }
        var nodes: [[String: String]] = []
        var ids = Set<String>()
        for page in links.pages.values {
            guard let t = topic(of: page.url) else { continue }
            let id = page.url.standardizedFileURL.path
            let title = page.title.components(separatedBy: " · ").first ?? page.title
            nodes.append(["id": id, "title": title.isEmpty ? page.url.lastPathComponent : title,
                          "topic": t, "summary": page.summary])
            ids.insert(id)
        }
        var edges: [[String: String]] = []
        for (from, targets) in links.outgoing {
            let s = from.standardizedFileURL.path
            guard ids.contains(s) else { continue }
            for to in targets {
                let t = to.standardizedFileURL.path
                if ids.contains(t), t != s { edges.append(["source": s, "target": t]) }
            }
        }
        let object: [String: Any] = ["nodes": nodes, "links": edges]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8) else { return #"{"nodes":[],"links":[]}"# }
        return json
    }
}

private struct GraphWebView: NSViewRepresentable {
    let json: String
    let focus: String?
    var onOpen: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "graph")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        context.coordinator.webView = webView
        context.coordinator.update(self)
        if let page = Bundle.main.url(forResource: "graph", withExtension: "html", subdirectory: "Graph") {
            webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(self)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "graph")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        private var ready = false
        private var sentJSON: String?
        private var focused = false
        private var parent: GraphWebView?

        func update(_ view: GraphWebView) {
            parent = view
            push()
        }

        /// Sends the graph once the page has loaded, and again only when the links changed.
        private func push() {
            guard ready, let webView, let parent, parent.json != sentJSON else { return }
            sentJSON = parent.json
            webView.evaluateJavaScript("window.setGraph(\(parent.json))")
            if !focused, let focus = parent.focus, let data = try? JSONSerialization.data(withJSONObject: [focus]),
               let arg = String(data: data, encoding: .utf8) {
                focused = true
                webView.evaluateJavaScript("window.focusPage(\(arg)[0])")
            }
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            if body["ready"] != nil {
                ready = true
                push()
            } else if let path = body["open"] as? String {
                parent?.onOpen(URL(fileURLWithPath: path))
            }
        }
    }
}
#endif
