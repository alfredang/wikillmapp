# Wiki LLM

A **native knowledge-building app for Mac, iPad and iPhone**. Knowledge lives in a **Topics
library**: a plain folder whose sub-folders are topics, each holding numbered subtopics and
self-contained **HTML pages**. On the Mac, **Claude Code** runs in a built-in terminal and writes
and maintains those pages as an
[LLM wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).

[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20iPadOS%20%7C%20iOS-blue)](https://developer.apple.com)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)](https://swift.org)
[![UI](https://img.shields.io/badge/UI-SwiftUI-0A84FF?logo=swift)](https://developer.apple.com/xcode/swiftui/)
[![Terminal](https://img.shields.io/badge/Terminal-SwiftTerm-2ea44f)](https://github.com/migueldeicaza/SwiftTerm)
[![Xcode](https://img.shields.io/badge/Xcode-26-1575F9?logo=xcode)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/license-MIT-green)](#license)

<a href="https://apps.apple.com/us/app/tertiary-markdown/id6782659815"><img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download Wiki LLM on the App Store" height="44"></a>

> 📲 **Now on the App Store** — [**Download Wiki LLM**](https://apps.apple.com/us/app/tertiary-markdown/id6782659815) for Mac, iPad, and iPhone.

## Features

- 📚 **Topics library** — any folder can be a library. Topics, subtopics and pages are ordinary
  folders and `.html` files on disk, so nothing is locked into a proprietary store.
- 🌐 **Self-contained HTML pages** — pages copy one template, render offline and update on screen
  as soon as the file changes.
- 🔗 **Obsidian-style links** — relative links and `[[wikilinks]]`, with hover previews, backlinks
  and outgoing links computed by the app.
- 🏷 **Tags** — stored in each page's own `<meta name="tags">`, so they stay with the files.
- 📝 **Markdown too** — `.md` files open in an Edit · Split · Preview editor with images, tables
  and interactive checklists.
- 🎨 **Light, Dark or System** appearance, which pages follow.
- 🍏 **One codebase, three platforms** — SwiftUI multiplatform.

### 🖥 Mac: the agent panel

The right-hand panel holds the terminals: Claude Code, Codex and a plain shell, each in a real pty
([SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)) started in the library folder, so Claude
Code follows the library's `CLAUDE.md`. Ask it in plain language, for example *Add a new topic
"Galois Theory"*, and the new topic appears in the sidebar. Sidebar menus offer one-click Outline,
Lint and Ingest, which type the instruction into Claude Code.

> ⚠️ Claude Code runs with `--dangerously-skip-permissions`, in the library folder, so it can
> change files there without asking. Keep your library backed up.

## Screenshots

iPhone and iPad:

| iPhone — Page | iPhone — Dark | iPad — Page |
| --- | --- | --- |
| ![A wiki page on iPhone](screenshots/iphone-page.png) | ![A wiki page in dark appearance](screenshots/iphone-dark.png) | ![A wiki page on iPad](screenshots/ipad-page.png) |

## Tech Stack

| Area | Choice |
| --- | --- |
| Language | Swift 5 |
| UI | SwiftUI (multiplatform: iOS 17+ / macOS 14+) |
| Pages | `WKWebView` with a page script for wikilinks and hover previews |
| Markdown | Custom dependency-free block parser with native SwiftUI rendering |
| Terminal | [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 1.11.2 (macOS) |
| Agents | [Claude Code](https://claude.com/claude-code) and Codex CLIs, installed separately |
| Project gen | [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`) |

## Architecture

```
Sources/
├─ MarkdownVaultApp.swift   # @main App + macOS menu commands
├─ RootView.swift           # macOS: TopicsRootView · iOS: TabView
├─ TopicsRootView.swift     # macOS: sidebar · page · agent panel
├─ TopicDetailView.swift    # Folder overview, page view (Preview / Split / Source), links bar
├─ AgentPanel.swift         # Agent tabs and terminal sessions
├─ HTMLPageView.swift       # WKWebView page rendering
├─ HTMLSourceEditor.swift   # HTML source editing
├─ WikiLinks.swift          # LinkIndex: backlinks, wikilinks, hover previews
├─ PageTags.swift           # Reads and writes tags in a page's <meta>
├─ TagViews.swift           # Tag chips and layout
├─ TopicLibrary.swift       # Library layout, seeding and HTML generators
├─ VaultStore.swift         # Open library, file tree, live refresh, CRUD
├─ FileNode.swift           # File/folder tree model
├─ VaultView.swift          # iOS library browser
├─ MarkdownEditorView.swift # Edit · Split · Preview for .md files
├─ MarkdownParser.swift     # GFM-ish block parser
├─ MarkdownPreview.swift    # Native Markdown rendering
├─ Platform.swift           # Platform helpers
├─ Theme.swift              # Brand palette and appearance setting
├─ FeedbackView.swift       # Feedback form
├─ AboutView.swift          # App and developer info
└─ SettingsView.swift       # Library and display preferences
Resources/LibraryTemplate/  # CLAUDE.md schema + _template.html seeded into new libraries
Tools/mdwiki                # Legacy helper for Markdown wikis, not used by Topics libraries
```

## Getting Started

Requirements: **macOS 14+**, **Xcode 26+** and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The agent panel also needs the
[Claude Code](https://claude.com/claude-code) CLI on your `PATH`.

```bash
git clone https://github.com/alfredang/wikillmapp.git
cd wikillmapp
xcodegen generate            # creates MarkdownVault.xcodeproj from project.yml
open MarkdownVault.xcodeproj # build & run for My Mac, an iPad or an iPhone
```

Or from the command line:

```bash
# macOS
xcodebuild -project MarkdownVault.xcodeproj -scheme MarkdownVault -destination 'platform=macOS' build
# iOS Simulator
xcodebuild -project MarkdownVault.xcodeproj -scheme MarkdownVault -destination 'generic/platform=iOS Simulator' build
```

On first launch the app creates a library at `~/Documents/Tertiary Topics` (app Documents on iOS).
Use ⌘O to open any other folder as a library.

> The Mac build in this repo runs **without the App Sandbox** so its terminals can start a real
> login shell. That makes this build **not App Store eligible**; keep it for personal and
> development use.

## How a library is laid out

```
<library>/
├─ CLAUDE.md          # Schema the agent follows
├─ _template.html     # Template every page starts from
└─ <Topic>/
   ├─ index.html      # Topic home
   ├─ log.md          # Append-only operations log
   ├─ raw/            # Immutable sources
   └─ 01 Subtopic/
      ├─ index.html
      └─ some-page.html
```

## Developer

**Tertiary Infotech Academy Pte Ltd** — [tertiaryinfotech.com](https://www.tertiaryinfotech.com)

## License

MIT
