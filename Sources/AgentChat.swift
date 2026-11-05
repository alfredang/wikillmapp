#if os(macOS)
import SwiftUI
import AppKit

// The top half of the agent panel: a chat view of the Claude Code session running in the
// terminal below. There is only one session. Messages are typed into the terminal, and replies
// come from the transcript Claude Code writes to ~/.claude/projects/<folder>/<session>.jsonl,
// so anything typed directly in the terminal shows up here too.

/// One tool call, summarised for the chat ("Edit 01 Basics/index.html").
struct ChatTool: Equatable {
    var symbol: String
    var label: String
    /// A file inside the library, which the row can open in the app.
    var url: URL?
}

struct ChatEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case user(String)
        case assistant(String)
        case tool(ChatTool)
        case note(String)
    }
    let id: String
    let kind: Kind
}

/// Turns transcript records into chat entries. The transcript also holds request logs, hook
/// output and sub-agent work; only the conversation itself is kept.
enum ChatTranscriptParser {
    struct Output {
        var entries: [ChatEntry] = []
        /// Whether Claude is mid-turn after this record; nil when the record says nothing.
        var working: Bool?
    }

    /// User records wrapping terminal slash commands and injected context, not typed messages.
    private static let hiddenPrefixes = ["<command-name>", "<command-message>", "<command-args>", "<local-command",
                                         "<system-reminder>", "<bash-", "Caveat:"]

    static func parse(line: Data, workspace: String) -> Output {
        var output = Output()
        // Request logs can be huge and are never shown; skip them before decoding.
        if line.prefix(48).range(of: Data("api-request".utf8)) != nil { return output }
        guard let record = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let type = record["type"] as? String, type == "user" || type == "assistant",
              record["isSidechain"] as? Bool != true,
              record["isMeta"] as? Bool != true,
              record["isCompactSummary"] as? Bool != true,
              let message = record["message"] as? [String: Any]
        else { return output }
        let id = record["uuid"] as? String ?? UUID().uuidString

        if type == "user" {
            let blocks: [[String: Any]]
            if let text = message["content"] as? String {
                blocks = [["type": "text", "text": text]]
            } else {
                blocks = message["content"] as? [[String: Any]] ?? []
            }
            for (index, block) in blocks.enumerated() {
                if block["type"] as? String == "tool_result" {
                    output.working = true
                } else if let text = block["text"] as? String {
                    appendUser(text, id: "\(id)-\(index)", to: &output)
                }
            }
        } else {
            let stop = message["stop_reason"] as? String
            output.working = stop == nil || stop == "tool_use"
            for (index, block) in (message["content"] as? [[String: Any]] ?? []).enumerated() {
                let blockID = "\(id)-\(index)"
                switch block["type"] as? String {
                case "text":
                    let text = (block["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { output.entries.append(ChatEntry(id: blockID, kind: .assistant(text))) }
                case "tool_use":
                    let tool = describe(name: block["name"] as? String ?? "Tool",
                                        input: block["input"] as? [String: Any] ?? [:], workspace: workspace)
                    output.entries.append(ChatEntry(id: blockID, kind: .tool(tool)))
                default:
                    break
                }
            }
        }
        return output
    }

    private static func appendUser(_ text: String, id: String, to output: inout Output) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || hiddenPrefixes.contains(where: trimmed.hasPrefix) { return }
        if trimmed.hasPrefix("<task-notification>") {
            output.working = true
        } else if trimmed.hasPrefix("[Request interrupted") {
            output.working = false
            output.entries.append(ChatEntry(id: id, kind: .note("Stopped")))
        } else {
            output.working = true
            output.entries.append(ChatEntry(id: id, kind: .user(trimmed)))
        }
    }

    private static func describe(name: String, input: [String: Any], workspace: String) -> ChatTool {
        let prefix = workspace + "/"
        func relative(_ path: String) -> String { path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path }
        func file(_ verb: String, _ symbol: String) -> ChatTool {
            let path = input["file_path"] as? String ?? input["notebook_path"] as? String ?? ""
            return ChatTool(symbol: symbol, label: "\(verb) \(relative(path))",
                            url: path.hasPrefix(prefix) ? URL(fileURLWithPath: path) : nil)
        }
        func line(_ key: String) -> String {
            (input[key] as? String ?? "").split(separator: "\n").first.map(String.init) ?? ""
        }
        switch name {
        case "Read":                     return file("Read", "doc.text")
        case "Write":                    return file("Write", "doc.badge.plus")
        case "Edit", "MultiEdit", "NotebookEdit": return file("Edit", "pencil")
        case "Bash":
            let description = line("description")
            return ChatTool(symbol: "terminal", label: description.isEmpty ? line("command") : description)
        case "Grep", "Glob":             return ChatTool(symbol: "magnifyingglass", label: "Search \(line("pattern"))")
        case "WebSearch":                return ChatTool(symbol: "globe", label: "Search the web: \(line("query"))")
        case "WebFetch":                 return ChatTool(symbol: "globe", label: "Fetch \(line("url"))")
        case "Agent", "Task":            return ChatTool(symbol: "person.2", label: "Agent: \(line("description"))")
        case "TodoWrite":                return ChatTool(symbol: "checklist", label: "Update the task list")
        default:
            let short = name.components(separatedBy: "__").last ?? name
            return ChatTool(symbol: "wrench.and.screwdriver", label: short.replacingOccurrences(of: "_", with: " "))
        }
    }
}

/// Follows the newest transcript of a folder, reading only what was appended. Runs on the
/// transcript's background queue.
private final class ChatTranscriptReader: @unchecked Sendable {
    struct Update {
        var reset = false
        var entries: [ChatEntry] = []
        var working: Bool?
        var lastWrite: Date?
    }

    /// A long session's history is capped; the tail is what the chat shows anyway.
    private static let maxInitialRead: UInt64 = 24 * 1024 * 1024

    private var workspace = ""
    private var directory: URL?
    private var current: URL?
    private var offset: UInt64 = 0
    private var remainder = Data()
    private var excluded = Set<String>()
    private var notBefore: Date?

    func attach(workspace path: String) {
        workspace = realpath(path, nil).map { pointer in
            defer { free(pointer) }
            return String(cString: pointer)
        } ?? path
        directory = nil
        excluded = []
        notBefore = nil
        forgetCurrent()
    }

    /// Hides everything written so far: a new session starts with an empty chat, even before
    /// Claude Code creates its transcript file.
    func startFresh() {
        if let current { excluded.insert(current.lastPathComponent) }
        notBefore = Date()
        forgetCurrent()
    }

    private func forgetCurrent() {
        current = nil
        offset = 0
        remainder = Data()
    }

    /// Claude Code's folder for a working directory: every other character becomes "-", and
    /// long names are cut at 200 characters and given a hash suffix.
    private func projectDirectory() -> URL? {
        if let directory { return directory }
        let fm = FileManager.default
        let projects = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
        let slug = String(String.UnicodeScalarView(workspace.unicodeScalars.map { scalar in
            scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) ? scalar : "-"
        }))
        var found: URL?
        let exact = projects.appendingPathComponent(slug, isDirectory: true)
        if fm.fileExists(atPath: exact.path) {
            found = exact
        } else if slug.count > 200, let names = try? fm.contentsOfDirectory(atPath: projects.path),
                  let match = names.first(where: { $0.hasPrefix(slug.prefix(200)) }) {
            found = projects.appendingPathComponent(match, isDirectory: true)
        }
        directory = found
        return found
    }

    func poll() -> Update? {
        guard let directory = projectDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
        else { return nil }

        var newest: (url: URL, date: Date, size: UInt64)?
        for url in files where url.pathExtension == "jsonl" && !excluded.contains(url.lastPathComponent) {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let date = values.contentModificationDate else { continue }
            if let notBefore, date < notBefore { continue }
            if newest == nil || date > newest!.date { newest = (url, date, UInt64(values.fileSize ?? 0)) }
        }
        guard let newest else { return nil }

        var update = Update(lastWrite: newest.date)
        if newest.url != current {
            forgetCurrent()
            current = newest.url
            update.reset = true
            if newest.size > Self.maxInitialRead { offset = newest.size - Self.maxInitialRead }
        }
        let skipFirstLine = update.reset && offset > 0
        guard newest.size > offset, let handle = try? FileHandle(forReadingFrom: newest.url) else {
            return update.reset ? update : nil
        }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd() else {
            return update.reset ? update : nil
        }
        offset += UInt64(data.count)
        remainder.append(data)

        // Only complete lines; the rest waits for the next poll.
        guard let lastNewline = remainder.lastIndex(of: 0x0A) else { return update }
        var lines = remainder[remainder.startIndex..<lastNewline].split(separator: 0x0A)
        remainder = Data(remainder[(lastNewline + 1)...])
        if skipFirstLine, !lines.isEmpty { lines.removeFirst() }
        for line in lines {
            let output = ChatTranscriptParser.parse(line: Data(line), workspace: workspace)
            update.entries += output.entries
            if let working = output.working { update.working = working }
        }
        return update
    }
}

/// The chat's state: the conversation read from the transcript, plus messages on their way.
@MainActor
final class AgentChatTranscript: ObservableObject {
    static let shared = AgentChatTranscript()

    struct PendingMessage: Identifiable {
        let id = UUID()
        let prompt: String
        let display: String
        let sentAt = Date()
    }

    @Published private(set) var entries: [ChatEntry] = []
    @Published private(set) var pending: [PendingMessage] = []
    @Published private(set) var agentWorking = false
    /// Claude Code is showing a prompt in the terminal that only the person can answer.
    @Published private(set) var needsTerminalAnswer = false
    /// Ticks while a message is pending, so its "still waiting" hint can appear.
    @Published private(set) var now = Date()

    private static let maxEntries = 500
    /// Nothing written for this long means the turn ended without a final record (e.g. a crash).
    private static let workingTimeout: TimeInterval = 300

    private let reader = ChatTranscriptReader()
    private let queue = DispatchQueue(label: "chat.transcript", qos: .utility)
    private var timer: Timer?
    private var polling = false
    private var lastWrite: Date?
    /// What the person actually typed, for prompts wrapped with instructions by the app.
    private var displayTexts: [String: String] = [:]
    /// Asks the terminal whether such a prompt is on screen (set by the panel model).
    var terminalNeedsAnswer: (@MainActor () -> Bool)?

    var isWorking: Bool { !pending.isEmpty || agentWorking }

    func attach(workspace: String) {
        entries = []
        pending = []
        agentWorking = false
        queue.async { [reader] in reader.attach(workspace: workspace) }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func startFresh() {
        entries = []
        pending = []
        agentWorking = false
        queue.async { [reader] in reader.startFresh() }
    }

    func addPending(prompt: String, display: String) {
        displayTexts[Self.normalized(prompt)] = display
        pending.append(PendingMessage(prompt: prompt, display: display))
    }

    /// The session ended before these were delivered; say so rather than losing them quietly.
    func dropPending() {
        entries += pending.map { ChatEntry(id: $0.id.uuidString, kind: .note("Not sent: \($0.display)")) }
        pending = []
        agentWorking = false
    }

    private func poll() {
        if !pending.isEmpty { now = Date() }
        let needsAnswer = terminalNeedsAnswer?() ?? false
        if needsAnswer != needsTerminalAnswer { needsTerminalAnswer = needsAnswer }
        if agentWorking, let lastWrite, Date().timeIntervalSince(lastWrite) > Self.workingTimeout {
            agentWorking = false
        }
        guard !polling else { return }
        polling = true
        queue.async { [weak self, reader] in
            let update = reader.poll()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.polling = false
                    if let update { self?.apply(update) }
                }
            }
        }
    }

    private func apply(_ update: ChatTranscriptReader.Update) {
        lastWrite = update.lastWrite
        if update.reset { entries = [] }
        if let working = update.working { agentWorking = working }
        guard !update.entries.isEmpty else { return }
        let incoming = update.entries.map { entry -> ChatEntry in
            guard case .user(let text) = entry.kind else { return entry }
            confirmPending(text, isLive: !update.reset)
            return ChatEntry(id: entry.id, kind: .user(displayText(for: text)))
        }
        // Records are re-read after a transcript is resumed, so keep ids unique.
        let known = Set(entries.map(\.id))
        entries = Array((entries + incoming.filter { !known.contains($0.id) }).suffix(Self.maxEntries))
    }

    /// A user record arrived: the matching message is no longer pending. A loaded history
    /// must match exactly; a record arriving live also settles the oldest message.
    private func confirmPending(_ text: String, isLive: Bool) {
        let key = Self.normalized(text)
        if let index = pending.firstIndex(where: { Self.normalized($0.prompt) == key }) {
            pending.remove(at: index)
        } else if isLive, !pending.isEmpty {
            pending.removeFirst()
        }
    }

    private func displayText(for text: String) -> String {
        if let display = displayTexts[Self.normalized(text)] { return display }
        // From an earlier run of the app: drop the context prefix the app added.
        guard let range = text.range(of: #"^\[(Topic|Context)[^\]]*\]\s*"#, options: .regularExpression) else {
            return text
        }
        return String(text[range.upperBound...])
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// The chat pane: conversation, quick actions and the message box.
struct AgentChatPane: View {
    @Binding var isVisible: Bool
    var context: WikiContext?

    @ObservedObject private var model = AgentPanelModel.shared
    @ObservedObject private var chat = AgentChatTranscript.shared
    /// A one-shot wiki action for the next message; nil sends a plain chat message.
    @State private var action: WikiAction?
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    private static let examples = ["Add a new topic “Galois Theory”",
                                   "Outline this topic as a learning wiki",
                                   "What's in this library so far?"]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            conversation
            if chat.needsTerminalAnswer { terminalQuestionBanner }
            Divider()
            composer
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { inputFocused = true }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
            Text("Chat").font(.subheadline.weight(.semibold))
            Text("powered by Claude Code")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button { model.newSession(.claude) } label: {
                Image(systemName: "square.and.pencil").font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help("New chat")
            Button { model.showHistory(.claude) } label: {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help("Earlier chats (opens the picker in the terminal below)")
            Button {
                withAnimation { isVisible = false }
            } label: {
                Image(systemName: "sidebar.trailing").font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("Hide the agent panel (⌥⌘T)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .help("Talk to Claude Code here. It runs in the terminal below, where you can watch it work.")
    }

    /// Startup prompts (like the folder trust check) are answered in the terminal, not here.
    private var terminalQuestionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(Theme.highlight)
            Text("Claude Code needs your answer in the terminal below.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Go to Terminal") { model.select(.claude) }
                .controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.highlight.opacity(0.14))
    }

    // MARK: - Conversation

    /// Entries with consecutive tool calls folded into one row.
    private var rows: [ChatRow] {
        var rows: [ChatRow] = []
        for entry in chat.entries {
            if case .tool(let tool) = entry.kind {
                if case .tools(let id, let tools)? = rows.last {
                    rows[rows.count - 1] = .tools(id: id, tools + [tool])
                } else {
                    rows.append(.tools(id: entry.id, [tool]))
                }
            } else {
                rows.append(.entry(entry))
            }
        }
        return rows
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if chat.entries.isEmpty && chat.pending.isEmpty { emptyState }
                    ForEach(rows) { row in
                        switch row {
                        case .entry(let entry): ChatEntryRow(entry: entry)
                        case .tools(_, let tools): ChatToolsRow(tools: tools)
                        }
                    }
                    ForEach(chat.pending) { message in pendingRow(message) }
                    if chat.isWorking && !chat.needsTerminalAnswer { workingRow }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(12)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: chat.entries.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: chat.pending.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What would you like to build?").font(.headline)
            Text("Claude Code creates and updates your topics and pages. New topics appear in the sidebar, and you can watch the work in the terminal below.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Self.examples, id: \.self) { example in
                Button {
                    input = example
                    inputFocused = true
                } label: {
                    Text(example)
                        .font(.callout)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Capsule().fill(Theme.accent.opacity(0.1)))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pendingRow(_ message: AgentChatTranscript.PendingMessage) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            ChatBubble(text: message.display).opacity(0.65)
            Text(chat.needsTerminalAnswer ? "Will send once you've answered."
                 : chat.now.timeIntervalSince(message.sentAt) > 20 ? "Still waiting. Check the terminal below."
                 : "Sending…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var workingRow: some View {
        HStack(spacing: 7) {
            ProgressView().controlSize(.small)
            Text("Working… follow along in the terminal below")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if chat.agentWorking {
                Button("Stop") { model.interrupt() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Interrupt Claude Code (sends Esc)")
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(WikiAction.allCases) { item in
                        Button { action = action == item ? nil : item } label: {
                            Label(item.title, systemImage: item.symbol)
                                .labelStyle(.titleAndIcon)
                                .font(.caption.weight(action == item ? .semibold : .regular))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(action == item ? Theme.accent.opacity(0.16) : Color.clear))
                                .foregroundStyle(action == item ? Theme.accent : .secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(context == nil)
                        .help(context == nil ? "Select a topic in the sidebar to use \(item.title)" : item.title)
                    }
                }
            }
            HStack(spacing: 6) {
                TextField(action?.placeholder ?? "Message Claude Code…", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .onSubmit(submit)
                    .disabled(model.workspace == nil)
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSubmit ? Theme.accent : Color.secondary.opacity(0.5))
                .disabled(!canSubmit)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Send to Claude Code (⌘↩)")
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
            if let context {
                Text("Viewing: \(context.page ?? context.folder)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(10)
    }

    private var trimmedInput: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSubmit: Bool {
        guard model.workspace != nil else { return false }
        if let action { return context != nil && (!action.needsInput || !trimmedInput.isEmpty) }
        return !trimmedInput.isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        let text = trimmedInput
        let line = text.replacingOccurrences(of: "\n", with: " ")
        if let action, let context {
            model.send(action.prompt(input: line, context: context),
                       display: text.isEmpty ? action.title : "\(action.title): \(text)")
        } else if text == "/clear" {
            model.newSession(.claude)
        } else if text.hasPrefix("/") {
            model.send(line)
        } else {
            model.send(WikiContext.chatPrompt(line, context: context), display: text)
        }
        input = ""
        action = nil
        inputFocused = true
    }
}

private enum ChatRow: Identifiable {
    case entry(ChatEntry)
    case tools(id: String, [ChatTool])

    var id: String {
        switch self {
        case .entry(let entry): return entry.id
        case .tools(let id, _): return id
        }
    }
}

private struct ChatEntryRow: View {
    let entry: ChatEntry

    var body: some View {
        switch entry.kind {
        case .user(let text):
            ChatBubble(text: text).frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant(let text):
            MarkdownPreview(markdown: text, resolveImage: { _ in nil }, compact: true)
        case .note(let text):
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        case .tool:
            EmptyView()
        }
    }
}

private struct ChatBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .textSelection(.enabled)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent.opacity(0.14)))
            .padding(.leading, 28)
    }
}

/// A run of tool calls: one line showing the latest step, expanding to all of them.
private struct ChatToolsRow: View {
    let tools: [ChatTool]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if tools.count > 1 {
                Button { withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                        Text("\(tools.count) steps").font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if expanded {
                ForEach(tools.indices, id: \.self) { row(tools[$0]) }
            } else if let last = tools.last {
                row(last)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ tool: ChatTool) -> some View {
        let line = HStack(spacing: 6) {
            Image(systemName: tool.symbol).font(.system(size: 10)).frame(width: 13)
            Text(tool.label).font(.caption).lineLimit(1).truncationMode(.middle)
        }
        if let url = tool.url {
            Button { AgentPanelModel.shared.openLocal?(url) } label: {
                line.foregroundStyle(Theme.accent).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open \(url.lastPathComponent)")
        } else {
            line.foregroundStyle(.secondary)
        }
    }
}
#endif
