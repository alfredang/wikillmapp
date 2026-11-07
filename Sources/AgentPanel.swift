#if os(macOS)
import SwiftUI
import AppKit
import SwiftTerm

// The right-hand "agent mode" panel, modelled on the Planner app: a tab per agent CLI running
// in a real pty (SwiftTerm), started in the library folder so the agent reads the library's
// CLAUDE.md schema.

/// The agents the panel can run, one tab each.
enum AgentKind: String, CaseIterable, Identifiable {
    case claude, codex, shell

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex:  return "Codex"
        case .shell:  return "Terminal"
        }
    }

    var symbol: String { self == .shell ? "terminal" : "sparkles" }

    /// The CLI to exec (nil = the user's login shell).
    var executable: String? {
        switch self {
        case .claude: return "claude"
        case .codex:  return "codex"
        case .shell:  return nil
        }
    }

    /// Arguments after the executable. Claude runs without per-command permission prompts,
    /// matching the Planner app — the agent only works inside the library folder. It defaults
    /// to Opus 5.5 at high effort; the library's subagents set their own models.
    var arguments: String {
        self == .claude ? " --dangerously-skip-permissions --model claude-opus-5-5 --effort high" : ""
    }

    /// Shell test that's true when this folder has an earlier conversation, and the
    /// arguments that resume it.
    var resume: (test: String, arguments: String)? {
        switch self {
        case .claude:
            return (#"ls "$HOME/.claude/projects/$(printf %s "$PWD" | sed 's/[^A-Za-z0-9]/-/g')" 2>/dev/null | grep -q '\.jsonl$'"#,
                    arguments + " --continue")
        case .codex:
            return (#"find "$HOME/.codex/sessions" -name 'rollout-*.jsonl' 2>/dev/null | sort -r | head -200 | while read -r f; do head -n1 "$f" | grep -qF "\"cwd\":\"$PWD\"" && echo found && break; done | grep -q found"#,
                    arguments + " resume --last")
        case .shell:
            return nil
        }
    }

    var newSessionCommand: String? {
        switch self {
        case .claude: return "/clear"
        case .codex:  return "/new"
        case .shell:  return nil
        }
    }

    var historyCommand: String? { self == .shell ? nil : "/resume" }
}

/// One-click LLM-wiki operations from the sidebar, phrased against the library's CLAUDE.md.
enum WikiAction {
    case outline, ingest, lint

    /// The single-line instruction typed into the agent.
    func prompt(context: WikiContext) -> String {
        let scope = context.scopeSentence
        switch self {
        case .outline:
            return "\(scope) Outline \"\(context.folder)\" as a learning wiki: create numbered subtopic folders with index.html overviews and focused concept pages from _template.html, keep every index.html card map current, and log it in \"\(context.topic)/log.md\"."
        case .ingest:
            return "\(scope) Ingest the sources in \"\(context.topic)/raw/\" that are not yet in log.md: update or create the affected pages and index.html maps, cite the source files, and append to \"\(context.topic)/log.md\"."
        case .lint:
            return "\(scope) Lint \"\(context.topic)\": fix broken relative links, orphan pages not linked from any index.html, missing breadcrumbs, contradictions and stale facts; add useful cross-links; log the changes in \"\(context.topic)/log.md\"."
        }
    }
}

/// What a wiki action's instruction refers to.
struct WikiContext {
    var topic: String      // e.g. "CCAR-F Claude Certified Architect Foundation"
    var folder: String     // folder the selection lives in, relative to the library
    var page: String?      // selected page, relative to the library

    var scopeSentence: String {
        if let page { return "[Topic: \(topic) · Page: \(page)]" }
        return "[Topic: \(topic) · Folder: \(folder)]"
    }
}

/// Running agent tabs. Terminals live here, not in the views, so hiding the panel never
/// restarts an agent. Tabs start on first use; Claude Code starts with the panel.
@MainActor
final class AgentPanelModel: ObservableObject {
    static let shared = AgentPanelModel()

    struct Tab: Identifiable {
        let kind: AgentKind
        var id: AgentKind { kind }
        var runID = UUID()
        var resume = true
        var exited = false
    }

    @Published private(set) var tabs: [Tab] = AgentKind.allCases.map { Tab(kind: $0) }
    @Published var selected: AgentKind = .claude
    /// Tabs whose process has been started (only those get a terminal host).
    @Published private(set) var started: Set<AgentKind> = []
    /// The folder every agent runs in — the library root. Agents start once it is known.
    @Published private(set) var workspace: String?

    private var sessions: [AgentKind: AgentTerminalSession] = [:]
    /// A tab whose terminal should take the keyboard once it is on screen.
    private var focusWhenHosted: AgentKind?
    /// Opens library files clicked in the terminal (set by the root view).
    var openLocal: ((URL) -> Void)?

    func tab(_ kind: AgentKind) -> Tab? { tabs.first { $0.kind == kind } }

    /// Points every agent at a (new) library folder, restarting running agents there.
    func setWorkspace(_ path: String) {
        guard path != workspace else { return }
        let hadWorkspace = workspace != nil
        workspace = path
        if hadWorkspace { for kind in started { restart(kind, resume: true) } }
    }

    /// Shows a tab, starting it if needed, and gives its terminal the keyboard.
    func select(_ kind: AgentKind) {
        selected = kind
        started.insert(kind)
        if let session = sessions[kind] {
            // After SwiftUI has un-hidden the terminal.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { session.focus() }
        } else {
            focusWhenHosted = kind
        }
    }

    /// Whether a terminal that just got its host should take the keyboard.
    func takeHostFocus(_ kind: AgentKind) -> Bool {
        guard focusWhenHosted == kind else { return false }
        focusWhenHosted = nil
        return true
    }

    func session(for tab: Tab) -> AgentTerminalSession {
        if let s = sessions[tab.kind], s.runID == tab.runID { return s }
        sessions[tab.kind]?.terminate()
        let kind = tab.kind
        let s = AgentTerminalSession(kind: kind, workspace: workspace ?? NSHomeDirectory(), resume: tab.resume, runID: tab.runID,
                                     openLocal: { [weak self] url in self?.openLocal?(url) },
                                     onExit: { [weak self] in self?.markExited(kind) })
        sessions[kind] = s
        return s
    }

    func restart(_ kind: AgentKind, resume: Bool = true) {
        guard let i = tabs.firstIndex(where: { $0.kind == kind }) else { return }
        sessions.removeValue(forKey: kind)?.terminate()
        tabs[i].resume = resume
        tabs[i].exited = false
        tabs[i].runID = UUID()
    }

    func newSession(_ kind: AgentKind) {
        guard let tab = tab(kind) else { return }
        if tab.exited || kind.newSessionCommand == nil || sessions[kind] == nil {
            restart(kind, resume: false)
        } else if let cmd = kind.newSessionCommand {
            sessions[kind]?.enqueue(cmd)
        }
    }

    func showHistory(_ kind: AgentKind) {
        guard let tab = tab(kind), let cmd = kind.historyCommand else { return }
        select(kind)
        if tab.exited { restart(kind, resume: true) } else { sessions[kind]?.enqueue(cmd) }
    }

    /// Types an instruction into an agent (starting it if needed) and submits it.
    func send(_ prompt: String, to kind: AgentKind = .claude) {
        select(kind)
        if tab(kind)?.exited == true { restart(kind, resume: true) }
        guard let tab = tab(kind) else { return }
        session(for: tab).enqueue(prompt)
    }

    private func markExited(_ kind: AgentKind) {
        guard let i = tabs.firstIndex(where: { $0.kind == kind }) else { return }
        tabs[i].exited = true
    }
}

/// The panel view: tab chips and the terminal.
struct AgentPanel: View {
    @Binding var isVisible: Bool

    @ObservedObject private var model = AgentPanelModel.shared

    private static let scrollerInset = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)

    var body: some View {
        VStack(spacing: 0) {
            terminalHeader
            Divider()
            ZStack {
                Color.black
                ForEach(model.workspace == nil ? [] : model.tabs.filter { model.started.contains($0.kind) }) { tab in
                    let isSelected = tab.kind == model.selected
                    AgentTerminalHost(session: model.session(for: tab), kind: tab.kind, isActive: isSelected)
                        .padding(.leading, 8)
                        .padding(.trailing, 8 - Self.scrollerInset)
                        .padding(.vertical, 6)
                        .id(tab.runID)
                        .opacity(isSelected ? 1 : 0)
                        .allowsHitTesting(isSelected)
                }
                if model.tab(model.selected)?.exited == true { exitOverlay }
            }
            .clipped()
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear { model.select(model.selected) }
    }

    private var terminalHeader: some View {
        HStack(spacing: 2) {
            ForEach(model.tabs) { tab in
                AgentTabChip(title: tab.kind.title, symbol: tab.kind.symbol,
                             status: model.started.contains(tab.kind) ? (tab.exited ? .red : .green) : nil,
                             isSelected: tab.kind == model.selected) {
                    model.select(tab.kind)
                }
            }
            Spacer(minLength: 4)
            Menu {
                Button { model.newSession(model.selected) } label: {
                    Label("New Session", systemImage: "square.and.pencil")
                }
                Button { model.showHistory(model.selected) } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .disabled(model.selected.historyCommand == nil)
                Divider()
                Button { model.restart(model.selected, resume: false) } label: {
                    Label("Restart \(model.selected.title)", systemImage: "arrow.clockwise")
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Session options")
            Button {
                withAnimation { isVisible = false }
            } label: {
                Image(systemName: "sidebar.trailing").font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("Hide the agent panel (⌥⌘T)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var exitOverlay: some View {
        VStack(spacing: 12) {
            Text("\(model.selected.title) stopped.").foregroundStyle(.secondary)
            Button("Restart \(model.selected.title)") { model.restart(model.selected) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}

private struct AgentTabChip: View {
    var title: String
    var symbol: String
    var status: SwiftUI.Color?
    var isSelected: Bool
    var select: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10))
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            if let status { Circle().fill(status).frame(width: 6, height: 6) }
        }
        .foregroundStyle(isSelected ? Theme.accent : .secondary)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Theme.accent.opacity(0.14) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
    }
}

/// Hosts a session's terminal view; tearing the host down leaves the process running.
private struct AgentTerminalHost: NSViewRepresentable {
    let session: AgentTerminalSession
    let kind: AgentKind
    var isActive: Bool

    func makeNSView(context: Context) -> TerminalContainerView {
        let session = session
        let kind = kind
        let container = TerminalContainerView(terminal: session.view) {
            if AgentPanelModel.shared.takeHostFocus(kind) { session.focus() }
        }
        session.setActive(isActive)
        return container
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) { session.setActive(isActive) }

    static func dismantleNSView(_ container: TerminalContainerView, coordinator: ()) {
        container.release()
    }
}

/// Keeps the terminal the size of this view. Autoresizing can't do it: the host starts at zero
/// size, and AppKit shares growth out in proportion to existing size, so a zero-size terminal
/// would stay at its minimum (1 row by 2 columns) and show a black screen.
///
/// SwiftUI can create a second host for the same terminal during layout, and that host may never
/// reach the screen. So a host takes the terminal only once it is on screen at a real size, and
/// never from another host that is.
private final class TerminalContainerView: NSView {
    private static let hosts = NSHashTable<TerminalContainerView>.weakObjects()

    private let terminal: NSView
    private let onAttach: () -> Void

    init(terminal: NSView, onAttach: @escaping () -> Void) {
        self.terminal = terminal
        self.onAttach = onAttach
        super.init(frame: .zero)
        Self.hosts.add(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var isOnScreen: Bool {
        window != nil && bounds.width > 1 && bounds.height > 1
    }

    private func attachTerminal() {
        guard isOnScreen, terminal.superview !== self else { return }
        if let owner = terminal.superview as? TerminalContainerView, owner.isOnScreen { return }
        terminal.removeFromSuperview()
        addSubview(terminal)
        onAttach()
    }

    /// Lets go of the terminal, handing it to another host of the same terminal if one is on screen.
    func release() {
        Self.hosts.remove(self)
        guard terminal.superview === self else { return }
        terminal.removeFromSuperview()
        Self.hosts.allObjects.first { $0.terminal === terminal && $0.isOnScreen }?.attachTerminal()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachTerminal()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        attachTerminal()
        fitTerminal()
    }

    override func layout() {
        super.layout()
        attachTerminal()
        fitTerminal()
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        fitTerminal()
    }

    private func fitTerminal() {
        // A passing zero size would reflow the conversation into a sliver.
        guard bounds.width > 1, bounds.height > 1 else { return }
        for view in subviews where view.frame != bounds { view.frame = bounds }
    }
}

/// One agent process in a pty, started in the library folder.
@MainActor
final class AgentTerminalSession: NSObject, LocalProcessTerminalViewDelegate {
    let view = AgentTerminalView(frame: .zero)
    let runID: UUID
    private let startedAt = Date()
    private var onExit: (() -> Void)?
    private var linkRouter: AgentLinkRouter?
    private var wheelMonitor: Any?
    /// Instructions waiting to be typed, in order, one at a time.
    private var outbox: [String] = []
    private var isFlushing = false
    private var inputReadySince: Date?

    /// Seconds since launch.
    var age: Double { Date().timeIntervalSince(startedAt) }

    /// Whether the agent is showing a startup prompt, like Claude Code's folder trust check.
    /// Those are the person's to answer, and Return picks the default, which is often "No, exit".
    var isAskingToConfirm: Bool {
        guard let terminal = view.terminal else { return false }
        return (0..<terminal.rows).contains { row in
            // Letters only: TUIs skip over blank cells, so the "spaces" may be empty cells.
            let text = terminal.getLine(row: row)?.translateToString(trimRight: true) ?? ""
            return text.filter(\.isLetter).contains("Entertoconfirm")
        }
    }

    /// Whether the agent's TUI is up. Input sent before that is delivered in one burst when it
    /// starts, which turns the Return into a newline and leaves the message unsent. A TUI turns
    /// on bracketed paste as it starts; give up waiting after a while in case this one never does.
    private var isInputReady: Bool {
        if isAskingToConfirm {
            inputReadySince = nil
            return false
        }
        if age > 45 { return true }
        guard view.terminal?.bracketedPasteMode == true else { return false }
        let since = inputReadySince ?? Date()
        inputReadySince = since
        return Date().timeIntervalSince(since) > 1
    }

    init(kind: AgentKind, workspace: String, resume: Bool, runID: UUID,
         openLocal: @escaping (URL) -> Void, onExit: @escaping () -> Void) {
        self.runID = runID
        self.onExit = onExit
        super.init()
        let terminal = view
        terminal.processDelegate = self
        linkRouter = AgentLinkRouter(base: terminal, workspace: workspace, openLocal: openLocal)
        terminal.terminalDelegate = linkRouter
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak terminal] event in
            guard let terminal, event.window === terminal.window, !terminal.isHiddenOrHasHiddenAncestor,
                  terminal.bounds.contains(terminal.convert(event.locationInWindow, from: nil))
            else { return event }
            return terminal.handleWheel(event) ? nil : event
        }
        terminal.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        terminal.nativeBackgroundColor = .black
        terminal.nativeForegroundColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        Self.hideScroller(in: terminal)
        DispatchQueue.main.async { Self.hideScroller(in: terminal) }

        // Inherit the environment minus any parent Claude Code / VS Code session state (a
        // `claude` started here must be a normal top-level session), and make sure the usual
        // CLI homes are on PATH — a Dock launch only gets launchd's minimal PATH.
        var env = ProcessInfo.processInfo.environment.filter { key, _ in
            !(key == "CLAUDECODE" || key.hasPrefix("CLAUDE_CODE_") || key.hasPrefix("CLAUDE_AGENT_SDK")
              || key == "CLAUDE_PID" || key == "CLAUDE_EFFORT"
              || key.hasPrefix("VSCODE_") || key == "TERM_PROGRAM" || key == "TERM_PROGRAM_VERSION")
        }
        let home = env["HOME"] ?? NSHomeDirectory()
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        let dirs = ["\(home)/.local/bin", "\(home)/.claude/local", "\(home)/Library/pnpm", "/opt/homebrew/bin", "/usr/local/bin"]
        env["PATH"] = (dirs + [env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")

        let quoted = "'" + workspace.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let bootstrap: String
        if let cli = kind.executable {
            let resumeLine = resume ? kind.resume.map { "  if \($0.test); then exec \(cli)\($0.arguments); fi\n" } ?? "" : ""
            // Claude Code runs on the person's own Claude login. An API key in the environment
            // (even one set by a login profile) would take priority and bill per token instead.
            // The library's agents run as an agent team: each is a teammate (its own session) the
            // person can watch and message from the list under the prompt, and the teammates
            // message each other. Exported after the login profile so it can't be overridden.
            let useClaudeLogin = kind == .claude
                ? "unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN\nexport CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1\n" : ""
            bootstrap = """
            \(useClaudeLogin)cd \(quoted) 2>/dev/null || cd ~
            if command -v \(cli) >/dev/null 2>&1; then
            \(resumeLine)  exec \(cli)\(kind.arguments)
            else
              echo '\(cli) CLI not found on PATH (e.g. ~/.local/bin/\(cli)).'
              echo 'Dropping into a plain shell:'
              exec /bin/zsh -i
            fi
            """
        } else {
            bootstrap = "cd \(quoted) 2>/dev/null || cd ~\nexec /bin/zsh -i"
        }
        terminal.startProcess(executable: "/bin/zsh", args: ["-l", "-c", bootstrap],
                              environment: env.map { "\($0.key)=\($0.value)" })
        watchExit(of: terminal.process.shellPid)
    }

    /// Queues a line to be typed once the agent is ready for input.
    func enqueue(_ text: String) {
        outbox.append(text)
        guard !isFlushing else { return }
        isFlushing = true
        flushOutbox()
    }

    private func flushOutbox() {
        guard !outbox.isEmpty else {
            isFlushing = false
            return
        }
        guard isInputReady else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.flushOutbox() }
            return
        }
        type(outbox.removeFirst())
        // After `type`'s delayed Return, so the next line doesn't clear this one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.flushOutbox() }
    }

    /// Types a line into the agent: clear the half-typed input (⌃U), paste the text, then
    /// press Return a moment later — sent together, TUIs treat the Return as part of the paste.
    private func type(_ text: String) {
        view.send(txt: "\u{15}")
        if let terminal = view.terminal, terminal.bracketedPasteMode {
            view.send(txt: "\u{1b}[200~" + text + "\u{1b}[201~")
        } else {
            view.send(txt: text)
        }
        let view = view
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { view.send(txt: "\r") }
    }

    func setActive(_ active: Bool) {
        Self.hideScroller(in: view)
        view.isHidden = !active
    }

    /// Gives the terminal the keyboard.
    func focus() {
        let view = view
        DispatchQueue.main.async {
            guard !view.isHiddenOrHasHiddenAncestor else { return }
            view.window?.makeFirstResponder(view)
        }
    }

    func terminate() {
        onExit = nil
        outbox = []
        if let monitor = wheelMonitor { NSEvent.removeMonitor(monitor) }
        wheelMonitor = nil
        let pid = view.process.shellPid
        view.terminate()
        view.removeFromSuperview()
        // SIGTERM alone is ignored by interactive shells and some TUIs; hang up the group.
        guard pid > 0 else { return }
        killpg(pid, SIGHUP)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if kill(pid, 0) == 0 { killpg(pid, SIGKILL) }
        }
    }

    private static func hideScroller(in view: NSView) {
        for sub in view.subviews where sub is NSScroller { sub.isHidden = true }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.reportExit() } }
    }

    /// SwiftTerm can miss an exit when a child keeps the pty open; wait on the pid too.
    private func watchExit(of pid: pid_t) {
        guard pid > 0 else { return }
        Thread.detachNewThread { [weak self] in
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.reportExit() } }
        }
    }

    private func reportExit() {
        outbox = []
        let report = onExit
        onExit = nil
        report?()
    }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}

/// Terminal view that pastes images/files as paths (agents attach them) and forwards the
/// wheel to full-screen TUIs so the conversation scrolls.
final class AgentTerminalView: LocalProcessTerminalView {
    private var pendingLines: CGFloat = 0

    override func paste(_ sender: Any) {
        let pasteboard = NSPasteboard.general
        let files = (pasteboard.readObjects(forClasses: [NSURL.self],
                                            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !files.isEmpty {
            pastePaths(files.map(\.path))
        } else if pasteboard.string(forType: .string) == nil, let path = Self.savePastedImage(from: pasteboard) {
            pastePaths([path])
        } else {
            super.paste(sender)
        }
    }

    private func pastePaths(_ paths: [String]) {
        let text = paths.map { $0.replacingOccurrences(of: " ", with: "\\ ") }.joined(separator: " ") + " "
        guard let terminal else { return }
        send(txt: terminal.bracketedPasteMode ? "\u{1b}[200~\(text)\u{1b}[201~" : text)
    }

    private static func savePastedImage(from pasteboard: NSPasteboard) -> String? {
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("topics-pastes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("paste-\(Int(Date().timeIntervalSince1970)).png")
        do { try png.write(to: url) } catch { return nil }
        return url.path
    }

    func handleWheel(_ event: NSEvent) -> Bool {
        guard let terminal, !event.modifierFlags.contains(.option),
              terminal.mouseMode != .off || terminal.isCurrentBufferAlternate else { return false }
        pendingLines += event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 12 : event.scrollingDeltaY
        let lines = Int(pendingLines.rounded(.towardZero))
        guard lines != 0 else { return true }
        pendingLines -= CGFloat(lines)
        let up = lines > 0
        let count = min(abs(lines), 10)
        if terminal.mouseMode != .off && allowMouseReporting {
            let point = convert(event.locationInWindow, from: nil)
            let col = max(0, min(terminal.cols - 1, Int(point.x / max(bounds.width, 1) * CGFloat(terminal.cols))))
            let row = max(0, min(terminal.rows - 1,
                                 Int((bounds.height - point.y) / max(bounds.height, 1) * CGFloat(terminal.rows))))
            let flags = terminal.encodeButton(button: up ? 4 : 5, release: false, shift: false, meta: false, control: false)
            for _ in 0..<count { terminal.sendEvent(buttonFlags: flags, x: col, y: row) }
        } else {
            let key = terminal.applicationCursor ? (up ? "\u{1b}OA" : "\u{1b}OB") : (up ? "\u{1b}[A" : "\u{1b}[B")
            for _ in 0..<count { send(txt: key) }
        }
        return true
    }
}

/// Terminal delegate shim: links to library files open in the app; web links in the browser.
final class AgentLinkRouter: TerminalViewDelegate {
    weak var base: LocalProcessTerminalView?
    let workspace: String
    let openLocal: (URL) -> Void

    init(base: LocalProcessTerminalView, workspace: String, openLocal: @escaping (URL) -> Void) {
        self.base = base
        self.workspace = workspace
        self.openLocal = openLocal
    }

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        let fixed = link.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? link
        guard let url = URL(string: link) ?? URL(string: fixed) else { return }
        if url.isFileURL, url.path.hasPrefix(workspace) {
            DispatchQueue.main.async { self.openLocal(url) }
        } else {
            NSWorkspace.shared.open(url)
        }
    }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        base?.sizeChanged(source: source, newCols: newCols, newRows: newRows)
    }
    func setTerminalTitle(source: TerminalView, title: String) { base?.setTerminalTitle(source: source, title: title) }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        base?.hostCurrentDirectoryUpdate(source: source, directory: directory)
    }
    func send(source: TerminalView, data: ArraySlice<UInt8>) { base?.send(source: source, data: data) }
    func scrolled(source: TerminalView, position: Double) { base?.scrolled(source: source, position: position) }
    func clipboardCopy(source: TerminalView, content: Data) { base?.clipboardCopy(source: source, content: content) }
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        base?.rangeChanged(source: source, startY: startY, endY: endY)
    }
}
#endif
