# CLAUDE.md — Wiki LLM (Topics · HTML LLM Wiki)

Guidance for AI agents working on **this app's code** and on the **content inside a Topics
library** opened by the app. `AGENTS.md` is a mirror of this file.

> The app is a native SwiftUI knowledge-building app (macOS / iPadOS / iOS). Knowledge lives
> in a **Topics library** — a plain folder whose sub-folders are topics, each holding
> numbered sub-topic folders and **self-contained HTML pages** (like Claude artifacts). On
> macOS it uses the Planner app's layout: Topics sidebar · page view · **agent panel**
> (Claude Code in a real terminal) that writes and maintains the pages as an LLM wiki.

## Mission

Wiki LLM is the user's own **AI-for-science app**: a multi-agent system that generates new knowledge and
organizes knowledge. It is not an encyclopedia, and organizing knowledge is only the starting point. Its
purpose is to help the user think and create new work:

- **Organize their ideas** so rough thoughts become a connected body of work.
- **Realize their ideas** by converting them into real things: concrete plans, code, pages and
  results.
- **Generate new ideas** for them from connections, gaps and tensions across the library.
- **Inspire them** with unexpected angles, analogies and questions they haven't asked.
- **Challenge and critique them** by questioning and debating them, so they reach new insights.
- **Explore new ideas** by following them through variations, related work and objections.
- **Create new theory** by proposing hypotheses and theories of your own, with clear definitions,
  assumptions, claims, arguments and tests.
- **Generate publications** such as papers and articles from the work developed in the wiki.

**The user is a learned student and researcher who asks deep questions.** Never write elementary,
first-textbook content for them ("don't treat me like a primary school student"): go to structure,
reasons, obstructions, connections and open questions, lead with insight-revealing visuals, keep all
maths in LaTeX, and build pages around their own intuitions and questions. Turn each way of working
they ask for into a reusable library skill.

Three rules apply to all of this:

- **Challenge the user, then improve the idea.** If an idea is wrong or implausible, say so directly
  and explain why, even if they seem committed to it. Don't stop at the objection: repair the idea
  where you can, or suggest a better theory or testable hypothesis in its place. Unusual ideas
  deserve a real test, not automatic agreement or dismissal.
- **Don't copy Wikipedia or any other source.** Add background only where it serves the user's
  thinking or they ask to study a subject, and write it in your own words with sources cited. The
  value of a page is in the synthesis, the original angle and the open questions.
- **Be original and honest.** Keep established facts, the user's ideas and your own conjectures
  visibly separate. Never invent a reference, quotation, data or result, and don't claim something
  is new just because a search found nothing like it.

Use **Opus at high effort** by default. In a library, the main session is the lead of an
**agent team** (Claude Code agent teams; each agent is a teammate the user can watch and message):

- **Sonnet, medium effort:** `wiki-collector` gets content, `wiki-arxiv` searches arXiv papers,
  `wiki-organizer` organizes content, keywords and cross-links, and `wiki-reviewer` checks
  citations, numbers and labels.
- **Opus, high effort:** `wiki-researcher` does the research, `wiki-idea-partner` generates and extends
  ideas, `wiki-cross-domain` brings ideas from other disciplines, `wiki-critic` challenges, questions,
  critiques and debates the user, and `wiki-visualizer` makes pages visual, animated and interactive.

The team is active, not passive: each teammate has standing duties it does unasked, and every insight
the user offers is written into the page it belongs to with the team's verdict (sound / needs a fix /
goes further) and a "How to explain it" section, so the library becomes the user's own notes.

Judge new app features by the same mission. For content work, the operations that carry it out
(capture, develop, debate, spark, explore, theorize, cross, investigate, tournament, publish) are
defined in the library schema,
[Resources/LibraryTemplate/CLAUDE.md](Resources/LibraryTemplate/CLAUDE.md).

### Turning an idea into reality

The user brings ideas for this wiki, often still rough, whether for the app or for a topic's
content. Don't just record an idea or build it exactly as first stated. Act as a thinking
partner and strengthen it until it can be built:

1. **Sharpen it.** Restate the idea in a sentence or two: what problem it solves and for whom.
2. **Test it.** Name the gaps, weak assumptions and edge cases, and say plainly if part of it
   won't work. Suggest a stronger version and recommend one direction rather than listing
   options.
3. **Make it concrete.** Define the smallest useful first version, what is out of scope and how
   to tell it works. Tie it to the real project: the files and views it touches for an app idea,
   the topic, subtopics and pages for a content idea.
4. **Realize it.** Once the user agrees with the direction, build it: write the code or the
   pages, following the rules in this file. If they ask to go straight to building, do so and
   state any assumptions you made.

## How content works (what you edit)

- Default library: `~/Documents/Tertiary Topics/` (iOS: app Documents). Any folder can be
  opened as a library (⌘O); the app seeds `CLAUDE.md`, `_template.html` and the offline page
  libraries in `_assets/` (KaTeX, D3, Observable Plot, JSXGraph, Mermaid, Matter.js, highlight.js)
  into it where missing, and on macOS the agents from `Resources/LibraryTemplate/agents/` and
  skills from `skills/` into `.claude/`: `deep-insight` (the level), `insight-pages` (page shape and
  insight test), `latex-math`, `rich-visuals` (+ `recipes.html`, `serve.sh`), `discussion`,
  `wiki-graph` (`wiki_index.py` search / related / report) and `new-page` (`new_page.py` scaffold).
  Seeding never overwrites, so update an existing library's copies by hand.
- The library's own `CLAUDE.md` (bundled from `Resources/LibraryTemplate/CLAUDE.md`) is the
  schema agents follow: mission, layout, page rules, operations (ingest / generate / ask / lint
  and capture / develop / debate / spark / explore / theorize / cross / investigate / tournament /
  publish), the person's-notes rules, the agent team, `log.md` format.
- Layout per topic: `index.html` (topic home) · `log.md` (append-only) · `raw/` (immutable
  sources) · `NN Subtopic/` folders, each with `index.html` + kebab-case `.html` pages.
- Pages copy the `<style>` of `_template.html`, work offline (no CDNs; shared libraries come
  from `_assets/` by relative path), link relatively (spaces as `%20`) and carry breadcrumbs
  back to each folder's `index.html`.
- In the sidebar a folder row stands for its `index.html`; `index.html` files are not listed.
- Sidebar pages show their `<title>` minus trailing " · …" segments that repeat a parent
  folder or topic (`VaultStore.sidebarLabel`), and sort by that label in natural order. Put a
  number first in the title ("Scenario 1 · …") to order pages.
- **Cross-links are Obsidian-style**: relative `<a href>` links and `[[page]]` /
  `[[Page Title|label]]` wikilinks (resolved by file name, title or folder name) both count.
  The app builds a `LinkIndex` (`WikiLinks.swift`) for backlinks, hover previews and
  orphan detection. Pages need no "Backlinks" section. The sidebar's **Graph** (Library section,
  `GraphView.swift`) draws the whole index as an Obsidian-style 3D graph with `3d-force-graph`
  (MIT, bundles three.js) from `Resources/Graph/`.
- **Tags** are `<meta name="tags" content="a, b">` in a page's `<head>` (`PageTags.swift`); a
  topic or subtopic is tagged through its `index.html`. `raw/` sources and `_template.html`
  have none. `LinkIndex` collects them and `PageTagBar` edits them above each page.
- **Keywords** are `<meta name="keywords" content="…">`: a page's concepts, synonyms, symbols
  and other names, so plain text search finds it by any of them (there is no vector index).
- **Search** (`TagFilterBar`, above the sidebar): plain words match titles, summaries, keywords,
  folders and tags; a word starting with `@` searches tags and shows matching tag chips (`@`
  alone lists every tag).
- **Discussion**: every page ends with a compact Discussion section (one line per question,
  newest first, older folded, never deleted), written only by the library's `discussion` skill
  script. On macOS the app writes the page on screen to `.claude/viewing.nosync` (iCloud skips
  `.nosync`), so the agent knows what "this page" is.
- **iCloud**: the default library sits in iCloud Drive when the Mac syncs Desktop & Documents.
  On iOS, open it from Files (iCloud Drive › Documents › Tertiary Topics); `VaultStore`
  asks iOS to download every page (`syncFromICloud`) and refreshes when the app comes back.
  Seeding treats an iCloud placeholder (`.name.icloud`) as present, so it never writes a
  default over a file still in iCloud.
- To create or update content, just **write the files**. The app watches the folder (FSEvents)
  and reloads the page on screen when it changes.

## Agent panel (macOS)

- **All agents run locally as native Claude Code agents in the terminal, on the user's own Claude
  login (OAuth, `claude auth login`).** Don't add the Claude Agent SDK or an API key: that was
  considered and declined. Agents are the Markdown files in the library's `.claude/agents/`.
- The Claude Code tab exports `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, so the lead runs the
  agents as an in-process agent team (no tmux needed). Teammates show under the prompt.
- Tabs: **Claude Code** (`claude --dangerously-skip-permissions --model claude-opus-5-5 --effort
  high`, resumes with `--continue`),
  **Codex**, **Terminal** — all started in the library root so `CLAUDE.md` applies.
- Sidebar context menus offer Outline / Lint / Ingest on folders (`WikiAction`). Each types a
  single-line instruction scoped to that folder into Claude Code, waiting until it is ready and
  never while a startup prompt such as the folder trust check is on screen.

## The `mdwiki` CLI (`Tools/mdwiki`)

Legacy helper for Markdown wikis (pre-HTML). Not used by the Topics library.

---

# Building the app (for code changes)

- Project is generated by **XcodeGen** from `project.yml`. After editing `project.yml` or adding
  files under `Sources/`, run `xcodegen generate`.
- Build: `xcodebuild -project MarkdownVault.xcodeproj -scheme MarkdownVault -destination 'platform=macOS' -configuration Debug build`
- **Sandbox is OFF** (`com.apple.security.app-sandbox: false`) so embedded terminals can spawn a
  real login shell. This build is **not App Store eligible** — keep it for personal/dev use.
- Dependency: **SwiftTerm** pinned to 1.11.2 in `project.yml` (1.13 needs the Metal toolchain).

## macOS UI architecture (`#if os(macOS)`)

- `RootView` → `TopicsRootView` (macOS) or a `TabView` with `VaultView` (iOS).
- `TopicsRootView`: `NavigationSplitView` — sidebar (`TopicTreeRow` tree of topics/subtopics/
  pages, Agents: All Agents + each agent, Library: Agent Schema / Page Template, Support: Settings /
  Feedback / About) and a
  detail area = `TopicDetailView` + draggable divider (`PanelResizeHandle`) + `AgentPanel`.
- **Maths is LaTeX** (`\( … \)`, `\[ … \]`). `HTMLPageView` typesets it with the library's
  `_assets/katex` after load on any page that doesn't load KaTeX itself (`renderMath`), and adds
  click-to-zoom (`_assets/zoom/zoom.js`, read from the app bundle) to every page.
- `TopicDetailView`: folder → its `index.html` (or `FolderOverview` cards); HTML page →
  `HTMLPageView` (WKWebView) in Preview / Split / Source (`HTMLSourceEditor`); `.md` →
  `MarkdownEditorView`. `LibraryHomeView` when nothing is selected. `LocalFileGate` fetches a
  page macOS has evicted to iCloud before showing it, because WebKit stays white until the download ends.
- `VaultStore` owns the library folder (bookmark key `library.bookmark`), file tree, live
  FSEvents refresh, and topic/subtopic/page CRUD; `TopicLibrary` holds layout constants,
  seeding and the HTML generators.
- `WikiLinks.swift`: `LinkIndex` (built off-main on every refresh → `VaultStore.links`) and
  the page script `HTMLPageView` runs after load. It resolves `[[…]]`, styles internal and
  external links, and shows hover previews. `LinksBar` (in `TopicDetailView`) lists backlinks
  and outgoing links.
- `AgentPanel.swift`: `AgentPanelModel` (shared; sessions survive panel hide), `AgentPanel`
  view, `AgentTerminalSession` / `AgentTerminalView` (SwiftTerm, ported from Planner).
- `AgentsView.swift`: the sidebar's Agents section and its pages. `AgentDefinition` parses each
  `.claude/agents/*.md` file (frontmatter + instructions) and adds the lead session; the pages show
  every agent's model, tools, skills and instructions.
- `GraphView.swift`: `LibraryGraphView` turns `LinkIndex` into graph JSON and hosts
  `Resources/Graph/graph.html` in a WKWebView; the page posts `open` messages back.
- Debug: launch with `-debugSelect "<path relative to the library>"` to open a page,
  `-debugPane agents` (or `graph`) to open a pane, `-debugAgent wiki-critic` to open one agent, and
  `-debugLibrary "<path>"` to open a throwaway library without touching the saved one.

## Conventions

- Use the brand palette in `Theme.swift` (`Theme.*`); avoid raw color literals.
- Appearance is a user setting (`AppAppearance`, key `appearance.theme`): **Light (default)**,
  Dark or System. macOS applies it with `NSApp.appearance`, iOS with `.preferredColorScheme`.
  Pages follow it through `prefers-color-scheme`. The agent terminal stays dark.
- Keep iOS working: macOS-only files/sections are wrapped in `#if os(macOS)`.
- Don't read library files on the main thread in new code: the library can sit in iCloud Drive, where
  a read can stall and freeze the app.
