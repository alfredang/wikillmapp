import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import CoreServices   // FSEvents — live folder watching
#endif

/// Owns the open Topics library (a local folder — see `TopicLibrary`), its file tree, the
/// selected topic / sub-topic / page, and all file-system CRUD. Persists the library via a
/// bookmark so it re-opens on next launch; a fresh install opens `TopicLibrary.defaultURL`.
@MainActor
final class VaultStore: ObservableObject {
    @Published var rootURL: URL?
    @Published var rootNode: FileNode?
    @Published var selectedFileURL: URL?
    /// Bumped on every tree refresh (including live FSEvents refreshes), so views showing a
    /// file can notice it changed on disk — e.g. when the agent rewrites a page.
    @Published private(set) var revision = 0
    /// Obsidian-style link graph of the library (backlinks, `[[wikilinks]]`, hover previews).
    /// Rebuilt in the background after each refresh.
    @Published private(set) var links = LinkIndex()
    private var linkTask: Task<Void, Never>?

    /// Sidebar tag search: results carry every selected tag and, when text is typed, a tag
    /// containing that text.
    @Published var tagQuery = ""
    @Published var selectedTags: Set<String> = []

    /// Toggles wired to menu commands / toolbar on macOS.
    @Published var openVaultRequested = false
    @Published var newFileRequested = false

    @Published var showHiddenFiles = false {
        didSet { UserDefaults.standard.set(showHiddenFiles, forKey: Keys.showHidden); refresh() }
    }

    /// Explorer sort direction (folders always group first). Persisted.
    @Published var sortAscending = true {
        didSet { UserDefaults.standard.set(sortAscending, forKey: Keys.sortAsc); refresh() }
    }

    /// Recently-opened vault folders, most-recent first (Obsidian-style vault switcher).
    @Published var recentVaults: [URL] = []

    /// Per-vault custom display names, keyed by folder path. Lets you rename a vault's
    /// shown name without touching the folder on disk.
    @Published private var displayNames: [String: String] = [:]

    private enum Keys {
        // A new key for the Topics library, so the first launch after the Markdown→HTML
        // revamp opens the library instead of an old Markdown vault.
        static let bookmark = "library.bookmark"
        static let showHidden = "settings.showHidden"
        static let sortAsc = "settings.sortAscending"
        static let recents = "vault.recents"
        static let displayNames = "vault.displayNames"
    }

    private var accessing: URL?

    init() {
        showHiddenFiles = UserDefaults.standard.bool(forKey: Keys.showHidden)
        sortAscending = UserDefaults.standard.object(forKey: Keys.sortAsc) as? Bool ?? true
        recentVaults = (UserDefaults.standard.array(forKey: Keys.recents) as? [String] ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        displayNames = UserDefaults.standard.dictionary(forKey: Keys.displayNames) as? [String: String] ?? [:]
    }

    // MARK: - Menu bridges
    func requestOpenVault() { openVaultRequested = true }
    func requestNewFile() { newFileRequested = true }

    // MARK: - Opening / restoring a vault
    func openVault(at url: URL) {
        stopAccessing()
        // Non-sandboxed build: a scoped call isn't required, but harmless if it succeeds.
        if url.startAccessingSecurityScopedResource() {
            accessing = url
        }
        TopicLibrary.seed(url)
        clearTagFilter()
        rootURL = url
        saveBookmark(for: url)
        addRecent(url)
        refresh()
        startWatching(url)
    }

    /// Opens (creating and seeding when needed) the default library folder.
    func openDefaultLibrary() {
        openVault(at: TopicLibrary.defaultURL)
    }

    /// Add a folder to the top of the recent-vaults list (deduped, capped).
    private func addRecent(_ url: URL) {
        var list = recentVaults.filter { $0.standardizedFileURL != url.standardizedFileURL }
        list.insert(url, at: 0)
        recentVaults = Array(list.prefix(10))
        UserDefaults.standard.set(recentVaults.map(\.path), forKey: Keys.recents)
    }

    func removeRecent(_ url: URL) {
        recentVaults.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        UserDefaults.standard.set(recentVaults.map(\.path), forKey: Keys.recents)
    }

    func restoreVaultIfNeeded() {
        guard rootURL == nil else { return }
        #if DEBUG
        // `-debugLibrary <path>` opens a throwaway library for UI checks, leaving the saved
        // library and the recents list alone.
        if let path = UserDefaults.standard.string(forKey: "debugLibrary") {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            TopicLibrary.seed(url)
            rootURL = url
            refresh()
            startWatching(url)
            return
        }
        #endif
        // No saved library yet: open (and seed) the default one.
        guard UserDefaults.standard.data(forKey: Keys.bookmark) != nil else {
            openDefaultLibrary()
            return
        }
        guard let data = UserDefaults.standard.data(forKey: Keys.bookmark) else { return }
        var stale = false
        // Try a plain resolution first; fall back to a security-scoped one so bookmarks
        // saved by an earlier sandboxed build still resolve.
        var resolved: URL?
        for options in bookmarkResolutionOptionSets {
            if let url = try? URL(resolvingBookmarkData: data,
                                  options: options,
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &stale) {
                resolved = url
                break
            }
        }
        guard let url = resolved, FileManager.default.fileExists(atPath: url.path) else {
            openDefaultLibrary()
            return
        }
        TopicLibrary.seed(url)
        if url.startAccessingSecurityScopedResource() {
            accessing = url
        }
        rootURL = url
        if stale { saveBookmark(for: url) }
        addRecent(url)
        refresh()
        startWatching(url)
    }

    func closeVault() {
        stopWatching()
        stopAccessing()
        rootURL = nil
        rootNode = nil
        selectedFileURL = nil
        UserDefaults.standard.removeObject(forKey: Keys.bookmark)
    }

    /// Resolution options to attempt, in order. Plain bookmarks work in this non-sandboxed
    /// build; the security-scoped variant is kept as a fallback for legacy bookmarks.
    private var bookmarkResolutionOptionSets: [URL.BookmarkResolutionOptions] {
        #if os(macOS)
        return [[], [.withSecurityScope]]
        #else
        return [[]]
        #endif
    }

    private func saveBookmark(for url: URL) {
        // Non-sandboxed macOS uses plain bookmarks (no security scope needed).
        if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: Keys.bookmark)
        }
    }

    private func stopAccessing() {
        accessing?.stopAccessingSecurityScopedResource()
        accessing = nil
    }

    var vaultName: String {
        guard let rootURL else { return "No Library" }
        return displayNames[rootURL.path] ?? rootURL.lastPathComponent
    }

    /// The vault's real folder name on disk (ignores any custom display name).
    var vaultFolderName: String { rootURL?.lastPathComponent ?? "No Vault" }

    /// Rename the *display* name of the current vault (does not move the folder).
    /// Pass an empty/whitespace string to clear the override and fall back to the folder name.
    func renameVault(to newName: String) {
        guard let rootURL else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == rootURL.lastPathComponent {
            displayNames[rootURL.path] = nil
        } else {
            displayNames[rootURL.path] = trimmed
        }
        UserDefaults.standard.set(displayNames, forKey: Keys.displayNames)
    }

    /// Display name for any vault URL (used by the recent-vaults list).
    func displayName(for url: URL) -> String {
        displayNames[url.path] ?? url.lastPathComponent
    }

    // MARK: - Tree building
    func refresh() {
        guard let rootURL else { rootNode = nil; return }
        rootNode = buildNode(at: rootURL, isRoot: true)
        revision &+= 1
        rebuildLinks(root: rootURL)
    }

    private func rebuildLinks(root: URL) {
        linkTask?.cancel()
        linkTask = Task { [weak self] in
            let index = await Task.detached(priority: .utility) { LinkIndex.build(root: root) }.value
            guard !Task.isCancelled, let self, self.rootURL == root else { return }
            self.links = index
        }
    }

    /// The topic folders (top-level directories of the library).
    var topics: [FileNode] { rootNode?.children ?? [] }

    // MARK: - Sidebar labels and order

    /// Sidebar name of a node. A page shows its `<title>` with trailing segments that only
    /// repeat where it lives dropped: `"Scenario 5 · Claude Code for CI · CCAR-F"` in
    /// `06 Exam Scenarios/` shows as `"Scenario 5 · Claude Code for CI"`. Pages without a
    /// title, folders and other files keep `displayName`.
    func sidebarLabel(for node: FileNode) -> String {
        guard node.isHTML, let title = links.pages[node.url.standardizedFileURL]?.title else { return node.displayName }
        var parts = title.components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let context = contextNames(for: node.url)
        while parts.count > 1, let last = parts.last, context.contains(LinkIndex.normalize(last)) {
            parts.removeLast()
        }
        return parts.isEmpty ? node.displayName : parts.joined(separator: " · ")
    }

    /// Children in sidebar order: folders first (by name, so "NN " prefixes order them),
    /// then files by their sidebar label in natural order ("Scenario 2" before "Scenario 10").
    func sidebarChildren(of node: FileNode) -> [FileNode] {
        let kids = node.children ?? []
        let folders = kids.filter(\.isDirectory)
        let files = kids.filter { !$0.isDirectory }
            .map { (node: $0, label: sidebarLabel(for: $0)) }
            .sorted { lhs, rhs in
                let order = lhs.label.localizedStandardCompare(rhs.label)
                if order == .orderedSame { return lhs.node.name < rhs.node.name }
                return sortAscending ? order == .orderedAscending : order == .orderedDescending
            }
            .map(\.node)
        return folders + files
    }

    /// Normalized names of the folders a page sits in, up to its topic: each folder's name,
    /// its name without the "NN " prefix, and the first segment of its index page's title.
    private func contextNames(for url: URL) -> Set<String> {
        guard let root = rootURL?.standardizedFileURL.path else { return [] }
        var names = Set<String>()
        var dir = url.standardizedFileURL.deletingLastPathComponent()
        while dir.path.hasPrefix(root), dir.path != root {
            let name = dir.lastPathComponent
            names.insert(LinkIndex.normalize(name))
            names.insert(LinkIndex.normalize(TopicLibrary.prettyFolderName(name)))
            let index = dir.appendingPathComponent(TopicLibrary.indexFile).standardizedFileURL
            if let first = links.pages[index]?.title.components(separatedBy: " · ").first {
                names.insert(LinkIndex.normalize(first))
            }
            dir = dir.deletingLastPathComponent()
        }
        return names
    }

    // MARK: - Tags

    private var normalizedTagQuery: String { PageTags.normalize(tagQuery) }

    var isFilteringByTag: Bool { !selectedTags.isEmpty || !normalizedTagQuery.isEmpty }

    /// Chips to offer: tags matching the typed text, plus selected ones so they can always be
    /// turned off, even after their last page loses the tag.
    var visibleTags: [LinkIndex.TagCount] {
        let query = normalizedTagQuery
        var tags = links.tagList.filter {
            query.isEmpty || $0.tag.contains(query) || selectedTags.contains($0.tag)
        }
        let listed = Set(tags.map(\.tag))
        tags += selectedTags.subtracting(listed).map { LinkIndex.TagCount(tag: $0, count: 0) }
        return tags.sorted { $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
    }

    /// Pages matching the tag search, with each topic ahead of the pages inside it.
    var tagResults: [LinkIndex.Page] {
        let query = normalizedTagQuery
        return links.pages.values
            .filter { page in
                selectedTags.allSatisfy(page.tags.contains)
                    && !page.tags.isEmpty
                    && (query.isEmpty || page.tags.contains { $0.contains(query) })
            }
            .map { (page: $0, path: relativePath(nodeURL(forPage: $0.url))) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .map(\.page)
    }

    /// What a page's row selects: a folder stands for its `index.html`.
    func nodeURL(forPage url: URL) -> URL {
        url.lastPathComponent.lowercased() == TopicLibrary.indexFile ? url.deletingLastPathComponent() : url
    }

    func toggleTag(_ tag: String) {
        if selectedTags.remove(tag) == nil { selectedTags.insert(tag) }
    }

    /// Replaces the search with one tag.
    func showTag(_ tag: String) {
        tagQuery = ""
        selectedTags = [tag]
    }

    func clearTagFilter() {
        tagQuery = ""
        selectedTags = []
    }

    /// Pages the app has indexed and may write to (not `_template.html` or `raw/` sources).
    func canTag(_ page: URL) -> Bool {
        guard let rootURL, links.pages[page.standardizedFileURL] != nil else { return false }
        return !TopicLibrary.isSource(page, root: rootURL)
    }

    /// Adds a comma-separated list of tags. Reads the file first, so a page the agent just
    /// changed keeps its current tags.
    func addTags(_ list: String, to page: URL) {
        let html = loadText(page)
        guard !html.isEmpty else { return }
        writeTags(PageTags.read(from: html) + PageTags.parseList(list), to: page, html: html)
    }

    func removeTag(_ tag: String, from page: URL) {
        let html = loadText(page)
        guard !html.isEmpty else { return }
        writeTags(PageTags.read(from: html).filter { $0 != tag }, to: page, html: html)
    }

    private func writeTags(_ tags: [String], to page: URL, html: String) {
        let updated = PageTags.write(tags, to: html)
        guard updated != html else { return }
        save(updated, to: page)
        links.setTags(PageTags.read(from: updated), for: page)
        refresh()
    }

    // MARK: - Live folder watching (auto-sync)
    #if os(macOS)
    private var fsStream: FSEventStreamRef?
    private var autoRefreshWork: DispatchWorkItem?

    /// Watch the vault folder (recursively) for any on-disk change — files created,
    /// deleted, or renamed by agents, git, Finder, the terminal — and refresh the tree.
    private func startWatching(_ url: URL) {
        stopWatching()
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let store = Unmanaged<VaultStore>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in store.scheduleAutoRefresh() }
        }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.4,                      // coalesce bursts within 0.4s
            flags) else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        fsStream = stream
    }

    private func stopWatching() {
        guard let stream = fsStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        fsStream = nil
    }

    /// Debounce rapid change bursts into a single refresh.
    func scheduleAutoRefresh() {
        autoRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        autoRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    #else
    private func startWatching(_ url: URL) {}
    private func stopWatching() {}
    #endif

    private func buildNode(at url: URL, isRoot: Bool = false) -> FileNode {
        let name = url.lastPathComponent
        var children: [FileNode]? = nil
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDir {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants])) ?? []
            let kids = contents
                // Show every file type (only the hidden-files toggle filters dotfiles).
                // Non-editable files still open to a graceful "Unsupported File" view.
                .filter { showHiddenFiles || !$0.lastPathComponent.hasPrefix(".") }
                .filter { child in
                    let name = child.lastPathComponent
                    let childIsDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    // The library root lists topics only (folders); CLAUDE.md, the template
                    // and `_`-prefixed helpers stay out of the sidebar.
                    if isRoot { return childIsDir && !name.hasPrefix("_") && !name.hasPrefix(".") }
                    // A folder's index.html is the folder itself (selecting the folder opens it).
                    return name.lowercased() != TopicLibrary.indexFile
                }
                .map { buildNode(at: $0) }
                .sorted { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
                    let order = lhs.name.localizedStandardCompare(rhs.name)
                    return sortAscending ? order == .orderedAscending : order == .orderedDescending
                }
            children = kids
        }
        return FileNode(url: url, name: name, isDirectory: isDir, children: children)
    }

    // MARK: - Reading / writing
    func loadText(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func save(_ text: String, to url: URL) {
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    // MARK: - CRUD
    /// Directory new items should be created in, based on the current selection.
    func targetDirectory() -> URL? {
        guard let rootURL else { return nil }
        guard let sel = selectedFileURL else { return rootURL }
        let isDir = (try? sel.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        return isDir ? sel : sel.deletingLastPathComponent()
    }

    @discardableResult
    func createFile(named rawName: String, in directory: URL? = nil) -> URL? {
        guard let dir = directory ?? targetDirectory() else { return nil }
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "Untitled" }
        if (name as NSString).pathExtension.isEmpty { name += ".md" }
        let url = uniqueURL(in: dir, name: name)
        FileManager.default.createFile(atPath: url.path, contents: Data("# \(url.deletingPathExtension().lastPathComponent)\n\n".utf8))
        refresh()
        selectedFileURL = url
        return url
    }

    @discardableResult
    func createFolder(named rawName: String, in directory: URL? = nil) -> URL? {
        guard let dir = directory ?? targetDirectory() else { return nil }
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "New Folder" }
        let url = uniqueURL(in: dir, name: name)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        refresh()
        return url
    }

    func delete(_ url: URL) {
        try? FileManager.default.trashOrRemove(url)
        if selectedFileURL == url { selectedFileURL = nil }
        refresh()
    }

    @discardableResult
    func rename(_ url: URL, to rawName: String) -> URL? {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if !isDir && (name as NSString).pathExtension.isEmpty {
            let oldExt = url.pathExtension
            if !oldExt.isEmpty { name += "." + oldExt }
        }
        let dest = url.deletingLastPathComponent().appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            if selectedFileURL == url { selectedFileURL = dest }
            refresh()
            return dest
        } catch { return nil }
    }

    // MARK: - Topics, sub-topics, pages

    /// Selects a file or folder, normalising `…/index.html` to its folder (the folder row
    /// stands for its overview page). Used by in-page links and the agent.
    func select(_ url: URL) {
        var target = url.standardizedFileURL
        if target.lastPathComponent.lowercased() == TopicLibrary.indexFile {
            target = target.deletingLastPathComponent()
        }
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        selectedFileURL = target
    }

    func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    /// The page shown for a selection: the file itself, or a folder's `index.html` if any.
    func pageURL(for url: URL) -> URL? {
        guard isDirectory(url) else { return url }
        let index = url.appendingPathComponent(TopicLibrary.indexFile)
        return FileManager.default.fileExists(atPath: index.path) ? index : nil
    }

    /// The topic folder that contains `url` (or `url` itself when it is a topic).
    func topicURL(for url: URL?) -> URL? {
        guard let rootURL, let url else { return nil }
        return TopicLibrary.folderChain(root: rootURL, to: isDirectory(url) ? url : url.deletingLastPathComponent()).first
    }

    /// Path relative to the library root, e.g. `CCAR-F/01 Agents/agent-loop.html`.
    func relativePath(_ url: URL) -> String {
        guard let root = rootURL?.standardizedFileURL.path else { return url.path }
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root) else { return path }
        return String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// New topic at the library root: `index.html`, `log.md` and an empty `raw/`.
    @discardableResult
    func createTopic(named rawName: String) -> URL? {
        guard let rootURL else { return nil }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let dir = uniqueURL(in: rootURL, name: name)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir.appendingPathComponent(TopicLibrary.sourcesFolder), withIntermediateDirectories: true)
            try TopicLibrary.topicIndexHTML(root: rootURL, title: dir.lastPathComponent)
                .write(to: dir.appendingPathComponent(TopicLibrary.indexFile), atomically: true, encoding: .utf8)
            try TopicLibrary.logMarkdown(topic: dir.lastPathComponent)
                .write(to: dir.appendingPathComponent(TopicLibrary.logFile), atomically: true, encoding: .utf8)
        } catch { return nil }
        refresh()
        selectedFileURL = dir
        return dir
    }

    /// New sub-topic folder (with an overview `index.html`) inside `parent`.
    @discardableResult
    func createSubtopic(named rawName: String, in parent: URL) -> URL? {
        guard let rootURL else { return nil }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let dir = uniqueURL(in: parent, name: name)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try TopicLibrary.folderIndexHTML(root: rootURL, folder: dir)
                .write(to: dir.appendingPathComponent(TopicLibrary.indexFile), atomically: true, encoding: .utf8)
        } catch { return nil }
        refresh()
        selectedFileURL = dir
        return dir
    }

    /// New HTML page from the library template inside `folder`.
    @discardableResult
    func createPage(titled rawTitle: String, in folder: URL) -> URL? {
        guard let rootURL else { return nil }
        var title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { title = "Untitled" }
        let url = uniqueURL(in: folder, name: TopicLibrary.slug(title) + ".html")
        do {
            try TopicLibrary.pageHTML(root: rootURL, folder: folder, title: title)
                .write(to: url, atomically: true, encoding: .utf8)
        } catch { return nil }
        refresh()
        selectedFileURL = url
        return url
    }

    private func uniqueURL(in dir: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = dir.appendingPathComponent(name)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            n += 1
            let newName = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            candidate = dir.appendingPathComponent(newName)
        }
        return candidate
    }

    // MARK: - Image resolution (Bear / Obsidian embeds)
    /// Resolve a markdown/Obsidian image reference to an on-disk URL.
    /// Handles `![[image.png]]`, `![alt](relative/path.png)`, optional `|size` suffix.
    func resolveImageURL(_ src: String, relativeTo fileURL: URL?) -> URL? {
        var name = src
        if let bar = name.firstIndex(of: "|") { name = String(name[..<bar]) }   // Obsidian size hint
        name = name.removingPercentEncoding ?? name
        name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.hasPrefix("http") else { return nil }

        let direct = [
            fileURL?.deletingLastPathComponent().appendingPathComponent(name),
            rootURL?.appendingPathComponent(name)
        ].compactMap { $0 }
        for c in direct where FileManager.default.fileExists(atPath: c.path) { return c }

        // Fall back to searching the whole vault by file name (Obsidian shortest-path behaviour).
        if let root = rootURL {
            let base = (name as NSString).lastPathComponent
            if let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
                for case let u as URL in en where u.lastPathComponent == base { return u }
            }
        }
        return nil
    }
}

private extension FileManager {
    /// Move to Trash where available (macOS / iOS 11+), else hard delete.
    func trashOrRemove(_ url: URL) throws {
        do {
            try trashItem(at: url, resultingItemURL: nil)
        } catch {
            try removeItem(at: url)
        }
    }
}
