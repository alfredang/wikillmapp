---
name: insight-pages
description: How to create content in this library the way the person wants it — intuitive, insightful, visual pages built on their own thinking, not collections of information. Use whenever you write, rewrite or extend any page, answer a question that should change a page, or turn the person's intuition into notes. Defines the page shape, the writing rules, how to handle their intuitions, and the insight test every page must pass before filing.
---

# Creating intuitive, insightful pages

## What the person wants, in their words

- "Don't treat me like primary school. Remove those basic stuff. I need deep discussion and insight."
  The reader is mathematically mature: follow the `deep-insight` skill for the level.
- "I don't want just a collection of info. I need insights, and how I can explain it to people."
- "The app must make my intuition sensible, or correct it, or expand on it, and add all these insights
  to the notes. Then it becomes my notes."
- "The HTML pages must be highly visual, intuitive and creative, and help me gain insights and expand
  them deeply into the subject." "I am a visual person, so make it visual if possible."
- "I don't want my questions to be gone": every question is kept on its page (Discussion section).
- Maths renders beautifully in LaTeX; pages are interconnected like a graph; search finds them.

A page has done its job when the person can say the big idea in one sentence, see why it is true,
know where it stops being true, and explain it to a friend.

## The shape of a page

Follow this order. Skip a part only when it truly doesn't apply.

1. **The question.** Open with the question the page answers, ideally the person's own, in plain
   words ("Why is the trace enough to tell representations apart?").
2. **A picture first.** A visual that lets the reader see the answer before reading it (follow the
   `rich-visuals` skill). The best ones let the reader predict, then reveal.
3. **A sharp concrete case.** The smallest example that exposes the structure or breaks a naive
   claim, at the reader's level (see `deep-insight`). Never a toy or a textbook drill.
4. **The big idea in one line.** In a highlighted callout, one or two sentences, with the key formula
   boxed in LaTeX (`latex-math` skill). This is the insight; everything else supports it.
5. **Why it works.** The argument the reader can follow and see, step by step, each step earned by
   the picture or the example. Never a formula from nowhere.
6. **Where it breaks.** The smallest counterexample or the assumption it depends on. The boundary is
   often the deepest insight.
7. **The general case, then the abstract structure.** The right setting where the idea becomes
   inevitable, with the full statement, after the reader knows why it is shaped that way. Assume
   standard definitions; state only the non-standard ones.
8. **Your intuition.** The person's own intuitions and analogies about this idea, in their words,
   each with a verdict (see below).
9. **Think of it like… / Where the analogy breaks.** An everyday analogy next to the idea, and where
   it fails.
10. **The history of ideas.** Who saw what, when, and how one person's idea fed the next — briefly,
    as a story of insight, not a list of dates.
11. **Connections.** How it links to other topics in the library, especially across topics (a group
    idea showing up in physics). Link them; this is what makes the library a graph.
12. **How to explain it.** One sentence; the analogy or physical demo, and the visual to show; a short
    script in plain words; what not to say (the common misconceptions); the questions people will
    ask, with short answers; a question to ask the listener.
13. **Check yourself.** Two to four questions that test understanding, not recall (predict, explain
    why, spot the flaw), with answers in `<details>`.
14. **Related**, **Sources**, then the **Discussion** at the very bottom (`discussion` skill).

## Turning the person's intuition into notes

When they offer an intuition, analogy or guess, never just agree or just correct. Put it on the page
in their words in a **Your intuition** box, then answer it:

- **Sound:** say exactly why it works and which fact it captures.
- **Needs a fix:** where it breaks, with the smallest counterexample, then the repaired version.
  Keep the original beside the repair; the gap between them is the insight.
- **Goes further:** what it leads to that they haven't said yet.

Example. Their words: "Think of different footballs with different shapes, each with a short and a
long axis. The trace is like the total length, and that is good enough to tell how many football
shapes there are." *Sound* in that totals add, \( \chi_{V\oplus W} = \chi_V + \chi_W \), and don't
depend on which way the ball faces, as the trace doesn't depend on the basis. *Needs a fix*: one total
can't tell a (1, 3) ball from a (2, 2) ball. *Repair*: measure once per kind of symmetry (each
conjugacy class), and powers give more totals for free. Then record the exchange in the Discussion.

## Writing rules

- **Why before what.** Every section answers a "why" the reader would actually ask.
- **One big idea per page.** If there are two, make two linked pages.
- **Plain words, short sentences.** Define a term the first time, right where it is used.
- **Show, then tell.** A visual or an example comes before the abstract statement.
- **Original synthesis, not a summary.** Never copy Wikipedia or a textbook's order; write your own
  angle and say what is surprising. Background only where it serves the person's thinking.
- **Labels.** Mark claims **Established** (with a source), **Your idea** (the person's) or
  **Conjecture** (ours, untested). Never invent a reference, number or result.
- **All maths in LaTeX**, matrices as real matrices (`latex-math`).
- **Dense links** to every concept that has its own page, and **keywords** in the `<head>`.

## The insight test (run it before filing)

Answer each honestly. Fix the page until every answer is yes.

1. Can a reader state the big idea in one sentence after reading the first screen?
2. Is there a visual that shows the idea, not one that decorates the page?
3. Is the "why" answered with an argument the reader can see, not just asserted?
4. Does the page say where the idea fails or what it depends on?
5. Is there at least one thing that would surprise a smart reader?
6. Are the person's own intuitions and questions on the page, each with a verdict?
7. Could the person explain it to a friend using only the How to explain it section?
8. Does it connect to at least one other topic in the library?
9. Does every formula render, and does every number trace to a source or a run?

## Anti-patterns

A page that opens with definitions. A wall of text with no visual. A formula with no picture or
argument behind it. A list of facts with no "so what". A summary of a source. Plain-text maths. An
insight that lives only in the chat. Agreeing with the person's intuition without testing it.
