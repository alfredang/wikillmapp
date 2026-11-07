---
name: wiki-graph
description: How to keep the library a connected, searchable graph like Obsidian — cross-links (both directions, across topics), tags, keywords and descriptions — and how to search it fast as plain text with no vector index. Use when creating, moving or renaming any page, when filing new content, when looking for where something belongs or what it relates to, and when asked to lint, link or tag the library.
---

# The library as a graph, and smart tagging for search

The app draws every page as a node and every link as an edge (sidebar › Graph), shows backlinks
under each page, and searches titles, descriptions, keywords, folders and tags (`@tag` for tags).
There is no vector index: a page is found only by words it carries, and understood only through its
links. So links and metadata are part of every page, not an afterthought.

## Find before you write

Search the library before creating or answering, so new content joins the graph instead of
duplicating it:

```bash
python3 .claude/skills/wiki-graph/wiki_index.py search trace character     # ranked by title, keywords, tags…
python3 .claude/skills/wiki-graph/wiki_index.py search @physics spin        # @tag narrows to a tag
python3 .claude/skills/wiki-graph/wiki_index.py related "Topic/01 Sub/page.html"   # what to link to
```

## Links

- **Both directions.** When page A should mention B, link A → B in the prose *and* add A to B's
  Related list (or link it from B's prose). `related` lists pages that link in but aren't linked back.
- **Across topics.** The most valuable links bridge topics (a group-theory idea inside quantum
  mechanics, a Claude API concept in both certifications). Look for them every time.
- **Form.** In prose, `[[file-name|natural words]]` keeps the wording unchanged; breadcrumbs and
  Related lists use real relative `<a href>` links with spaces as `%20`. A wikilink resolves by file
  name, title or folder name, so don't reuse a file name that already exists elsewhere.
- **Density.** Link the first mention of every concept that has its own page, once per section.
  No "Backlinks" sections: the app computes them.
- **Moves and deletions.** Repoint every inbound link before moving, renaming or deleting a page.

## Smart metadata (in the `<head>`)

- `<meta name="description">`: one sentence saying the page's insight, in plain words.
- `<meta name="keywords">`: 6–15 comma-separated search terms: the concepts, synonyms and other
  names, symbols spelled out ("chi, character"), notation, people and results, and the question the
  page answers. This is how text search finds a page by any of its names.
- `<meta name="tags">`: a few shared categories reused across the library (`idea`, `theory`,
  `publication`, subject tags). A topic's `index.html` tags file it under a sidebar section:
  `certification` (or `exams`), `math`, `physics`. Keep existing tags whenever you rewrite a page.

## Check the graph

```bash
python3 .claude/skills/wiki-graph/wiki_index.py report            # whole library
python3 .claude/skills/wiki-graph/wiki_index.py report "Galois Theory"
```

It lists orphans, broken links, unresolved wikilinks, pages missing keywords or descriptions, index
pages without tags, weakly linked pages and duplicate titles. Fix what you introduced before
finishing; report the rest.
