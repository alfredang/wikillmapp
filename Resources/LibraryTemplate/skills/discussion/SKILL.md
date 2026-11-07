---
name: discussion
description: Record the person's questions and the exchanges about a page in that page's Discussion section at the bottom, newest first with older ones collapsed, so the notes keep their thinking process. Use after answering any question, query or intuition the person raises about a page or topic, and when backfilling past conversations.
---

# The Discussion section

Every page ends with a **Discussion** section: the person's questions and our exchanges about
that page, newest first. The latest three stay open; older ones fold into "Earlier discussion".
It is the record of how their thinking developed, so it keeps their words exactly.

## When to record

After you answer anything the person asks or proposes about a page or topic: a question, a query,
an intuition, an objection, a "why". Record it on the page it is about (the page they are viewing
is in `.claude/viewing.nosync`, written by the app); a question about a whole topic or subtopic goes
on that folder's `index.html`. If it touches several pages, record it on the main one and link the
others from the answer. Record each exchange once.

## How to record

Always use the script, never hand-edit the section, so every page has the same structure:

```bash
cat > /tmp/answer.html <<'HTML'
<p>Short, self-contained answer in HTML: the key point first, then the reasoning.
Maths in LaTeX: \( \chi_V(g) = \operatorname{tr}\rho(g) \).</p>
<p>See <a href="characters.html">characters</a> for the full argument.</p>
HTML
python3 .claude/skills/discussion/add_discussion.py "Topic/01 Sub/page.html" \
  --question "the person's question, word for word" --answer-file /tmp/answer.html \
  --verdict fix            # optional: sound | fix | further, when they offered an intuition
```

- **Question:** the person's words exactly, typos fixed only if they hide the meaning.
- **Answer:** a faithful summary of what was answered, 1–3 short paragraphs (not the whole chat
  turn): the main point, the reasoning, and a link to where the page now covers it. Write it so it
  makes sense on its own months later.
- **Verdict:** for an intuition, say whether it was sound, needed a fix, or goes further (see
  "Make them the person's notes" in `CLAUDE.md`).
- **Date:** today by default; use `--date YYYY-MM-DD` when backfilling.

The Discussion section is the log; the page body is the synthesis. When an exchange produces an
insight, also work it into the page body as the rules in `CLAUDE.md` describe.

## Backfilling past conversations

Past Claude Code sessions for this library are in `~/.claude/projects/<library path with / as ->/*.jsonl`.
Each line is a JSON event; the person's messages are `"type":"user"` entries whose
`message.content` is text (skip tool results), and answers are the following `"type":"assistant"`
text blocks. Pick out the real questions and intuitions (not instructions like "push to github" or
"make the font bigger"), work out which page each is about, and record them with their dates.
