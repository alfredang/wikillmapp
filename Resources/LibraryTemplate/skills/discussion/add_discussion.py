#!/usr/bin/env python3
"""Add one exchange (the person's question + the answer) to a page's Discussion section.

The Discussion section sits at the bottom of the page, newest first: the latest exchanges stay
open and older ones fold into a collapsed "Earlier discussion". Run from the library root:

  python3 .claude/skills/discussion/add_discussion.py "Topic/01 Sub/page.html" \
      --question "the person's words" --answer-file /tmp/answer.html [--date 2026-11-08]
      [--answer "<p>short HTML answer</p>"] [--verdict sound|fix|further] [--keep 3]

The question is plain text (kept word for word). The answer is HTML and may use LaTeX
(\\( \\) and \\[ \\]). Re-running with the same question and date does nothing.
"""
import argparse, datetime, html, re, sys

KEEP = 3
STYLE = """<style id="discussion-style">
  .discussion h2 { margin-bottom: 4px; }
  .discussion .discussion-note { color: var(--muted, #6b6878); font-size: 13px; margin: 0 0 8px; }
  .discussion details.qa { border-bottom: 1px solid var(--line, #e6e3f0); }
  .discussion details.qa > summary { list-style: none; cursor: pointer; display: flex; gap: 10px; align-items: baseline;
                                     padding: 7px 2px; font-size: 15px; }
  .discussion details.qa > summary::-webkit-details-marker { display: none; }
  .discussion details.qa > summary::before { content: "▸"; color: var(--accent, #6d4aff); font-size: 12px; }
  .discussion details.qa[open] > summary::before { content: "▾"; }
  .discussion .qa-date { flex: none; font-size: 12px; color: var(--muted, #6b6878); font-variant-numeric: tabular-nums; min-width: 72px; }
  .discussion .qa-text { flex: 1; }
  .discussion .verdict { flex: none; font-size: 11px; font-weight: 700; padding: 1px 8px; border-radius: 999px; }
  .discussion .verdict.sound { background: var(--ok-soft, #e4f6ee); color: var(--ok, #12805c); }
  .discussion .verdict.fix { background: #fff1e0; color: #a35a00; }
  .discussion .verdict.further { background: var(--accent-soft, #efeaff); color: var(--accent, #6d4aff); }
  .discussion .qa-a { margin: 0 0 10px 22px; padding: 8px 12px; border-left: 3px solid var(--accent, #6d4aff);
                      background: var(--surface, #f6f5fb); border-radius: 0 8px 8px 0; font-size: 15px; }
  .discussion .qa-a p { margin: 4px 0; }
  .discussion details.discussion-older > summary { cursor: pointer; color: var(--muted, #6b6878); font-size: 13px;
                                                   font-weight: 600; padding: 8px 2px; }
  @media (prefers-color-scheme: dark) { .discussion .verdict.fix { background: #3a2a14; color: #f5b04a; } }
</style>"""
VERDICTS = {"sound": "Sound", "fix": "Needs a fix", "further": "Goes further"}


def entry(date, question, answer, verdict):
    """One exchange as a single line (date · question); the answer opens on click."""
    when = datetime.date.fromisoformat(date).strftime("%-d %b %Y")
    q = html.escape(" ".join(question.split()))
    badge = f'<span class="verdict {verdict}">{VERDICTS[verdict]}</span>' if verdict else ""
    return (f'<!-- qa:start --><details class="qa" data-date="{date}" data-q="{html.escape(question.strip()[:80], quote=True)}">'
            f'<summary><time class="qa-date" datetime="{date}">{when}</time><span class="qa-text">{q}</span>{badge}</summary>'
            f'<div class="qa-a">{answer.strip()}</div>'
            f'</details><!-- qa:end -->')


def section(recent, older):
    older_html = ""
    if older:
        older_html = (f'<!-- discussion:older --><details class="discussion-older"><summary>Earlier discussion ({len(older)})</summary>'
                      + "\n".join(older) + "</details><!-- /discussion:older -->")
    return ('<!-- discussion:start --><section id="discussion" class="discussion">\n<h2>Discussion</h2>\n'
            '<p class="discussion-note">Your questions about this page, newest first. Click one to see the answer.</p>\n'
            '<!-- discussion:recent -->' + "\n".join(recent) + '<!-- /discussion:recent -->\n'
            + older_html + '\n</section><!-- discussion:end -->')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("page")
    ap.add_argument("--question", required=True)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--answer")
    g.add_argument("--answer-file")
    ap.add_argument("--date", default=datetime.date.today().isoformat())
    ap.add_argument("--verdict", choices=list(VERDICTS))
    ap.add_argument("--keep", type=int, default=KEEP)
    a = ap.parse_args()
    answer = a.answer if a.answer is not None else open(a.answer_file, encoding="utf-8").read()
    doc = open(a.page, encoding="utf-8").read()

    items = re.findall(r"<!-- qa:start -->.*?<!-- qa:end -->", doc, re.S)
    key = f'data-date="{a.date}" data-q="{html.escape(a.question.strip()[:80], quote=True)}"'
    if any(key in i for i in items):
        print(f"{a.page}: already recorded, nothing to do"); return
    items.insert(0, entry(a.date, a.question, answer, a.verdict))
    items.sort(key=lambda i: re.search(r'data-date="([^"]+)"', i).group(1), reverse=True)  # newest first, stable
    new = section(items[:a.keep], items[a.keep:])

    m = re.search(r"<!-- discussion:start -->.*?<!-- discussion:end -->", doc, re.S)
    if m:
        doc = doc[:m.start()] + new + doc[m.end():]
    else:
        # At the bottom of the page: before the footer, else before </main>, else before </body>.
        for pat in (r"\n?\s*<footer\b", r"\n?\s*</main>", r"\n?\s*</body>"):
            f = re.search(pat, doc, re.I)
            if f:
                doc = doc[:f.start()] + "\n\n  " + new + doc[f.start():]
                break
        else:
            doc += new
    # (Re)write the shared style so every page has the current compact look.
    doc = re.sub(r'<style id="discussion-style">.*?</style>\n?', "", doc, flags=re.S)
    doc = re.sub(r"</head>", STYLE + "\n</head>", doc, count=1, flags=re.I)
    open(a.page, "w", encoding="utf-8").write(doc)
    note = ""
    if re.search(r"\\\(|\\\[", answer) and "katex.min.js" not in doc:
        note = " (answer uses LaTeX: the app renders it; add the KaTeX include for plain browsers)"
    print(f"{a.page}: {len(items)} exchange(s), {min(len(items), a.keep)} shown, {max(0, len(items) - a.keep)} folded{note}")


if __name__ == "__main__":
    main()
