import Foundation

/// The Topics library: a plain folder whose top-level sub-folders are **topics**. Each topic
/// holds numbered **sub-topic** folders and self-contained **HTML pages** (Claude-artifact
/// style), plus `raw/` sources and an append-only `log.md`. The library root carries the
/// agent schema (`CLAUDE.md`) and the page template (`_template.html`); see
/// `Resources/LibraryTemplate`.
enum TopicLibrary {
    static let folderName = "Tertiary Topics"
    static let schemaFile = "CLAUDE.md"
    static let templateFile = "_template.html"
    static let indexFile = "index.html"
    static let logFile = "log.md"
    static let sourcesFolder = "raw"

    /// Where a fresh install keeps its library.
    static var defaultURL: URL {
        #if os(macOS)
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        #else
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
        #endif
    }

    /// Creates the library folder and writes the schema + template where they are missing.
    /// Never overwrites: the person (or agent) may have customised them.
    static func seed(_ root: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        guard let bundled = Bundle.main.url(forResource: "LibraryTemplate", withExtension: nil) else { return }
        for name in [schemaFile, templateFile] {
            let dest = root.appendingPathComponent(name)
            if !fm.fileExists(atPath: dest.path) {
                try? fm.copyItem(at: bundled.appendingPathComponent(name), to: dest)
            }
        }
    }

    // MARK: - Names

    /// `"Agent Loop & Tools!"` → `"agent-loop-tools"`.
    static func slug(_ title: String) -> String {
        let lowered = title.lowercased()
        var out = ""
        var lastDash = false
        for ch in lowered {
            if ch.isLetter || ch.isNumber {
                out.append(ch); lastDash = false
            } else if !lastDash && !out.isEmpty {
                out.append("-"); lastDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "untitled" : out
    }

    /// Folder name shown to people: `"01 Agentic Architecture"` → `"Agentic Architecture"`.
    static func prettyFolderName(_ name: String) -> String {
        let parts = name.split(separator: " ", maxSplits: 1)
        if parts.count == 2, parts[0].allSatisfy(\.isNumber) { return String(parts[1]) }
        return name
    }

    /// Page name shown to people: `"agent-loop.html"` → `"Agent loop"`.
    static func prettyPageName(_ fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        guard let first = base.first else { return fileName }
        return first.uppercased() + base.dropFirst()
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// True for anything inside a topic's `raw/` sources, which are never edited.
    static func isSource(_ url: URL, root: URL) -> Bool {
        let depth = root.standardizedFileURL.pathComponents.count
        return url.standardizedFileURL.pathComponents.dropFirst(depth).contains(sourcesFolder)
    }

    // MARK: - Page generation

    /// Folders from the topic down to `dir` (inclusive), e.g. `[Topic, 01 Sub, 02 Deeper]`.
    static func folderChain(root: URL, to dir: URL) -> [URL] {
        let rootParts = root.standardizedFileURL.pathComponents
        let dirParts = dir.standardizedFileURL.pathComponents
        guard dirParts.count > rootParts.count, Array(dirParts.prefix(rootParts.count)) == rootParts else { return [] }
        var chain: [URL] = []
        var current = root.standardizedFileURL
        for part in dirParts.dropFirst(rootParts.count) {
            current.appendPathComponent(part, isDirectory: true)
            chain.append(current)
        }
        return chain
    }

    /// Breadcrumb links for a page living in `chain.last`: every folder links to its
    /// `index.html`, relative to that page.
    private static func crumbs(_ chain: [URL], current: String) -> String {
        var items: [String] = []
        for (i, folder) in chain.enumerated() {
            let ups = String(repeating: "../", count: chain.count - 1 - i)
            let label = escape(i == 0 ? folder.lastPathComponent : prettyFolderName(folder.lastPathComponent))
            items.append("<a href=\"\(ups)index.html\">\(label)</a>")
        }
        items.append(escape(current))
        return "<nav class=\"crumbs\">" + items.joined(separator: "<span>›</span>") + "</nav>"
    }

    /// The `<head>` of the library's template (its `<style>` keeps every page consistent),
    /// with the title and description filled in.
    private static func head(root: URL, title: String, description: String) -> String {
        let templateURL = root.appendingPathComponent(templateFile)
        let bundledURL = Bundle.main.url(forResource: "LibraryTemplate", withExtension: nil)?
            .appendingPathComponent(templateFile)
        let template = (try? String(contentsOf: templateURL, encoding: .utf8))
            ?? bundledURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            ?? ""
        var head: String
        if let end = template.range(of: "</head>", options: .caseInsensitive) {
            head = String(template[..<end.upperBound])
        } else {
            head = "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>Page Title</title>\n</head>"
        }
        head = head.replacingOccurrences(of: #"<title>[\s\S]*?</title>"#,
                                          with: "<title>\(escape(title))</title>",
                                          options: .regularExpression)
        head = head.replacingOccurrences(of: #"<meta name="description" content="[^"]*">"#,
                                          with: "<meta name=\"description\" content=\"\(escape(description))\">",
                                          options: .regularExpression)
        return head
    }

    private static func document(root: URL, title: String, eyebrow: String, lede: String,
                                 crumbs: String, body: String) -> String {
        let today = ISO8601DateFormatter.dateOnly.string(from: Date())
        return """
        \(head(root: root, title: title, description: lede))
        <body>
        <main>
          \(crumbs)

          <div class="eyebrow">\(escape(eyebrow))</div>
          <h1>\(escape(title))</h1>
          <p class="lede">\(escape(lede))</p>

        \(body)

          <footer>Created \(today) · Ask the agent panel to write or update this page.</footer>
        </main>
        </body>
        </html>

        """
    }

    /// Topic home page (`<Topic>/index.html`).
    static func topicIndexHTML(root: URL, title: String) -> String {
        document(root: root, title: title, eyebrow: "Topic",
                 lede: "Overview of \(title): what it covers and how its subtopics fit together.",
                 crumbs: "",
                 body: """
                  <div class="callout"><strong>New topic</strong>Ask the agent panel to outline this topic — it will create the numbered subtopic folders and pages and keep this map current.</div>

                  <h2>Subtopics</h2>
                  <div class="grid">
                  </div>
                """)
    }

    /// Sub-topic overview page (`<Folder>/index.html`).
    static func folderIndexHTML(root: URL, folder: URL) -> String {
        let chain = folderChain(root: root, to: folder)
        let title = prettyFolderName(folder.lastPathComponent)
        let eyebrow = chain.first?.lastPathComponent ?? "Topic"
        return document(root: root, title: title, eyebrow: eyebrow,
                        lede: "Overview of \(title).",
                        crumbs: crumbs(Array(chain.dropLast()), current: title),
                        body: """
                          <h2>Pages</h2>
                          <div class="grid">
                          </div>
                        """)
    }

    /// A concept page inside `folder`.
    static func pageHTML(root: URL, folder: URL, title: String) -> String {
        let chain = folderChain(root: root, to: folder)
        let eyebrow = chain.count > 1 ? prettyFolderName(folder.lastPathComponent)
                                      : (chain.first?.lastPathComponent ?? "Topic")
        return document(root: root, title: title, eyebrow: eyebrow,
                        lede: "A short summary of \(title).",
                        crumbs: crumbs(chain, current: title),
                        body: """
                          <div class="callout warn"><strong>Draft</strong>This page is a stub. Ask the agent panel to write it.</div>

                          <h2>Key ideas</h2>
                          <ul>
                            <li>…</li>
                          </ul>

                          <h2>Related</h2>
                          <ul class="related"><li><a href="index.html">\(escape(prettyFolderName(folder.lastPathComponent)))</a></li></ul>
                        """)
    }

    static func logMarkdown(topic: String) -> String {
        let today = ISO8601DateFormatter.dateOnly.string(from: Date())
        return "# Log — \(topic)\n\nAppend-only. One line per operation.\n\n## [\(today)] create | topic created\n"
    }
}

extension ISO8601DateFormatter {
    static let dateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = .current
        return f
    }()
}

extension FileNode {
    var isHTML: Bool { ["html", "htm"].contains(ext) }

    /// Name for the sidebar: pages lose their extension and dashes; numbered folders keep
    /// their number so the order stays visible.
    var displayName: String {
        if isDirectory { return name == TopicLibrary.sourcesFolder ? "Sources" : name }
        return isHTML ? TopicLibrary.prettyPageName(name) : name
    }

    /// HTML pages under this folder, recursively (overview pages included).
    var pageCount: Int {
        guard isDirectory else { return isHTML ? 1 : 0 }
        let own = FileManager.default.fileExists(atPath: url.appendingPathComponent(TopicLibrary.indexFile).path) ? 1 : 0
        return own + (children ?? []).reduce(0) { $0 + $1.pageCount }
    }
}
