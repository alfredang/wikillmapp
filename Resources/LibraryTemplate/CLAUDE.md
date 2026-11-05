# Topics Library — LLM Wiki Schema (HTML)

You are the maintainer of a **knowledge library**. Every topic is a folder of
self-contained **HTML pages** (like Claude artifacts), which the Wiki LLM app shows
in its Topics sidebar and renders live. You write and keep the pages current; the person
curates the sources and asks the questions. This follows the "LLM Wiki" pattern: knowledge is
compiled once into a persistent, interlinked wiki instead of being re-derived on every query.

## Layout

```
<library>/                       ← this folder (the agent's working directory)
  CLAUDE.md                      ← this schema
  _template.html                 ← the page template — copy it for every new page
  <Topic>/                       ← one folder per topic, human-readable name
    index.html                   ← topic home: overview + map of every subtopic and page
    log.md                       ← append-only operations log (Markdown)
    raw/                         ← immutable sources (PDF, notes, URLs.txt…). Never edit.
    <NN Subtopic>/               ← sub-topic folder, numbered for order: "01 Agentic Architecture"
      index.html                 ← sub-topic overview + links to its pages
      <page-name>.html           ← one concept per page, kebab-case file name
      <NN Deeper Subtopic>/      ← nest further when a subtopic grows past ~8 pages
```

## Page rules

1. **Start from `_template.html`.** Keep its `<style>` block intact so every page looks the
   same; fill the `<title>`, `<meta name="description">`, breadcrumb, header and body.
   The sidebar lists a page by its `<title>` (end it with " · <Topic>"; that suffix is hidden)
   and sorts pages by it, so start titles with a number when order matters
   ("Scenario 1 · Customer Support", "Step 2 · …").
2. **Self-contained.** Inline CSS/JS only. No external scripts, fonts or CDNs — pages must
   render offline. Inline SVG is welcome for diagrams.
3. **Link relatively.** `href="../01 Agentic Architecture/agent-loop.html"` — encode spaces as
   `%20` (`../01%20Agentic%20Architecture/agent-loop.html`). Every page links back up to its
   folder's `index.html` (breadcrumb) and to 2–5 related pages ("Related" section).
4. **One concept per page.** Prefer many focused pages over one long page.
5. **Cite sources.** Facts that came from `raw/` or the web get a "Sources" list at the end
   with the file name or URL and the date checked. Say "unverified" when you are not sure.
6. **Cross-link densely, Obsidian style.** Whenever a page mentions a concept that has its
   own page, link it. Two forms work:
   - `<a href="../02%20Tool%20Design/tool-descriptions.html">tool descriptions</a>`, the
     portable form, which also works when the page is opened in a browser.
   - `[[tool-descriptions]]`, `[[Tool Descriptions|how tools are described]]` or
     `[[agentic-loop#termination]]`: wikilinks, which resolve by file name, page title or
     folder name (for a folder's `index.html`). The app turns them into links with hover
     previews; in a plain browser they show as text. Use them freely in prose; keep
     breadcrumbs and "Related" lists as real `<a href>` links.
   Don't write "Backlinks" sections. The app computes linked mentions for every page.
7. **Interactive is fine.** Quizzes, flashcards, tabs, toggles — use `<details>` or small
   inline `<script>`; keep them working without network access.
8. **Tags go in the `<head>`.** `<meta name="tags" content="agents, exam-prep">`: comma-separated,
   lowercase, hyphens instead of spaces. Tag a topic or subtopic through its folder's
   `index.html`. The app's sidebar searches them and the person edits them there too, so
   **keep the existing tags whenever you rewrite a page**, and reuse tags already in the
   library rather than inventing near-duplicates.

## Operations

- **New topic** — the person asks for a topic: create `<Topic>/` at the library root, whatever
  page they happen to be viewing, with `index.html` (from the template), `log.md` and `raw/`.
  The folder appears in the app's sidebar by itself.
- **Ingest** — read a new file in `<Topic>/raw/`, then create or update the affected pages,
  update every `index.html` it touches, and append to `log.md`.
- **Generate** — the person asks for a page or subtopic: research, write it from the template,
  link it into the parent `index.html`, append to `log.md`.
- **Ask** — answer from the wiki pages first (cite them by path); if the answer is worth
  keeping, file it as a new page.
- **Lint** — find broken relative links and unresolved `[[wikilinks]]`, orphan pages (no
  page links to them), stale facts, contradictions and missing cross-links (a concept
  mentioned in prose without a link to its page); fix them and log what changed.

## `log.md` format

Append only, never rewrite:

```
## [YYYY-MM-DD] ingest | raw/exam-guide.pdf → updated 4 pages in 01 Agentic Architecture
```

## Conventions

- Folder names: `NN Title Case` for ordered subtopics; topic folders use the plain title.
- File names: lowercase kebab-case, `.html`.
- `index.html` in every folder is the folder's overview page — the app opens it when the
  folder is selected.
- Don't create files outside the topic you were asked to work on unless told to.
