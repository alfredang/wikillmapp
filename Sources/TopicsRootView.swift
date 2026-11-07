#if os(macOS)
import SwiftUI
import AppKit

/// Panes outside the topics tree.
enum SupportPane: String, CaseIterable, Identifiable {
    case agents, graph, settings, feedback, about
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .agents:   return "person.3"
        case .graph:    return "point.3.connected.trianglepath.dotted"
        case .settings: return "gearshape"
        case .feedback: return "bubble.left.and.bubble.right"
        case .about:    return "info.circle"
        }
    }
}

enum SidebarSelection: Hashable {
    case node(URL)
    case pane(SupportPane)
    case agent(URL)
}

/// What a name prompt creates.
private enum NamePrompt: Identifiable {
    case topic
    case subtopic(in: URL)
    case page(in: URL)
    case rename(URL)

    var id: String {
        switch self {
        case .topic: return "topic"
        case .subtopic(let u): return "sub:" + u.path
        case .page(let u): return "page:" + u.path
        case .rename(let u): return "rename:" + u.path
        }
    }

    var title: String {
        switch self {
        case .topic: return "New Topic"
        case .subtopic: return "New Subtopic"
        case .page: return "New Page"
        case .rename: return "Rename"
        }
    }

    var message: String {
        switch self {
        case .topic: return "A topic is a folder of HTML pages, with its own sources (raw/) and log."
        case .subtopic(let u): return "Created inside “\(u.lastPathComponent)”. Number it to set the order, e.g. “02 Tool Design”."
        case .page(let u): return "An HTML page from the library template, in “\(u.lastPathComponent)”."
        case .rename(let u): return "Rename “\(u.lastPathComponent)”."
        }
    }
}

/// Desktop root, laid out like the Planner app: the Topics sidebar on the left, the selected
/// topic / page in the middle, and the Claude Code agent panel on the right.
struct TopicsRootView: View {
    @EnvironmentObject var store: VaultStore
    @ObservedObject private var agents = AgentPanelModel.shared

    @State private var pane: SupportPane?
    @State private var team: [AgentDefinition] = []
    /// The agent shown while `pane` is `.agents`; nil shows the whole team.
    @State private var selectedAgent: URL?
    @State private var expanded: Set<URL> = []
    /// Sidebar sections the person has collapsed (comma-separated names), kept across launches.
    @AppStorage("collapsedTopicSections") private var collapsedSectionsRaw = ""
    @State private var namePrompt: NamePrompt?
    @State private var nameText = ""
    @State private var deleteTarget: URL?

    @AppStorage("agentPanelVisible") private var agentVisible = true
    @AppStorage("agentPanelWidth") private var agentWidth = 460.0
    @State private var dragStartWidth: CGFloat?
    @State private var dividerHovered = false

    private static let panelMinWidth: CGFloat = 320
    private static let compactThreshold: CGFloat = 760

    private var selection: Binding<SidebarSelection?> {
        Binding(
            get: {
                if pane == .agents, let selectedAgent { return .agent(selectedAgent) }
                if let pane { return .pane(pane) }
                return store.selectedFileURL.map { .node($0) }
            },
            set: { newValue in
                switch newValue {
                case .pane(let p): pane = p; selectedAgent = nil
                case .agent(let url): pane = .agents; selectedAgent = url
                case .node(let url): pane = nil; store.selectedFileURL = url
                case nil: break
                }
            })
    }

    /// Off the main thread: the library can sit in iCloud Drive, where a read can stall.
    private func reloadTeam() {
        guard let root = store.rootURL else { team = []; return }
        Task {
            let loaded = await Task.detached { AgentDefinition.load(from: root) }.value
            if loaded != team, store.rootURL == root { team = loaded }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailWithAgent
                .toolbar { toolbar }
        }
        .task {
            store.restoreVaultIfNeeded()
            agents.openLocal = { url in store.select(url); pane = nil }
            if let root = store.rootURL { agents.setWorkspace(root.path) }
            reloadTeam()
            #if DEBUG
            // `-debugSelect <path relative to the library>` opens a topic/page (screenshots, UI checks).
            if let rel = UserDefaults.standard.string(forKey: "debugSelect"), let root = store.rootURL {
                store.select(root.appendingPathComponent(rel))
            }
            // `-debugPane agents` opens a pane outside the topics tree.
            if let name = UserDefaults.standard.string(forKey: "debugPane") {
                pane = SupportPane(rawValue: name)
            }
            // `-debugAgent wiki-critic` opens one agent.
            if let name = UserDefaults.standard.string(forKey: "debugAgent"), let root = store.rootURL {
                pane = .agents
                selectedAgent = root.appendingPathComponent("\(AgentDefinition.folder)/\(name).md")
            }
            #endif
        }
        .onChange(of: store.rootURL) { _, url in
            if let url { agents.setWorkspace(url.path) }
            reloadTeam()
        }
        .onChange(of: store.selectedFileURL) { _, url in revealInTree(url) }
        .onChange(of: store.openVaultRequested) { _, requested in
            guard requested else { return }
            store.openVaultRequested = false
            presentOpenLibraryPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refresh()
            reloadTeam()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTopic)) { _ in ask(.topic) }
        .onReceive(NotificationCenter.default.publisher(for: .newPage)) { _ in
            if let dir = targetFolder { ask(.page(in: dir)) } else { ask(.topic) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newSubtopic)) { _ in
            if let dir = targetFolder { ask(.subtopic(in: dir)) } else { ask(.topic) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleAgentPanel)) { _ in
            withAnimation { agentVisible.toggle() }
        }
        .alert(namePrompt?.title ?? "", isPresented: Binding(get: { namePrompt != nil },
                                                             set: { if !$0 { namePrompt = nil } }),
               presenting: namePrompt) { prompt in
            TextField("Name", text: $nameText)
            Button(prompt.title.hasPrefix("Rename") ? "Rename" : "Create") { commit(prompt) }
            Button("Cancel", role: .cancel) {}
        } message: { prompt in
            Text(prompt.message)
        }
        .confirmationDialog("Move “\(deleteTarget?.lastPathComponent ?? "")” to the Trash?",
                            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                if let url = deleteTarget { store.delete(url) }
                deleteTarget = nil
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: selection) {
            topicsSection

            if store.rootURL != nil {
                Section("Agents") {
                    Label("All Agents", systemImage: SupportPane.agents.symbol)
                        .tag(SidebarSelection.pane(.agents))
                        .help("The whole team: names, models, tools, skills and instructions")
                    ForEach(team) { agent in
                        AgentSidebarRow(agent: agent)
                            .tag(SidebarSelection.agent(agent.url))
                            .help(agent.description)
                    }
                }
            }

            if let root = store.rootURL {
                Section("Library") {
                    Label("Graph", systemImage: SupportPane.graph.symbol)
                        .tag(SidebarSelection.pane(.graph))
                        .help("A 3D map of how every page links to every other, like Obsidian's graph view")
                    Label("Agent Schema", systemImage: "doc.text")
                        .tag(SidebarSelection.node(root.appendingPathComponent(TopicLibrary.schemaFile)))
                        .help("CLAUDE.md — how the agent maintains this library")
                    Label("Page Template", systemImage: "doc.richtext")
                        .tag(SidebarSelection.node(root.appendingPathComponent(TopicLibrary.templateFile)))
                        .help("_template.html — the look every page starts from")
                }
            }

            Section("Support") {
                ForEach(SupportPane.allCases.filter { $0 != .agents && $0 != .graph }) { p in
                    Label(p.title, systemImage: p.symbol).tag(SidebarSelection.pane(p))
                }
            }
        }
        .listStyle(.sidebar)
        // The tree stays mounted under the results: swapping rows in this List left stale ones
        // on screen, and a new List takes keyboard focus from the search field.
        .opacity(store.isFilteringByTag ? 0 : 1)
        .allowsHitTesting(!store.isFilteringByTag)
        .accessibilityHidden(store.isFilteringByTag)
        .overlay {
            if store.isFilteringByTag {
                TagResultsPane { selection.wrappedValue = .node($0) }
            }
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 320, max: 440)
        .navigationTitle(store.vaultName)
        .safeAreaInset(edge: .top, spacing: 0) { TagFilterBar() }
        .safeAreaInset(edge: .bottom, spacing: 0) { libraryFooter }
    }

    private var topicsSection: some View {
        Section {
            if store.topics.isEmpty {
                Text("No topics yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(TopicSection.allCases.filter { $0 != .other }) { section in
                let items = store.topics(in: section)
                DisclosureGroup(isExpanded: sectionBinding(section)) {
                    if items.isEmpty {
                        Text("No topics yet.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(items) { topic in
                        TopicTreeRow(node: topic, depth: 0, expanded: $expanded, actions: rowActions)
                    }
                } label: {
                    Label(section.rawValue, systemImage: section.symbol)
                        .fontWeight(.semibold)
                        .badge(items.count)
                        .contentShape(Rectangle())
                        .onTapGesture { toggleSection(section) }
                        .help("Topics tagged “\(section.rawValue.lowercased())” — click to show or hide")
                }
            }
            // Topics without a section tag (often ones still being written) sit below the
            // sections as plain rows — no "Other" heading.
            ForEach(store.topics(in: .other)) { topic in
                TopicTreeRow(node: topic, depth: 0, expanded: $expanded, actions: rowActions)
            }
            Button { ask(.topic) } label: {
                Label("New Topic…", systemImage: "plus.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        } header: {
            HStack {
                Text("Topics")
                Spacer()
                if !expanded.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { expanded.removeAll() }
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Collapse all")
                }
            }
        }
    }

    private var collapsedSections: Set<String> {
        Set(collapsedSectionsRaw.split(separator: ",").map(String.init))
    }

    private func setSection(_ section: TopicSection, open: Bool) {
        var closed = collapsedSections
        if open { closed.remove(section.rawValue) } else { closed.insert(section.rawValue) }
        collapsedSectionsRaw = closed.sorted().joined(separator: ",")
    }

    private func toggleSection(_ section: TopicSection) {
        withAnimation(.easeInOut(duration: 0.15)) {
            setSection(section, open: collapsedSections.contains(section.rawValue))
        }
    }

    private func sectionBinding(_ section: TopicSection) -> Binding<Bool> {
        Binding(get: { !collapsedSections.contains(section.rawValue) },
                set: { setSection(section, open: $0) })
    }

    /// Library location, pinned under the sidebar like Planner's sync row.
    private var libraryFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder").font(.system(size: 11)).foregroundStyle(.secondary)
            Text(store.rootURL?.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? "No library")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button { store.requestOpenVault() } label: {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .help("Open another library folder (⌘O)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .help(store.rootURL?.path ?? "")
    }

    private var rowActions: TopicRowActions {
        TopicRowActions(
            newPage: { ask(.page(in: $0)) },
            newSubtopic: { ask(.subtopic(in: $0)) },
            rename: { ask(.rename($0)) },
            delete: { deleteTarget = $0 },
            agent: { action, url in
                store.selectedFileURL = url
                pane = nil
                agentVisible = true
                if let ctx = context(for: url) {
                    agents.send(action.prompt(context: ctx))
                }
            })
    }

    /// Expands the ancestors of a selection (e.g. after following a link in a page).
    private func revealInTree(_ url: URL?) {
        guard let url, let root = store.rootURL else { return }
        let dir = store.isDirectory(url) ? url : url.deletingLastPathComponent()
        var chain = TopicLibrary.folderChain(root: root, to: dir)
        if store.isDirectory(url) { chain.removeLast() }
        expanded.formUnion(chain)
        // Open the section holding the topic, so the revealed row is visible.
        let topicURL = TopicLibrary.folderChain(root: root, to: dir).first?.standardizedFileURL
        if let topic = store.topics.first(where: { $0.url.standardizedFileURL == topicURL }) {
            setSection(store.section(of: topic), open: true)
        }
    }

    // MARK: - Detail + agent panel

    @ViewBuilder
    private var detail: some View {
        if let pane {
            switch pane {
            case .agents:   AgentsView(agents: team, selected: selectedAgent)
            case .graph:    LibraryGraphView { url in store.select(url); self.pane = nil }
            case .settings: SettingsView()
            case .feedback: FeedbackView()
            case .about:    AboutView()
            }
        } else if let url = store.selectedFileURL {
            TopicDetailView(url: url,
                            onNewPage: { ask(.page(in: $0)) },
                            onNewSubtopic: { ask(.subtopic(in: $0)) },
                            onAgent: { action, url in rowActions.agent(action, url) })
                .id(url)
        } else {
            LibraryHomeView(onNewTopic: { ask(.topic) })
        }
    }

    /// Detail with the agent panel docked on the right; on a narrow window the panel slides
    /// over the content instead. Same width in both modes so the terminal never reflows.
    private var detailWithAgent: some View {
        GeometryReader { geo in
            let compact = geo.size.width < Self.compactThreshold
            let width = min(max(Self.panelMinWidth, CGFloat(agentWidth)),
                            max(Self.panelMinWidth, geo.size.width * 0.6)).rounded()
            HStack(spacing: 0) {
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                if agentVisible && !compact {
                    resizeDivider(maxWidth: geo.size.width * 0.6)
                    AgentPanel(isVisible: $agentVisible)
                        .frame(width: width)
                        .transition(.move(edge: .trailing))
                }
            }
            .overlay {
                if agentVisible && compact {
                    ZStack(alignment: .trailing) {
                        Color.black.opacity(0.3)
                            .onTapGesture { withAnimation { agentVisible = false } }
                        AgentPanel(isVisible: $agentVisible)
                            .frame(width: min(width, (geo.size.width - 44).rounded()))
                            .shadow(color: .black.opacity(0.35), radius: 14, x: -6, y: 0)
                    }
                    .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: agentVisible)
        }
    }

    private func resizeDivider(maxWidth: CGFloat) -> some View {
        let active = dividerHovered || dragStartWidth != nil
        return ZStack {
            Rectangle().fill(Color.primary.opacity(active ? 0.08 : 0))
            Rectangle()
                .fill(active ? Color(nsColor: .controlAccentColor) : Color(nsColor: .separatorColor))
                .frame(width: active ? 3 : 1)
            if !active {
                Capsule().fill(Color.secondary.opacity(0.45)).frame(width: 3, height: 28)
            }
        }
        .frame(width: 11)
        .overlay(
            PanelResizeHandle(
                onHover: { dividerHovered = $0 },
                onDrag: { dx in
                    if dragStartWidth == nil { dragStartWidth = CGFloat(agentWidth) }
                    let proposed = (dragStartWidth ?? CGFloat(agentWidth)) - dx
                    agentWidth = Double(min(max(Self.panelMinWidth, proposed),
                                            max(Self.panelMinWidth, maxWidth)).rounded())
                },
                onEnded: { dragStartWidth = nil }))
        .animation(.easeInOut(duration: 0.12), value: active)
        .accessibilityLabel("Resize agent panel")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Menu {
                Button { ask(.topic) } label: { Label("New Topic…", systemImage: "books.vertical") }
                if let dir = targetFolder {
                    Button { ask(.subtopic(in: dir)) } label: { Label("New Subtopic…", systemImage: "folder.badge.plus") }
                    Button { ask(.page(in: dir)) } label: { Label("New Page…", systemImage: "doc.badge.plus") }
                }
            } label: {
                Image(systemName: "plus")
            }
            .help("New topic, subtopic or page")
        }
        ToolbarItem(placement: .automatic) {
            Button { withAnimation { agentVisible.toggle() } } label: {
                Image(systemName: "sparkles.rectangle.stack")
            }
            .help(agentVisible ? "Hide the agent panel (⌥⌘T)" : "Show the agent panel (⌥⌘T)")
        }
    }

    // MARK: - Helpers

    /// The folder new pages / subtopics go into, from the current selection (inside a topic).
    private var targetFolder: URL? {
        guard let sel = store.selectedFileURL, store.topicURL(for: sel) != nil else { return nil }
        return store.isDirectory(sel) ? sel : sel.deletingLastPathComponent()
    }

    private func context(for url: URL) -> WikiContext? {
        guard let topic = store.topicURL(for: url) else { return nil }
        let isDir = store.isDirectory(url)
        let folder = isDir ? url : url.deletingLastPathComponent()
        return WikiContext(topic: store.relativePath(topic),
                           folder: store.relativePath(folder),
                           page: isDir ? nil : store.relativePath(url))
    }

    private func ask(_ prompt: NamePrompt) {
        switch prompt {
        case .topic, .page: nameText = ""
        case .subtopic(let dir):
            let count = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]))?
                .filter { store.isDirectory($0) && $0.lastPathComponent != TopicLibrary.sourcesFolder }.count ?? 0
            nameText = String(format: "%02d ", count + 1)
        case .rename(let url): nameText = url.lastPathComponent
        }
        namePrompt = prompt
    }

    private func commit(_ prompt: NamePrompt) {
        let name = nameText
        switch prompt {
        case .topic: store.createTopic(named: name)
        case .subtopic(let dir): store.createSubtopic(named: name, in: dir)
        case .page(let dir): store.createPage(titled: name, in: dir)
        case .rename(let url): store.rename(url, to: name)
        }
        pane = nil
        namePrompt = nil
    }

    private func presentOpenLibraryPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Library"
        panel.message = "Choose a folder to use as your Topics library. Each sub-folder is a topic."
        if panel.runModal() == .OK, let url = panel.url {
            store.openVault(at: url)
        }
    }
}

/// Tag search results, shown in place of the tree.
private struct TagResultsPane: View {
    @EnvironmentObject var store: VaultStore
    var onSelect: (URL) -> Void

    var body: some View {
        let results = store.tagResults
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text(results.count == 1 ? "1 result" : "\(results.count) results")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                if results.isEmpty {
                    Text("No pages match.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                }
                ForEach(results, id: \.url) { page in
                    row(page)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ page: LinkIndex.Page) -> some View {
        let node = store.nodeURL(forPage: page.url)
        let selected = store.selectedFileURL?.standardizedFileURL.path == node.standardizedFileURL.path
        return Button { onSelect(node) } label: {
            TagResultRow(page: page)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.1) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Actions offered on a sidebar row.
struct TopicRowActions {
    var newPage: (URL) -> Void
    var newSubtopic: (URL) -> Void
    var rename: (URL) -> Void
    var delete: (URL) -> Void
    var agent: (WikiAction, URL) -> Void
}

/// One row of the Topics tree: a topic / subtopic folder (expandable) or a page.
struct TopicTreeRow: View {
    @EnvironmentObject var store: VaultStore
    let node: FileNode
    let depth: Int
    @Binding var expanded: Set<URL>
    let actions: TopicRowActions

    var body: some View {
        if node.isDirectory, let children = node.children, !children.isEmpty {
            DisclosureGroup(isExpanded: Binding(
                get: { expanded.contains(node.url) },
                set: { open in if open { expanded.insert(node.url) } else { expanded.remove(node.url) } })) {
                ForEach(store.sidebarChildren(of: node)) { child in
                    TopicTreeRow(node: child, depth: depth + 1, expanded: $expanded, actions: actions)
                }
            } label: {
                label
            }
            .tag(SidebarSelection.node(node.url))
        } else {
            label.tag(SidebarSelection.node(node.url))
        }
    }

    private var icon: String {
        if node.isDirectory && depth == 0 { return "books.vertical" }
        return node.systemImage
    }

    private var label: some View {
        let title = store.sidebarLabel(for: node)
        return Label {
            Text(title).lineLimit(1).truncationMode(.tail)
        } icon: {
            Image(systemName: icon)
        }
        .badge(depth == 0 ? node.pageCount : 0)
        .contextMenu { menu }
        .help(title == node.name ? node.name : "\(title)\n\(node.name)")
    }

    @ViewBuilder
    private var menu: some View {
        if node.isDirectory {
            Button { actions.newPage(node.url) } label: { Label("New Page…", systemImage: "doc.badge.plus") }
            Button { actions.newSubtopic(node.url) } label: { Label("New Subtopic…", systemImage: "folder.badge.plus") }
            Divider()
            Button { actions.agent(.outline, node.url) } label: { Label("Ask Agent to Outline", systemImage: "sparkles") }
            Button { actions.agent(.lint, node.url) } label: { Label("Ask Agent to Lint", systemImage: "checkmark.seal") }
            if node.name == TopicLibrary.sourcesFolder {
                Button { actions.agent(.ingest, node.url) } label: { Label("Ingest Sources", systemImage: "tray.and.arrow.down") }
            }
            Divider()
        } else {
            Button { NSWorkspace.shared.open(node.url) } label: { Label("Open in Default App", systemImage: "safari") }
        }
        Button { NSWorkspace.shared.activateFileViewerSelecting([node.url]) } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
        Button { actions.rename(node.url) } label: { Label("Rename…", systemImage: "pencil") }
        Button(role: .destructive) { actions.delete(node.url) } label: { Label("Move to Trash", systemImage: "trash") }
    }
}

/// AppKit drag handle for the panel divider (a SwiftUI drag loses events to the terminal).
struct PanelResizeHandle: NSViewRepresentable {
    var onHover: (Bool) -> Void
    var onDrag: (CGFloat) -> Void
    var onEnded: () -> Void

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: HandleView, context: Context) {
        view.onHover = onHover
        view.onDrag = onDrag
        view.onEnded = onEnded
    }

    final class HandleView: NSView {
        var onHover: ((Bool) -> Void)?
        var onDrag: ((CGFloat) -> Void)?
        var onEnded: (() -> Void)?
        private var dragStartX: CGFloat?

        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero,
                                           options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                           owner: self))
        }

        override func mouseEntered(with event: NSEvent) { onHover?(true) }
        override func mouseExited(with event: NSEvent) { onHover?(false) }
        override func mouseDown(with event: NSEvent) { dragStartX = event.locationInWindow.x }
        override func mouseDragged(with event: NSEvent) {
            guard let start = dragStartX else { return }
            onDrag?(event.locationInWindow.x - start)
        }
        override func mouseUp(with event: NSEvent) {
            if dragStartX != nil { dragStartX = nil; onEnded?() }
        }
    }
}

extension Notification.Name {
    static let newTopic = Notification.Name("newTopic")
    static let newPage = Notification.Name("newPage")
    static let newSubtopic = Notification.Name("newSubtopic")
    static let toggleAgentPanel = Notification.Name("toggleAgentPanel")
}
#endif
