#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// How an HTML page is shown.
enum PageMode: String, CaseIterable, Identifiable {
    case preview, split, source
    var id: String { rawValue }
    var title: String {
        switch self {
        case .preview: return "Preview"
        case .split:   return "Split"
        case .source:  return "Source"
        }
    }
    var symbol: String {
        switch self {
        case .preview: return "eye"
        case .split:   return "rectangle.split.2x1"
        case .source:  return "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// The middle pane for a selected topic, subtopic or page. Folders show their `index.html`
/// overview (or a card grid when they have none); HTML pages render like artifacts with a
/// Source / Split view for hand edits; Markdown files (log.md, CLAUDE.md) use the Markdown editor.
struct TopicDetailView: View {
    @EnvironmentObject var store: VaultStore
    let url: URL
    var onNewPage: (URL) -> Void
    var onNewSubtopic: (URL) -> Void
    var onAgent: (WikiAction, URL) -> Void

    @AppStorage("page.mode") private var modeRaw = PageMode.preview.rawValue
    private var mode: PageMode { PageMode(rawValue: modeRaw) ?? .preview }

    var body: some View {
        let isDir = store.isDirectory(url)
        let page = store.pageURL(for: url)
        VStack(spacing: 0) {
            header(isDir: isDir, page: page)
            Divider()
            if let page, store.canTag(page) {
                PageTagBar(page: page)
                Divider()
            }
            content(isDir: isDir, page: page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: Header

    private func header(isDir: Bool, page: URL?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(isDir: isDir, page: page))
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Breadcrumbs(url: url, isDir: isDir, count: isDir ? subtitleCount : nil)
            }
            Spacer(minLength: 8)
            PageStepper(url: url)
            if let page, isHTML(page) {
                Picker("View", selection: $modeRaw) {
                    ForEach(PageMode.allCases) { m in
                        Image(systemName: m.symbol).help(m.title).tag(m.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Preview · Split · Source")
            }
            if isDir {
                Button { onNewPage(url) } label: { Image(systemName: "doc.badge.plus") }
                    .help("New page in this folder")
                Button { onNewSubtopic(url) } label: { Image(systemName: "folder.badge.plus") }
                    .help("New subtopic in this folder")
            }
            if let page, isHTML(page) {
                Button {
                    NotificationCenter.default.post(name: .wikiScrollToSection, object: page,
                                                    userInfo: ["anchor": "discussion"])
                } label: { Image(systemName: "bubble.left.and.text.bubble.right") }
                    .keyboardShortcut("d", modifiers: [.command, .option])
                    .help("Go to the Discussion: your questions on this page (⌥⌘D)")
            }
            if let page {
                Button { NSWorkspace.shared.open(page) } label: { Image(systemName: "safari") }
                    .help("Open in default browser")
            }
            Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "folder") }
                .help("Reveal in Finder")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func title(isDir: Bool, page: URL?) -> String {
        // From the link index, never the file: this runs on every redraw, and in iCloud Drive a
        // read can stall and freeze the app.
        if let page, isHTML(page), let t = store.links.pages[page.standardizedFileURL]?.title, !t.isEmpty { return t }
        if isDir { return url.lastPathComponent == TopicLibrary.sourcesFolder ? "Sources" : url.lastPathComponent }
        return url.lastPathComponent
    }

    private var subtitleCount: Int {
        store.rootNode.flatMap { Self.find(url, in: $0) }?.pageCount ?? 0
    }

    private func subtitle(isDir: Bool) -> String {
        let path = store.relativePath(isDir ? url : url.deletingLastPathComponent())
        guard isDir else { return path.isEmpty ? "Library" : path }
        let node = store.rootNode.flatMap { Self.find(url, in: $0) }
        let count = node?.pageCount ?? 0
        return "\(path) · \(count) page\(count == 1 ? "" : "s")"
    }

    // MARK: Content

    @ViewBuilder
    private func content(isDir: Bool, page: URL?) -> some View {
        if let page, isHTML(page) {
            htmlPage(page)
        } else if isDir {
            FolderOverview(folder: url, onNewPage: onNewPage, onAgent: onAgent)
        } else {
            let node = FileNode(url: url, name: url.lastPathComponent, isDirectory: false, children: nil)
            if node.isEditable {
                LocalFileGate(url: url) { MarkdownEditorView(url: url).id(url) }
            } else if node.isImage {
                ImageFileView(url: url)
            } else if node.ext == "pdf" {
                LocalFileGate(url: url) { HTMLPageView(url: url, readAccessURL: url.deletingLastPathComponent()) }
            } else {
                ContentUnavailableView {
                    Label(url.lastPathComponent, systemImage: node.systemImage)
                } description: {
                    Text("This file type can't be shown here.")
                } actions: {
                    Button("Open in Default App") { NSWorkspace.shared.open(url) }
                }
            }
        }
    }

    @ViewBuilder
    private func htmlPage(_ page: URL) -> some View {
        let preview = HTMLPageView(url: page,
                                   readAccessURL: store.rootURL ?? page.deletingLastPathComponent(),
                                   revision: store.modificationDate(page),
                                   linkScript: store.links.script(for: page),
                                   onOpenLocal: { store.select($0) })
        VStack(spacing: 0) {
            LocalFileGate(url: page) {
                switch mode {
                case .preview:
                    preview
                case .source:
                    HTMLSourceEditor(url: page)
                case .split:
                    HSplitView {
                        HTMLSourceEditor(url: page).frame(minWidth: 260)
                        preview.frame(minWidth: 260)
                    }
                }
            }
            LinksBar(page: page)
            PageFooterNav(url: url)
        }
    }

    private func isHTML(_ url: URL) -> Bool { ["html", "htm"].contains(url.pathExtension.lowercased()) }

    static func find(_ url: URL, in node: FileNode) -> FileNode? {
        if node.url.standardizedFileURL == url.standardizedFileURL { return node }
        for child in node.children ?? [] {
            if let hit = find(url, in: child) { return hit }
        }
        return nil
    }
}

/// Shows `content` once `url` is on this Mac. When the disk runs low, macOS removes the local copy
/// of files in iCloud Drive, and opening one waits for a download. WebKit shows a white page for
/// that whole time and an editor would freeze the app, so this fetches the file off the main thread
/// first and says what is happening. A page already showing stays up if macOS later evicts it.
private struct LocalFileGate<Content: View>: View {
    let url: URL
    @ViewBuilder var content: () -> Content

    @State private var shown: URL?
    @State private var failed: URL?
    @State private var attempt = 0

    private struct Fetch: Hashable {
        let url: URL
        let attempt: Int
    }

    var body: some View {
        if shown == url || !Self.isEvicted(url) {
            content().task(id: url) { shown = url }
        } else if failed == url {
            ContentUnavailableView {
                Label("Couldn't download this page", systemImage: "icloud.slash")
            } description: {
                Text("macOS removed its local copy to save disk space and couldn't get it back from iCloud. Check your internet connection and try again.")
            } actions: {
                Button("Try Again") {
                    failed = nil
                    attempt += 1
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label {
                    Text("Downloading from iCloud…")
                } icon: {
                    ProgressView().controlSize(.large)
                }
            } description: {
                Text("macOS removed its local copy of this page to save disk space. It opens as soon as the download finishes, which can take a minute or two.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: Fetch(url: url, attempt: attempt)) {
                let target = url
                let fetched = await Task.detached(priority: .userInitiated) { Self.fetch(target) }.value
                guard !Task.isCancelled else { return }
                if fetched { shown = target } else { failed = target }
            }
        }
    }

    /// True when only iCloud holds the file's contents. Asking doesn't start a download.
    private nonisolated static func isEvicted(_ url: URL) -> Bool {
        let dataless: UInt32 = 0x4000_0000   // SF_DATALESS in <sys/stat.h>
        var info = stat()
        return stat(url.path, &info) == 0 && info.st_flags & dataless != 0
    }

    /// Reading the first byte makes macOS download the whole file.
    private nonisolated static func fetch(_ url: URL) -> Bool {
        guard let file = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? file.close() }
        return (try? file.read(upToCount: 1)) != nil
    }
}

/// Obsidian-style linked mentions under a page: backlinks (pages linking here) and
/// outgoing links, collapsible. Counts come from `VaultStore.links`.
struct LinksBar: View {
    @EnvironmentObject var store: VaultStore
    let page: URL
    @AppStorage("links.expanded") private var expanded = false

    var body: some View {
        let back = store.links.backlinks(to: page)
        let out = store.links.outlinks(from: page)
        VStack(spacing: 0) {
            Divider()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .font(.caption.weight(.semibold))
                    Label("\(back.count) backlink\(back.count == 1 ? "" : "s")", systemImage: "arrow.uturn.backward")
                    Label("\(out.count) outgoing", systemImage: "arrow.up.right")
                    Spacer()
                    // Only once the index has reached this page: until then "no backlinks" means nothing.
                    if back.isEmpty, store.links.pages[page.standardizedFileURL] != nil,
                       !page.lastPathComponent.lowercased().hasPrefix("index") {
                        Text("Orphan: nothing links here yet").foregroundStyle(Theme.highlight)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Linked mentions: pages that link here, and pages this one links to")

            if expanded {
                HStack(alignment: .top, spacing: 0) {
                    column("Linked mentions", empty: "No page links here yet.", pages: back)
                    Divider()
                    column("Links from this page", empty: "This page links nowhere yet.", pages: out)
                }
                .frame(height: 190)
            }
        }
        .background(Theme.card)
    }

    private func column(_ title: String, empty: String, pages: [LinkIndex.Page]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            if pages.isEmpty {
                Text(empty).font(.callout).foregroundStyle(.tertiary)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(pages, id: \.url) { p in
                            LinkRow(page: p, folder: store.relativePath(p.url.deletingLastPathComponent())) {
                                store.select(p.url)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LinkRow: View {
    let page: LinkIndex.Page
    let folder: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(page.title).font(.callout).foregroundStyle(Theme.accent).lineLimit(1)
                Text(folder).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.accent.opacity(0.08) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(page.summary)
    }
}

/// A folder with no `index.html`: its pages and subfolders as cards, plus ways to fill it.
struct FolderOverview: View {
    @EnvironmentObject var store: VaultStore
    let folder: URL
    var onNewPage: (URL) -> Void
    var onAgent: (WikiAction, URL) -> Void

    private var isSources: Bool { folder.lastPathComponent == TopicLibrary.sourcesFolder }

    private var children: [FileNode] {
        store.rootNode.flatMap { TopicDetailView.find(folder, in: $0) }?.children ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isSources {
                    hint(icon: "tray.and.arrow.down",
                         title: "Sources for this topic",
                         text: "Drop PDFs, notes, transcripts or a urls.txt here. They are never edited — the agent reads them and compiles the knowledge into pages.") {
                        Button { addSources() } label: { Label("Add Sources…", systemImage: "plus") }
                        Button { onAgent(.ingest, folder) } label: { Label("Ingest with Agent", systemImage: "sparkles") }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    hint(icon: "doc.richtext",
                         title: "No overview page yet",
                         text: "Each folder's index.html is its overview. Create one, or ask the agent to outline this folder into subtopics and pages.") {
                        Button { createOverview() } label: { Label("Create Overview Page", systemImage: "doc.badge.plus") }
                        Button { onAgent(.outline, folder) } label: { Label("Outline with Agent", systemImage: "sparkles") }
                            .buttonStyle(.borderedProminent)
                    }
                }
                if !children.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                        ForEach(children) { child in
                            NodeCard(node: child) { store.select(child.url) }
                        }
                    }
                }
            }
            .padding(22)
        }
    }

    private func hint<Actions: View>(icon: String, title: String, text: String,
                                     @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack { actions() }.padding(.top, 2)
            }
        }
        .appCard()
    }

    private func createOverview() {
        guard let root = store.rootURL else { return }
        let index = folder.appendingPathComponent(TopicLibrary.indexFile)
        store.save(TopicLibrary.folderIndexHTML(root: root, folder: folder), to: index)
        store.refresh()
    }

    private func addSources() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add to Sources"
        guard panel.runModal() == .OK else { return }
        for file in panel.urls {
            try? FileManager.default.copyItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
        }
        store.refresh()
    }
}

/// Card for a page or folder in an overview grid.
struct NodeCard: View {
    @EnvironmentObject var store: VaultStore
    let node: FileNode
    var action: () -> Void
    @State private var hovering = false

    private var cardTitle: String {
        guard node.isHTML, let title = store.links.pages[node.url.standardizedFileURL]?.title, !title.isEmpty
        else { return node.displayName }
        return title
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: node.systemImage).foregroundStyle(Theme.accent)
                    Spacer()
                    if node.isDirectory {
                        Text("\(node.pageCount) pages").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(cardTitle)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                if !node.isDirectory {
                    Text(node.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(hovering ? Theme.accent.opacity(0.6) : Theme.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Shown when nothing is selected: every topic as a card.
struct LibraryHomeView: View {
    @EnvironmentObject var store: VaultStore
    var onNewTopic: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Topics").font(.largeTitle.bold())
                    Text("Your knowledge library — each topic is a folder of HTML pages, written and maintained with the Claude Code agent on the right.")
                        .foregroundStyle(.secondary)
                }
                if store.topics.isEmpty {
                    ContentUnavailableView {
                        Label("No Topics Yet", systemImage: "books.vertical")
                    } description: {
                        Text("Create a topic, then ask the agent to outline it.")
                    } actions: {
                        Button("New Topic…", action: onNewTopic).buttonStyle(.borderedProminent)
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                        ForEach(store.topics) { topic in
                            NodeCard(node: topic) { store.select(topic.url) }
                        }
                    }
                    Button(action: onNewTopic) { Label("New Topic…", systemImage: "plus") }
                }
            }
            .padding(28)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
// MARK: - Breadcrumbs and previous / next

/// Library › Topic › Subtopic, each a link, under the page title.
private struct Breadcrumbs: View {
    @EnvironmentObject var store: VaultStore
    let url: URL
    let isDir: Bool
    var count: Int?

    var body: some View {
        HStack(spacing: 4) {
            crumb("Library", target: nil)
            ForEach(chain, id: \.self) { folder in
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                crumb(store.sidebarLabel(for: FileNode(url: folder, name: folder.lastPathComponent,
                                                      isDirectory: true, children: nil)), target: folder)
            }
            if let count {
                Text("· \(count) page\(count == 1 ? "" : "s")").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .lineLimit(1)
        .truncationMode(.middle)
    }

    /// The folders above this item; a folder's own name is the page title, so it's left out.
    private var chain: [URL] {
        guard let root = store.rootURL else { return [] }
        let dir = url.deletingLastPathComponent()
        return TopicLibrary.folderChain(root: root, to: dir)
    }

    private func crumb(_ title: String, target: URL?) -> some View {
        Button(title) {
            if let target { store.select(target) } else { store.selectedFileURL = nil }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .help(target.map { store.relativePath($0) } ?? "Library home")
    }
}

/// ‹ › buttons in the header: the previous and next page in the topic's reading order.
private struct PageStepper: View {
    @EnvironmentObject var store: VaultStore
    let url: URL

    var body: some View {
        let n = store.neighbours(of: url)
        HStack(spacing: 2) {
            Button { if let p = n.previous { store.select(p.url) } } label: { Image(systemName: "chevron.left") }
                .disabled(n.previous == nil)
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .help(n.previous.map { "Previous: \(store.sidebarLabel(for: $0))  ⌥⌘←" } ?? "First page of this topic")
            Button { if let p = n.next { store.select(p.url) } } label: { Image(systemName: "chevron.right") }
                .disabled(n.next == nil)
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .help(n.next.map { "Next: \(store.sidebarLabel(for: $0))  ⌥⌘→" } ?? "Last page of this topic")
        }
    }
}

/// "‹ Previous page · Next page ›" under the page, for when the reader reaches the end.
private struct PageFooterNav: View {
    @EnvironmentObject var store: VaultStore
    let url: URL

    var body: some View {
        let n = store.neighbours(of: url)
        if n.previous != nil || n.next != nil {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    if let p = n.previous { link(p, forward: false) }
                    Spacer(minLength: 16)
                    if let p = n.next { link(p, forward: true) }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
        }
    }

    private func link(_ node: FileNode, forward: Bool) -> some View {
        Button { store.select(node.url) } label: {
            HStack(spacing: 6) {
                if !forward { Image(systemName: "chevron.left") }
                VStack(alignment: forward ? .trailing : .leading, spacing: 0) {
                    Text(forward ? "Next" : "Previous").font(.caption2).foregroundStyle(.secondary)
                    Text(store.sidebarLabel(for: node)).font(.callout).lineLimit(1)
                }
                if forward { Image(systemName: "chevron.right") }
            }
            .foregroundStyle(Theme.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
