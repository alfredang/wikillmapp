import SwiftUI
import UniformTypeIdentifiers

/// iPhone / iPad Topics browser: topics, subtopics and pages on the left; the selected HTML
/// page (rendered like an artifact) or Markdown file on the right.
struct VaultView: View {
    @EnvironmentObject var store: VaultStore
    @State private var showImporter = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    // Name-entry dialogs
    @State private var showNewFile = false
    @State private var showNewFolder = false
    @State private var newName = ""

    // Rename
    @State private var renameTarget: URL?
    @State private var renameText = ""

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationTitle(store.vaultName)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        } detail: {
            detail
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { store.openVault(at: url) }
        }
        .task {
            store.restoreVaultIfNeeded()
            #if DEBUG
            // `-debugSelect <path relative to the library>` opens a page (screenshots, UI checks).
            if let rel = UserDefaults.standard.string(forKey: "debugSelect"), let root = store.rootURL {
                store.select(root.appendingPathComponent(rel))
            }
            #endif
        }
        // Bridge macOS menu commands
        .onChange(of: store.openVaultRequested) { _, v in if v { showImporter = true; store.openVaultRequested = false } }
        .onChange(of: store.newFileRequested) { _, v in if v { startNewFile(); store.newFileRequested = false } }
        // New file / folder dialogs
        .alert("New Page", isPresented: $showNewFile) {
            TextField("Title", text: $newName)
            Button("Create") { if let dir = topicFolder { store.createPage(titled: newName, in: dir) } }
            Button("Cancel", role: .cancel) { }
        } message: { Text("An HTML page in \(topicFolder?.lastPathComponent ?? "the selected topic")") }
        .alert(topicFolder == nil ? "New Topic" : "New Subtopic", isPresented: $showNewFolder) {
            TextField("Name", text: $newName)
            Button("Create") {
                if let dir = topicFolder { store.createSubtopic(named: newName, in: dir) }
                else { store.createTopic(named: newName) }
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Rename", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { if let t = renameTarget { store.rename(t, to: renameText) }; renameTarget = nil }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
    }

    // MARK: - Sidebar
    @ViewBuilder
    private var sidebar: some View {
        if store.rootNode == nil {
            emptyVault
        } else {
            List(selection: $store.selectedFileURL) {
                if store.isFilteringByTag {
                    let results = store.tagResults
                    Section("\(results.count) tagged") {
                        if results.isEmpty {
                            Text("Nothing has these tags.")
                                .font(.callout).foregroundStyle(Theme.mutedInk)
                        }
                        ForEach(results, id: \.url) { page in
                            TagResultRow(page: page).tag(store.nodeURL(forPage: page.url))
                        }
                    }
                } else if let children = store.rootNode?.children {
                    if children.isEmpty {
                        Text("No topics yet.\nUse + to create a topic.")
                            .font(.callout).foregroundStyle(Theme.mutedInk)
                    }
                    OutlineGroup(children, id: \.id, children: \.children) { node in
                        nodeLabel(node)
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .top, spacing: 0) { TagFilterBar() }
            .toolbar { sidebarToolbar }
        }
    }

    @ViewBuilder
    private func nodeLabel(_ node: FileNode) -> some View {
        if node.isDirectory {
            Label(store.sidebarLabel(for: node), systemImage: node.systemImage)
                .foregroundStyle(Theme.accent)
                .tag(node.url)
                .contextMenu { nodeMenu(node) }
        } else {
            Label(store.sidebarLabel(for: node), systemImage: node.systemImage)
                .tag(node.url)
                .contextMenu { nodeMenu(node) }
        }
    }

    @ViewBuilder
    private func nodeMenu(_ node: FileNode) -> some View {
        if node.isDirectory {
            Button { store.selectedFileURL = node.url; startNewFile() } label: { Label("New Page Here", systemImage: "doc.badge.plus") }
            Button { store.selectedFileURL = node.url; startNewFolder() } label: { Label("New Subtopic Here", systemImage: "folder.badge.plus") }
            Divider()
        }
        Button { renameTarget = node.url; renameText = node.name } label: { Label("Rename", systemImage: "pencil") }
        Button(role: .destructive) { store.delete(node.url) } label: { Label("Delete", systemImage: "trash") }
    }

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button { store.selectedFileURL = nil; startNewFolder() } label: { Label("New Topic", systemImage: "books.vertical") }
                if topicFolder != nil {
                    Button { startNewFolder() } label: { Label("New Subtopic", systemImage: "folder.badge.plus") }
                    Button { startNewFile() } label: { Label("New Page", systemImage: "doc.badge.plus") }
                }
                Divider()
                Button { showImporter = true } label: { Label("Open Library Folder…", systemImage: "folder") }
                Button { store.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    private var emptyVault: some View {
        VStack(spacing: 18) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 52))
                .foregroundStyle(Theme.accent)
            Text("Open a Library")
                .font(.title2.bold())
            Text("Choose a folder to hold your topics — each topic is a folder of HTML pages.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.mutedInk)
                .frame(maxWidth: 320)
            Button {
                showImporter = true
            } label: {
                Label("Open Folder…", systemImage: "folder")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)

            Button {
                store.openDefaultLibrary()
            } label: {
                Label("Use Default Library", systemImage: "books.vertical")
            }
            .buttonStyle(.bordered)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    // MARK: - Detail
    @ViewBuilder
    private var detail: some View {
        if let selected = store.selectedFileURL {
            let url = store.pageURL(for: selected) ?? selected
            let node = FileNode(url: url, name: url.lastPathComponent,
                                isDirectory: store.isDirectory(url), children: nil)
            if node.isHTML {
                VStack(spacing: 0) {
                    if store.canTag(url) {
                        PageTagBar(page: url).id(url)
                        Divider()
                    }
                    HTMLPageView(url: url,
                                 readAccessURL: store.rootURL ?? url.deletingLastPathComponent(),
                                 revision: store.modificationDate(url),
                                 linkScript: store.links.script(for: url),
                                 onOpenLocal: { store.select($0) })
                        .ignoresSafeArea(edges: .bottom)
                }
                    .navigationTitle(store.sidebarLabel(for: node))
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
            } else if node.isDirectory {
                ContentUnavailableView(node.displayName,
                                       systemImage: "folder",
                                       description: Text("This folder has no overview page yet. Pick a page from the sidebar."))
            } else if node.isEditable {
                MarkdownEditorView(url: url)
                    .id(url)
            } else if node.isImage {
                ImageFileView(url: url)
            } else {
                ContentUnavailableView("Unsupported File",
                                       systemImage: "doc",
                                       description: Text(url.lastPathComponent))
            }
        } else {
            ContentUnavailableView("No Page Selected",
                                   systemImage: "books.vertical",
                                   description: Text("Pick a topic or page from the sidebar, or create a new one."))
        }
    }

    /// The folder new pages and subtopics go into (nil at the library root → new topic).
    private var topicFolder: URL? {
        guard let sel = store.selectedFileURL, store.topicURL(for: sel) != nil else { return nil }
        return store.isDirectory(sel) ? sel : sel.deletingLastPathComponent()
    }

    // MARK: - Dialog launchers
    private func startNewFile() { newName = "Untitled"; showNewFile = true }
    private func startNewFolder() { newName = "New Folder"; showNewFolder = true }
}

/// Simple full-bleed viewer for image attachments selected in the tree.
struct ImageFileView: View {
    let url: URL
    var body: some View {
        Group {
            if let data = try? Data(contentsOf: url), let img = Image(platformData: data) {
                img.resizable().scaledToFit().padding()
            } else {
                ContentUnavailableView("Cannot Preview Image", systemImage: "photo")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .navigationTitle(url.lastPathComponent)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
