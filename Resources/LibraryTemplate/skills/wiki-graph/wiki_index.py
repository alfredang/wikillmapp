#!/usr/bin/env python3
"""Fast text search and link-graph checks over the library's own metadata (no vector index).

Run from the library root:
  python3 .claude/skills/wiki-graph/wiki_index.py search trace character        # find pages
  python3 .claude/skills/wiki-graph/wiki_index.py search @math eigenvalue        # @tag narrows
  python3 .claude/skills/wiki-graph/wiki_index.py related "Topic/01 Sub/page.html"
  python3 .claude/skills/wiki-graph/wiki_index.py report ["Topic"]               # graph health
"""
import html, os, re, sys, urllib.parse

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SKIP = ("_", ".")


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def meta(doc, name):
    m = re.search(r'<meta\s+name="%s"\s+content="([^"]*)"' % name, doc, re.I)
    return html.unescape(m.group(1)) if m else None


def load():
    pages = {}
    for d, dirs, files in os.walk(ROOT):
        rel = os.path.relpath(d, ROOT)
        parts = [] if rel == "." else rel.split(os.sep)
        dirs[:] = [x for x in dirs if not x.startswith(SKIP) and x not in ("raw", "runs")]
        if not parts:
            continue
        for f in files:
            if not f.endswith(".html"):
                continue
            p = os.path.join(rel, f)
            doc = open(os.path.join(ROOT, p), encoding="utf-8", errors="ignore").read()
            t = re.search(r"<title[^>]*>(.*?)</title>", doc, re.S | re.I)
            title = html.unescape(t.group(1)).split(" · ")[0].strip() if t else f
            body = re.sub(r"<(script|style)\b.*?</\1>", " ", doc, flags=re.S | re.I)
            pages[p] = dict(path=p, topic=parts[0], title=title, doc=doc,
                            text=html.unescape(re.sub(r"<[^>]+>", " ", body)).lower(),
                            desc=meta(doc, "description"),
                            tags=[x.strip() for x in (meta(doc, "tags") or "").split(",") if x.strip()],
                            keywords=[x.strip().lower() for x in (meta(doc, "keywords") or "").split(",") if x.strip()],
                            has_tags=meta(doc, "tags") is not None, has_keywords=meta(doc, "keywords") is not None)
    names = {}
    for p, v in pages.items():
        names.setdefault(norm(v["title"]), p)
        names.setdefault(norm(os.path.basename(p)[:-5]), p)
        if os.path.basename(p) == "index.html":
            names.setdefault(norm(os.path.basename(os.path.dirname(p))), p)
    for p, v in pages.items():
        out, broken, unresolved = set(), [], []
        body = re.sub(r"<(script|style)\b.*?</\1>", " ", v["doc"], flags=re.S | re.I)
        for h in re.findall(r'href="([^"#:?]+\.html)', body):
            q = os.path.normpath(os.path.join(os.path.dirname(p), urllib.parse.unquote(h)))
            (out.add(q) if q in pages else broken.append(h))
        for w in re.findall(r"\[\[([^\]|#]+)", body):
            q = names.get(norm(w))
            (out.add(q) if q else unresolved.append(w))
        out.discard(p)
        v.update(out=out, broken=broken, unresolved=unresolved)
    for v in pages.values():
        v["inc"] = set()
    for p, v in pages.items():
        for q in v["out"]:
            pages[q]["inc"].add(p)
    return pages


def search(pages, words):
    tags = [norm(w[1:]) for w in words if w.startswith("@")]
    terms = [w.lower() for w in words if not w.startswith("@")]
    hits = []
    for v in pages.values():
        if tags and not all(any(t in norm(x) for x in v["tags"]) for t in tags):
            continue
        score = 0
        for w in terms:
            s = 5 * (w in v["title"].lower()) + 4 * any(w in k for k in v["keywords"]) \
                + 3 * any(w in x for x in v["tags"]) + 2 * (w in (v["desc"] or "").lower()) \
                + 1 * (w in v["path"].lower()) + 0.5 * (w in v["text"])
            if not s:
                break
            score += s
        else:
            hits.append((score + 0.01 * len(v["inc"]), v))
    for score, v in sorted(hits, key=lambda h: -h[0])[:15]:
        print(f"{score:5.1f}  {v['path']}\n       {v['title']} — {(v['desc'] or '')[:90]}")
    if not hits:
        print("no pages match")


def related(pages, path):
    v = pages.get(os.path.normpath(path))
    if not v:
        sys.exit(f"not a library page: {path}")
    print(f"{v['title']}  ({len(v['out'])} out, {len(v['inc'])} in)")
    mine = set(v["keywords"]) | set(v["tags"])
    cands = []
    for q, w in pages.items():
        if q == v["path"]:
            continue
        shared = mine & (set(w["keywords"]) | set(w["tags"]))
        mentioned = w["title"].lower() in v["text"] and len(w["title"]) > 4
        if shared or mentioned:
            cands.append((len(shared) + 2 * mentioned, q, w, shared, mentioned))
    print("\nNot yet linked from this page, most related first:")
    for score, q, w, shared, mentioned in sorted(cands, key=lambda c: -c[0])[:12]:
        if q in v["out"]:
            continue
        why = (["title mentioned in prose"] if mentioned else []) + ([", ".join(sorted(shared))[:60]] if shared else [])
        print(f"  {q}\n      {'; '.join(why)}{'  [other topic]' if w['topic'] != v['topic'] else ''}")
    print("\nPages linking here but not linked back:")
    for q in sorted(v["inc"] - v["out"])[:12]:
        print("  " + q)


def report(pages, topic=None):
    sel = {p: v for p, v in pages.items() if not topic or v["topic"] == topic}
    def show(label, items):
        print(f"\n{label}: {len(items)}")
        for i in items[:25]:
            print("  " + i)
    show("Orphans (no page links here)", sorted(p for p, v in sel.items() if not v["inc"]))
    show("Broken relative links", [f"{p} → {b}" for p, v in sel.items() for b in v["broken"]])
    show("Unresolved [[wikilinks]]", [f"{p} → [[{w}]]" for p, v in sel.items() for w in v["unresolved"]])
    show("Missing keywords meta", sorted(p for p, v in sel.items() if not v["has_keywords"]))
    show("Fewer than 6 keywords", sorted(p for p, v in sel.items() if v["has_keywords"] and len(v["keywords"]) < 6))
    show("Missing description", sorted(p for p, v in sel.items() if not v["desc"]))
    show("Topic/subtopic index pages without tags", sorted(p for p, v in sel.items()
         if p.endswith("index.html") and not v["tags"]))
    show("Weakly linked (fewer than 3 links in + out)", sorted(p for p, v in sel.items() if len(v["out"] | v["inc"]) < 3))
    titles = {}
    for p, v in pages.items():
        titles.setdefault(v["title"].lower(), []).append(p)
    show("Duplicate titles", [" | ".join(ps) for t, ps in titles.items() if len(ps) > 1 and any(p in sel for p in ps)])
    edges = sum(len(v["out"]) for v in sel.values())
    cross = sum(1 for v in sel.values() for q in v["out"] if pages[q]["topic"] != v["topic"])
    print(f"\n{len(sel)} pages, {edges} links, {cross} across topics")


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ("search", "related", "report"):
        sys.exit(__doc__)
    pages = load()
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "search":
        search(pages, args)
    elif cmd == "related":
        related(pages, args[0])
    else:
        report(pages, args[0] if args else None)
