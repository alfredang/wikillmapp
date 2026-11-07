#if os(macOS)
import SwiftUI

/// A subagent defined by a Markdown file in the library's `.claude/agents` folder: YAML
/// frontmatter (name, description, model, effort, tools, skills) followed by its instructions.
struct AgentDefinition: Identifiable, Equatable {
    var id: URL { url }
    let url: URL
    var name: String
    var description = ""
    var model = ""
    var effort = ""
    var tools: [String] = []
    var skills: [String] = []
    var instructions = ""

    static let folder = ".claude/agents"

    /// Every agent the library uses: the lead session, then its subagents, strongest model first
    /// and then by name.
    static func load(from root: URL) -> [AgentDefinition] {
        let dir = root.appendingPathComponent(folder)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let team = files
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap { url in
                (try? String(contentsOf: url, encoding: .utf8)).map { parse($0, url: url) }
            }
            .sorted { ($0.modelRank, $0.name) < ($1.modelRank, $1.name) }
        return [lead(root: root)] + team
    }

    /// The agent panel's Claude Code session, which leads the team. It has no agent file: it runs
    /// with the flags in `AgentKind.arguments` and follows the library's `CLAUDE.md`.
    private static func lead(root: URL) -> AgentDefinition {
        let schema = root.appendingPathComponent(TopicLibrary.schemaFile)
        var agent = AgentDefinition(url: schema, name: "Lead (main session)")
        agent.description = "The Claude Code session in the agent panel and the team lead. It talks to you, writes original prose and runs the other agents as an agent team: each one is a teammate you can watch and message from the list under the prompt (↑/↓, Enter), and the teammates message each other."
        agent.model = "opus 5.5"
        agent.effort = "high"
        agent.tools = ["All available to Claude Code"]
        agent.skills = ["All available to Claude Code"]
        agent.instructions = (try? String(contentsOf: schema, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return agent
    }

    /// Reads the simple frontmatter agents use: `key: value`, with lists written either on one
    /// line separated by commas or as `- item` lines under the key.
    static func parse(_ text: String, url: URL) -> AgentDefinition {
        var agent = AgentDefinition(url: url, name: url.deletingPathExtension().lastPathComponent)
        let lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else {
            agent.instructions = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return agent
        }

        var fields: [String: String] = [:]
        var lists: [String: [String]] = [:]
        var currentKey: String?
        for line in lines[1..<end] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- "), let key = currentKey {
                lists[key, default: []].append(unquote(String(trimmed.dropFirst(2))))
            } else if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                fields[key] = unquote(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
                currentKey = key
            }
        }

        func list(_ key: String) -> [String] {
            lists[key] ?? (fields[key] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        if let name = fields["name"], !name.isEmpty { agent.name = name }
        agent.description = fields["description"] ?? ""
        agent.model = fields["model"] ?? ""
        agent.effort = fields["effort"] ?? ""
        agent.tools = list("tools")
        agent.skills = list("skills")
        agent.instructions = lines[(end + 1)...].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return agent
    }

    private static func unquote(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private var modelRank: Int {
        let model = model.lowercased()
        if model.contains("fable") { return 0 }
        if model.contains("opus") { return 1 }
        if model.contains("sonnet") { return 2 }
        if model.contains("haiku") { return 3 }
        return 4
    }

    /// "Opus · high effort"; the session's model when the agent doesn't set one.
    var modelLabel: String {
        let base = model.isEmpty ? "Session model" : model.prefix(1).uppercased() + model.dropFirst()
        return effort.isEmpty ? base : "\(base) · \(effort) effort"
    }

    /// The instructions for reading in a card. The files wrap prose at a fixed width, which would
    /// break mid-sentence here, so wrapped lines rejoin; headings, lists, tables and code stay put.
    var readableInstructions: String {
        var output: [String] = []
        var inCode = false
        var canContinue = false
        for line in instructions.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCode.toggle()
                output.append(line)
                canContinue = false
            } else if inCode {
                output.append(line)
            } else if trimmed.isEmpty {
                output.append("")
                canContinue = false
            } else if trimmed.hasPrefix("#") || trimmed.hasPrefix("|") {
                output.append(line)
                canContinue = false
            } else if trimmed.hasPrefix("- ") || trimmed.range(of: #"^\d+\. "#, options: .regularExpression) != nil {
                output.append(line)
                canContinue = true
            } else if canContinue, let last = output.last {
                output[output.count - 1] = last + " " + trimmed
            } else {
                output.append(line)
                canContinue = true
            }
        }
        return output.joined(separator: "\n")
    }

    /// "Opus", for the sidebar row.
    var shortModel: String {
        model.split(separator: " ").first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? ""
    }
}

/// The team on one page, or one agent when `selected` names it: each agent's name, description,
/// model, tools, skills and instructions.
struct AgentsView: View {
    let agents: [AgentDefinition]
    var selected: URL?

    private var selectedAgent: AgentDefinition? {
        agents.first { $0.url == selected }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let agent = selectedAgent {
                    AgentCard(agent: agent, showsInstructions: true).id(agent.id)
                } else {
                    Text("All Agents").font(.largeTitle.bold())
                    ForEach(agents) { AgentCard(agent: $0, showsInstructions: false) }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
    }
}

/// One agent's row in the sidebar's Agents section.
struct AgentSidebarRow: View {
    let agent: AgentDefinition

    var body: some View {
        HStack(spacing: 6) {
            Label(agent.name, systemImage: "person.crop.circle")
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(agent.shortModel)
                .font(.caption2)
                .foregroundStyle(Theme.mutedInk)
        }
    }
}

private struct AgentCard: View {
    let agent: AgentDefinition
    @State private var showInstructions: Bool

    init(agent: AgentDefinition, showsInstructions: Bool) {
        self.agent = agent
        _showInstructions = State(initialValue: showsInstructions)
    }

    private var usesOpus: Bool { agent.model.lowercased().contains("opus") }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(agent.name).font(.headline.monospaced()).textSelection(.enabled)
                Spacer(minLength: 8)
                Text(agent.modelLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(usesOpus ? Theme.primary : Theme.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((usesOpus ? Theme.primary : Theme.secondary).opacity(0.12), in: Capsule())
            }

            Text(agent.description)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            detailRow("Tools", agent.tools.isEmpty ? "All tools" : agent.tools.joined(separator: ", "))
            detailRow("Skills", agent.skills.isEmpty ? "None" : agent.skills.joined(separator: ", "))

            DisclosureGroup("Instructions", isExpanded: $showInstructions) {
                Text(agent.readableInstructions)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.top, 6)
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(Theme.mutedInk)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.mutedInk)
                .frame(width: 44, alignment: .leading)
            Text(value)
                .font(.callout)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
#endif
