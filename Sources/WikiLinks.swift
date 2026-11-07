import Foundation

/// Obsidian-style cross-links for the HTML library.
///
/// - Every local `<a href>` between pages and every `[[Page Name]]` / `[[page|label]]`
///   wikilink counts as a link, so each page gets **backlinks** ("linked mentions") for free.
/// - `[[…]]` resolves by page title, file name (`agentic-loop`) or folder name (for a
///   folder's `index.html`), case- and punctuation-insensitively.
/// - The page view uses `script(for:)` to turn `[[…]]` into real links, style internal links
///   like Obsidian and show a hover preview card.
struct LinkIndex: Sendable {
    struct Page: Sendable, Hashable {
        let url: URL
        let title: String
        let summary: String
        var tags: [String] = []
        /// `<meta name="keywords">`: the page's concepts, synonyms, symbols and other names,
        /// lowercased. The sidebar search matches them, so a page is found by any of its names.
        var keywords: [String] = []
    }

    struct TagCount: Sendable, Hashable, Identifiable {
        let tag: String
        let count: Int
        var id: String { tag }
    }

    private(set) var pages: [URL: Page] = [:]
    /// Every tag in the library with its page count, by name.
    private(set) var tagList: [TagCount] = []
    private(set) var outgoing: [URL: [URL]] = [:]
    private(set) var incoming: [URL: [URL]] = [:]
    /// Normalised name → page.
    private(set) var names: [String: URL] = [:]
    /// The page script, built once per index (it is the same for every page).
    private(set) var pageScript = ""

    func backlinks(to url: URL) -> [Page] {
        (incoming[url.standardizedFileURL] ?? []).compactMap { pages[$0] }.sorted { $0.title < $1.title }
    }

    func outlinks(from url: URL) -> [Page] {
        (outgoing[url.standardizedFileURL] ?? []).compactMap { pages[$0] }.sorted { $0.title < $1.title }
    }

    func resolve(_ name: String) -> URL? { names[Self.normalize(name)] }

    /// Applies an edit straight away, ahead of the background rebuild.
    mutating func setTags(_ tags: [String], for url: URL) {
        pages[url.standardizedFileURL]?.tags = tags
        rebuildTagList()
    }

    private mutating func rebuildTagList() {
        var counts: [String: Int] = [:]
        for page in pages.values {
            for tag in page.tags { counts[tag, default: 0] += 1 }
        }
        tagList = counts.map { TagCount(tag: $0.key, count: $0.value) }
            .sorted { $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
    }

    static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: ".html", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: Building

    /// A page's text as last read, with what identifies that version of the file.
    private struct CachedText {
        let modified: Date?
        let size: Int?
        let text: String
    }

    private final class TextCache: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [URL: CachedText] = [:]
        var contents: [URL: CachedText] {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    /// Lets a rebuild read only the pages that changed. In iCloud Drive macOS can remove a page's
    /// local copy at any time, and reading it again would wait for a download, so an unchanged
    /// page must not be touched just because some other file changed.
    private static let textCache = TextCache()

    /// Scans every HTML page under `root` (skipping hidden and `_`-prefixed files). Cheap
    /// enough to run on each refresh for libraries of a few thousand pages; call it off the
    /// main thread.
    static func build(root: URL) -> LinkIndex {
        var index = LinkIndex()
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: root,
                                         includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
                                         options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return index }
        var files: [(URL, String)] = []
        let known = textCache.contents
        var seen: [URL: CachedText] = [:]
        defer { textCache.contents = seen }
        for case let url as URL in walker {
            let name = url.lastPathComponent
            if name.hasPrefix("_") { if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { walker.skipDescendants() }; continue }
            guard ["html", "htm"].contains(url.pathExtension.lowercased()) else { continue }
            let page = url.standardizedFileURL
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let text: String
            if let cached = known[page], let values, cached.modified == values.contentModificationDate, cached.size == values.fileSize {
                text = cached.text
            } else if let read = try? String(contentsOf: url, encoding: .utf8) {
                text = read
            } else {
                continue
            }
            seen[page] = CachedText(modified: values?.contentModificationDate, size: values?.fileSize, text: text)
            files.append((page, text))
            let title = firstMatch(#"(?is)<title[^>]*>(.*?)</title>"#, in: text).map(decode) ?? name
            let summary = firstMatch(#"(?is)<meta\s+name="description"\s+content="([^"]*)""#, in: text).map(decode) ?? ""
            // raw/ holds immutable sources: a saved web page's own tags aren't library tags.
            let tags = TopicLibrary.isSource(page, root: root) ? [] : PageTags.read(from: text)
            let keywords = firstMatch(#"(?is)<meta\s+name="keywords"\s+content="([^"]*)""#, in: text)
                .map { decode($0).lowercased().split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } } ?? []
            index.pages[page] = Page(url: page, title: title, summary: summary, tags: tags, keywords: keywords)
        }
        index.rebuildTagList()

        // Names: file stem, folder name for index pages (with and without "NN "), title.
        // Titles register last only if free, so file names win on collisions.
        for page in index.pages.keys.sorted(by: { $0.path < $1.path }) {
            let stem = page.deletingPathExtension().lastPathComponent
            if stem.lowercased() == "index" {
                let folder = page.deletingLastPathComponent().lastPathComponent
                index.register(folder, page)
                index.register(TopicLibrary.prettyFolderName(folder), page)
            } else {
                index.register(stem, page)
            }
        }
        for (url, page) in index.pages {
            index.register(page.title, url, overwrite: false)
            // "Scenario 1 · Customer Support … · CCAR-F" → also "Customer Support …"
            for part in page.title.components(separatedBy: " · ") where part.count > 3 {
                index.register(part, url, overwrite: false)
            }
        }

        for (page, text) in files {
            var targets = Set<URL>()
            for href in allMatches(#"(?i)<a\b[^>]*\bhref="([^"]+)""#, in: text) {
                if let t = index.resolveHref(href, from: page) { targets.insert(t) }
            }
            for link in allMatches(#"\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|[^\]]*)?\]\]"#, in: text) {
                if let t = index.resolve(link) { targets.insert(t) }
            }
            targets.remove(page)
            let sorted = targets.sorted { $0.path < $1.path }
            index.outgoing[page] = sorted
            for t in sorted { index.incoming[t, default: []].append(page) }
        }
        index.pageScript = index.makeScript()
        return index
    }

    private mutating func register(_ name: String, _ url: URL, overwrite: Bool = true) {
        let key = Self.normalize(name)
        guard !key.isEmpty else { return }
        if overwrite || names[key] == nil { names[key] = url }
    }

    private func resolveHref(_ href: String, from page: URL) -> URL? {
        let raw = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? href
        guard !raw.isEmpty, !raw.contains(":") || raw.hasPrefix("file:") else { return nil }
        let target: URL
        if raw.hasPrefix("file:") {
            guard let u = URL(string: raw) else { return nil }
            target = u
        } else {
            let path = raw.split(separator: "?").first.map(String.init) ?? raw
            target = URL(fileURLWithPath: path.removingPercentEncoding ?? path,
                         relativeTo: page.deletingLastPathComponent())
        }
        var t = target.standardizedFileURL
        if pages[t] == nil { t = t.appendingPathComponent("index.html").standardizedFileURL }
        return pages[t] == nil ? nil : t
    }

    // MARK: Page script

    /// JavaScript run after a page loads: styles internal/external links, resolves `[[…]]`
    /// and adds Obsidian-style hover previews.
    func script(for page: URL) -> String { pageScript }

    private func makeScript() -> String {
        var list: [[String: String]] = []
        var position: [URL: Int] = [:]
        for (url, p) in pages {
            position[url] = list.count
            list.append(["u": url.absoluteString, "t": p.title, "d": p.summary])
        }
        let nameMap = names.compactMapValues { position[$0] }
        let payload: [String: Any] = ["pages": list, "names": nameMap]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return "(\(Self.js))(\(json));"
    }

    private static let js = #"""
    function (data) {
      const norm = s => s.toLowerCase().replace(/\.html$/, '').replace(/[^a-z0-9]+/g, ' ').trim();
      // Idempotent: re-running (e.g. after the index is rebuilt) refreshes the data only.
      const byURL = {};
      data.pages.forEach(p => { byURL[p.u] = p; });
      window.__ttByURL = byURL;
      if (!document.getElementById('tt-wikilinks')) {
        const st = document.createElement('style');
        st.id = 'tt-wikilinks';
        st.textContent = `
          a.wikilink { color: var(--accent, #6d4aff); text-decoration: none;
            border-bottom: 1px solid color-mix(in srgb, var(--accent, #6d4aff) 35%, transparent); }
          a.wikilink:hover { border-bottom-color: currentColor; text-decoration: none; }
          .wikilink.unresolved { color: var(--muted, #888); border-bottom: 1px dashed currentColor; cursor: help; }
          a.external-link::after { content: "↗"; font-size: .72em; margin-left: 2px; opacity: .65; }
          #tt-preview { position: fixed; z-index: 9999; max-width: 340px; padding: 12px 14px; border-radius: 12px;
            background: var(--card, #fff); color: var(--ink, #222); border: 1px solid var(--line, #ddd);
            box-shadow: 0 10px 30px rgba(0,0,0,.18); font: 13px/1.5 -apple-system, BlinkMacSystemFont, sans-serif;
            pointer-events: none; opacity: 0; transition: opacity .12s; }
          #tt-preview.on { opacity: 1; }
          #tt-preview b { display: block; font-size: 14px; margin-bottom: 4px; }
          #tt-preview span { color: var(--muted, #777); }`;
        document.head.appendChild(st);
      }
      // [[Target]], [[Target|label]], [[Target#anchor]] in text (not in code).
      const skip = /^(CODE|PRE|SCRIPT|STYLE|TEXTAREA|A)$/;
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
        acceptNode(n) {
          if (!n.nodeValue.includes('[[')) return NodeFilter.FILTER_REJECT;
          for (let p = n.parentElement; p; p = p.parentElement) if (skip.test(p.tagName)) return NodeFilter.FILTER_REJECT;
          return NodeFilter.FILTER_ACCEPT;
        }
      });
      const textNodes = [];
      while (walker.nextNode()) textNodes.push(walker.currentNode);
      const re = /\[\[([^\]|#]+)(#[^\]|]*)?(?:\|([^\]]+))?\]\]/g;
      textNodes.forEach(n => {
        const text = n.nodeValue, frag = document.createDocumentFragment();
        let last = 0, m;
        re.lastIndex = 0;
        while ((m = re.exec(text))) {
          frag.appendChild(document.createTextNode(text.slice(last, m.index)));
          const idx = data.names[norm(m[1])];
          const label = (m[3] || m[1]).trim();
          let el;
          if (idx !== undefined) {
            el = document.createElement('a');
            el.href = data.pages[idx].u + (m[2] || '');
          } else {
            el = document.createElement('span');
            el.classList.add('unresolved');
            el.title = 'No page named “' + m[1].trim() + '” yet';
          }
          el.classList.add('wikilink');
          el.textContent = label;
          frag.appendChild(el);
          last = re.lastIndex;
        }
        frag.appendChild(document.createTextNode(text.slice(last)));
        n.parentNode.replaceChild(frag, n);
      });
      // Style every link: internal (wikilink) vs external.
      document.querySelectorAll('a[href]').forEach(a => {
        if (a.closest('.crumbs') || a.classList.contains('card')) return;
        const h = a.getAttribute('href');
        if (/^https?:/i.test(h)) a.classList.add('external-link');
        else if (!h.startsWith('#') && !/^mailto:/i.test(h)) a.classList.add('wikilink');
      });
      // Hover preview for internal links.
      let card = document.getElementById('tt-preview');
      if (!card) { card = document.createElement('div'); card.id = 'tt-preview'; document.body.appendChild(card); }
      if (window.__ttHooked) return;
      window.__ttHooked = true;
      let timer;
      const target = a => {
        const u = a.href.split('#')[0], m = window.__ttByURL;
        return m[u] || m[u.replace(/\/$/, '') + '/index.html'];
      };
      document.addEventListener('mouseover', e => {
        const a = e.target.closest && e.target.closest('a[href]');
        if (!a) return;
        const p = target(a);
        if (!p) return;
        clearTimeout(timer);
        timer = setTimeout(() => {
          card.innerHTML = '';
          const b = document.createElement('b'); b.textContent = p.t; card.appendChild(b);
          if (p.d) { const s = document.createElement('span'); s.textContent = p.d; card.appendChild(s); }
          const r = a.getBoundingClientRect();
          const left = Math.min(Math.max(8, r.left), window.innerWidth - 356);
          const below = r.bottom + 8 + 140 < window.innerHeight;
          card.style.left = left + 'px';
          card.style.top = (below ? r.bottom + 8 : Math.max(8, r.top - 8 - card.offsetHeight)) + 'px';
          card.classList.add('on');
        }, 350);
      });
      document.addEventListener('mouseout', e => {
        const a = e.target.closest && e.target.closest('a[href]');
        if (a) { clearTimeout(timer); card.classList.remove('on'); }
      });
    }
    """#

    // MARK: Regex helpers

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let rx = try? NSRegularExpression(pattern: pattern),
              let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func allMatches(_ pattern: String, in text: String) -> [String] {
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return [] }
        return rx.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            guard $0.numberOfRanges > 1, let r = Range($0.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
    }

    static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&mdash;", with: "—")
    }
}
