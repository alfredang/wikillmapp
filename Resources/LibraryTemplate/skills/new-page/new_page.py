#!/usr/bin/env python3
"""Create a library page (or a whole topic) from _template.html, already wired correctly:
breadcrumbs, the right ../ prefix for _assets, KaTeX and any chosen libraries, tags, keywords,
description, and the section outline of the insight-pages skill. Run from the library root:

  python3 .claude/skills/new-page/new_page.py "Topic/01 Sub/page-name.html" --title "Page Title" \
      --description "One sentence: the page's insight." --keywords "a, b, c, d, e, f" \
      [--tags "idea"] [--libs d3,jsxgraph,mermaid,matter,plot,highlight]
  python3 .claude/skills/new-page/new_page.py --topic "Topic Name" --tags "math" \
      --description "…" --keywords "…"        # topic folder + index.html + log.md + raw/

Never overwrites an existing file. Fill every section afterwards; delete any that doesn't apply.
"""
import argparse, datetime, html, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
LIBS = {
    "katex": '<link rel="stylesheet" href="{p}katex/katex.min.css">\n<script defer src="{p}katex/katex.min.js"></script>\n'
             '<script defer src="{p}katex/auto-render.min.js" onload="renderMathInElement(document.body,{{delimiters:['
             "{{left:'\\\\[',right:'\\\\]',display:true}},{{left:'\\\\(',right:'\\\\)',display:false}}],macros:{{"
             "'\\\\Q':'\\\\mathbb{{Q}}','\\\\R':'\\\\mathbb{{R}}','\\\\C':'\\\\mathbb{{C}}','\\\\Z':'\\\\mathbb{{Z}}','\\\\N':'\\\\mathbb{{N}}',"
             "'\\\\F':'\\\\mathbb{{F}}','\\\\Gal':'\\\\operatorname{{Gal}}','\\\\Aut':'\\\\operatorname{{Aut}}','\\\\tr':'\\\\operatorname{{tr}}'}},"
             'throwOnError:false}})"></script>',
    "zoom": '<script defer src="{p}zoom/zoom.js"></script>',
    "d3": '<script src="{p}d3/d3.min.js"></script>',
    "plot": '<script src="{p}d3/d3.min.js"></script>\n<script src="{p}plot/plot.umd.min.js"></script>',
    "jsxgraph": '<link rel="stylesheet" href="{p}jsxgraph/jsxgraph.css">\n<script src="{p}jsxgraph/jsxgraphcore.js"></script>',
    "mermaid": '<script src="{p}mermaid/mermaid.min.js"></script>\n<script>addEventListener("DOMContentLoaded",function(){{'
               'mermaid.initialize({{startOnLoad:true,securityLevel:"strict",themeVariables:{{fontSize:"16px"}},theme:matchMedia("(prefers-color-scheme: dark)").matches?"dark":"neutral"}})}})</script>',
    "matter": '<script src="{p}matter/matter.min.js"></script>',
    "highlight": '<link rel="stylesheet" href="{p}highlight/github.min.css" media="(prefers-color-scheme: light)">\n'
                 '<link rel="stylesheet" href="{p}highlight/github-dark.min.css" media="(prefers-color-scheme: dark)">\n'
                 '<script src="{p}highlight/highlight.min.js"></script><script>addEventListener("DOMContentLoaded",function(){{hljs.highlightAll()}})</script>',
}
PAGE_BODY = """
  <p class="lede">The question this page answers, in plain words.</p>

  <!-- A visual first: what the reader should SEE (rich-visuals skill). -->
  <div class="card">Visual</div>

  <h2>A sharp example</h2>
  <p>The smallest case that exposes the structure (deep-insight skill: never a toy).</p>

  <div class="callout tip"><strong>The big idea</strong>One or two sentences, key formula boxed: \\( \\boxed{{\\,\\cdot\\,}} \\)</div>

  <h2>Why it must be so</h2>
  <p>The argument that forces it.</p>

  <h2>Where it breaks</h2>
  <p>The obstruction or counterexample, and what it measures.</p>

  <h2>The right setting</h2>
  <p>The generalisation where the idea becomes inevitable.</p>

  <h2>Connections</h2>
  <p>Links across topics: [[…]].</p>

  <h2>How to explain it</h2>
  <ul><li>One sentence:</li><li>Analogy or demo, and the visual to show:</li><li>Script:</li><li>What not to say:</li><li>Questions people ask:</li></ul>

  <h2>Check yourself</h2>
  <details class="q"><summary>A question that tests understanding?</summary><div class="answer"><p>…</p></div></details>

  <h2>Related</h2>
  <ul class="related"><li><a href="index.html">{folder}</a></li></ul>

  <h2>Sources</h2>
  <ol class="sources"><li>…</li></ol>
"""


def crumbs(rel_dir):
    parts = rel_dir.split("/") if rel_dir else []
    out = []
    for i, name in enumerate(parts):
        up = "../" * (len(parts) - 1 - i)
        out.append(f'<a href="{up}index.html">{html.escape(name)}</a>')
    return "<span>›</span>".join(out)


def build(template, rel, title, desc, keywords, tags, libs, body, eyebrow, topic):
    depth = rel.count("/")
    prefix = "../" * depth + "_assets/"
    doc = template
    doc = re.sub(r"<title>.*?</title>", f"<title>{html.escape(title)} · {html.escape(topic)}</title>", doc, flags=re.S)
    doc = re.sub(r'<meta name="description" content="[^"]*">', f'<meta name="description" content="{html.escape(desc, quote=True)}">', doc)
    doc = re.sub(r'<meta name="tags" content="[^"]*">', f'<meta name="tags" content="{html.escape(tags, quote=True)}">', doc)
    doc = re.sub(r'<meta name="keywords" content="[^"]*">', f'<meta name="keywords" content="{html.escape(keywords, quote=True)}">', doc)
    if 'name="keywords"' not in doc:
        doc = doc.replace('<meta name="tags"', f'<meta name="keywords" content="{html.escape(keywords, quote=True)}">\n<meta name="tags"', 1)
    includes = "\n".join(LIBS[l].format(p=prefix) for l in ["katex", "zoom"] + [l for l in libs if l not in ("katex", "zoom")])
    doc = re.sub(r"(</style>)", r"\1\n" + includes.replace("\\", "\\\\"), doc, count=1)
    m = re.search(r"<main[^>]*>", doc)
    end = doc.rfind("<footer")
    head_html = (f'\n  <nav class="crumbs">{crumbs(os.path.dirname(rel))}{"<span>›</span>" if os.path.dirname(rel) else ""}'
                 f'{html.escape(title)}</nav>\n\n  <div class="eyebrow">{html.escape(eyebrow)}</div>\n  <h1>{html.escape(title)}</h1>\n')
    today = datetime.date.today().isoformat()
    doc = doc[:m.end()] + head_html + body + "\n  " + doc[end:]
    doc = re.sub(r"Last updated [0-9Y-]+", f"Last updated {today}", doc)
    return doc


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("page", nargs="?")
    ap.add_argument("--topic")
    ap.add_argument("--title")
    ap.add_argument("--description", required=True)
    ap.add_argument("--keywords", required=True)
    ap.add_argument("--tags", default="")
    ap.add_argument("--libs", default="")
    a = ap.parse_args()
    template = open(os.path.join(ROOT, "_template.html"), encoding="utf-8").read()
    libs = [l.strip() for l in a.libs.split(",") if l.strip()]
    bad = [l for l in libs if l not in LIBS]
    if bad:
        sys.exit(f"unknown libs {bad}; choose from {sorted(LIBS)}")
    if len([k for k in a.keywords.split(",") if k.strip()]) < 6:
        sys.exit("give 6–15 keywords (wiki-graph skill)")
    if a.topic:
        topic = a.topic
        folder = os.path.join(ROOT, topic)
        os.makedirs(os.path.join(folder, "raw"), exist_ok=True)
        log = os.path.join(folder, "log.md")
        if not os.path.exists(log):
            open(log, "w").write(f"# {topic} — log\n\n## [{datetime.date.today()}] new topic | created {topic}/\n")
        rel = f"{topic}/index.html"
        title = a.title or topic
        body = ('\n  <p class="lede">What this topic is about, and the question that drives it.</p>\n\n'
                '  <!-- Open with a visual map of how the ideas connect (Mermaid or D3). -->\n'
                '  <figure class="card"><pre class="mermaid">flowchart LR\n  A["First idea"] --> B["Next idea"]</pre>'
                '<figcaption>What to notice.</figcaption></figure>\n\n  <h2>The path</h2>\n  <p>Subtopics, deepest insight first.</p>\n')
        libs = sorted(set(libs) | {"mermaid"})
        eyebrow = "Topic"
    else:
        if not a.page or not a.title:
            sys.exit("give a page path and --title, or --topic")
        rel = os.path.normpath(a.page)
        topic = rel.split("/")[0]
        title = a.title
        folder_name = os.path.basename(os.path.dirname(rel))
        body = PAGE_BODY.format(folder=html.escape(folder_name))
        eyebrow = re.sub(r"^\d+\s+", "", folder_name)
    target = os.path.join(ROOT, rel)
    if os.path.exists(target):
        sys.exit(f"{rel} already exists; edit it instead")
    if not os.path.isdir(os.path.dirname(target)):
        sys.exit(f"folder {os.path.dirname(rel)} doesn't exist; create the subtopic (with its index.html) first")
    open(target, "w", encoding="utf-8").write(build(template, rel, title, a.description, a.keywords, a.tags, libs, body, eyebrow, topic))
    print(f"created {rel} — now fill every section, link it from its folder's index.html, and run the checks")


if __name__ == "__main__":
    main()
