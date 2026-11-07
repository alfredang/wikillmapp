---
name: new-page
description: Create a new topic, subtopic or page in this library correctly from the start — template, breadcrumbs, _assets paths, KaTeX, tags, keywords, the insight-pages outline — then fill, link and check it. Use whenever the person asks for a new topic or page, or content needs a new page.
---

# Creating a topic or page

1. **Search first** (`wiki-graph`): `python3 .claude/skills/wiki-graph/wiki_index.py search …`. If a page
   already covers it, deepen that page instead.
2. **Set the level** (`deep-insight`): what is the deep question? What will a mature reader learn?
3. **Scaffold** with the script, so paths, includes and metadata are right:

   ```bash
   # a new topic (folder, index.html with a Mermaid map, log.md, raw/)
   python3 .claude/skills/new-page/new_page.py --topic "Lie Groups" --tags "math" \
     --description "…" --keywords "lie group, lie algebra, exponential map, …"
   # a subtopic: create the folder "NN Name/" and scaffold its index.html the same way as a page
   # a page
   python3 .claude/skills/new-page/new_page.py "Lie Groups/01 Matrix Groups/exponential-map.html" \
     --title "The Exponential Map" --description "…" --keywords "…" --libs d3,jsxgraph
   ```

   Libraries: `d3`, `plot`, `jsxgraph`, `mermaid`, `matter`, `highlight` (KaTeX is always included).
   Topic `index.html` tags decide the sidebar section: `math`, `physics`, `certification`.
4. **Write it** following `insight-pages` (shape, intuition handling, insight test), with all maths
   and numbers in LaTeX (`latex-math`) and a visual that reveals something (`rich-visuals`). Write
   the skeleton first so the person sees the page appear, then fill it.
5. **Connect it** (`wiki-graph`): add it to its folder's `index.html` map, link it both ways with
   related pages (`related`), across topics where real.
6. **Check**: `check_math.js`, `wiki_index.py report "<Topic>"`, render it via `serve.sh` + Playwright,
   then append a line to the topic's `log.md`.
