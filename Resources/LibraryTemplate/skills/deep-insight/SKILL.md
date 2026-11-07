---
name: deep-insight
description: The depth standard for this library — the person is mathematically mature and wants deep discussion and insight, never basics. Use before writing or rewriting any page, answering any question, or reviewing a topic, to set the level, cut elementary material ("no simple stuff"), and go to structure, reasons and connections. Includes the basics audit for pruning existing pages.
---

# Deep insight, no simple stuff

## Who the reader is

The person said: "I don't need the matrix transformations to be so simple, showing me shear and
reflect. Don't treat me like primary school. Remove those basic stuff. I need deep discussion and
insight." "Treat me like a learned student or researcher that asks deep questions."

Treat them as a learned student or researcher who asks deep questions. Write for a mathematically
mature reader: comfortable with linear algebra, abstract algebra,
calculus and proofs at university level and beyond. They want to understand *why things must be
so*, how ideas connect, and where they lead, not to be walked through definitions or textbook
examples.

## Cut

- Definitions and examples any undergraduate textbook opens with: "a matrix is where the basis goes",
  the five basic moves (stretch, rotate, shear, reflect, project), "AB means do B then A", area of a
  parallelogram, row-times-column drills, a group is a set with an operation.
- Step-by-step computations of routine cases, and recaps of prerequisites. Assume them; link to a
  reference page if one is needed, in one line.
- Visuals that only illustrate the obvious (a shear sliding a square). A visual must reveal
  something non-obvious.
- Encouraging filler ("this is a beautiful idea", "don't worry if…").

## Go deep

For every topic, aim at the layer that gives real understanding:

- **Structure and invariants.** What is preserved, what classifies the objects, why the
  classification has exactly that shape (e.g. conjugacy classes and Jordan form, not a gallery of
  2×2 matrices; the polar decomposition and SVD as the \( KAK \) / Cartan decomposition of
  \( GL_n \); why trace and determinant are the coefficients of the characteristic polynomial and
  what the rest of it encodes).
- **Why it must be so.** The argument that forces the result: a uniqueness, a universal property, a
  dimension count, a symmetry. Sketch proofs that carry the idea; skip proofs that only verify.
- **The obstruction.** Where the naive version fails and what the failure measures (non-diagonalisable
  matrices and nilpotents; non-commuting rotations and curvature; why there is no quintic formula).
- **Generalisation and the right setting.** The level where the idea becomes inevitable: linear maps
  over any field, modules, Lie groups and Lie algebras, categories, exterior algebra and forms.
- **Connections across fields.** The same structure in another topic of the library or in physics,
  computation or geometry (representations ↔ quantum numbers; determinants ↔ volume forms ↔
  orientation; Galois groups ↔ symmetry of roots ↔ solvability).
- **Open questions and frontiers.** What is still unknown, contested or active, and what the person
  could think about next. Label it **Conjecture** where it is ours.
- **History as insight.** The real problem that forced each idea into existence (who was stuck, and
  what they saw), not a timeline.

Examples stay, but as *sharp* examples: the smallest case that exposes the structure or breaks a
naive claim (a nilpotent 2×2, \( SO(3) \) versus \( SU(2) \), \( S_3 \) acting on roots of
\( x^3 - 2 \)), never a toy.

## Deep discussion

When answering the person: engage at their level, give the real reason, offer the non-obvious angle,
push back when an idea is wrong, and end with where it leads (a sharper question, a generalisation, a
connection). Several viewpoints on one fact are welcome (algebraic, geometric, physical,
computational). Record the exchange with the `discussion` skill.

## The basics audit (for existing pages)

For each page in the folder you are reviewing:

1. Ask: would a strong graduate student learn anything here? If no, the page is basics.
2. Basics pages: fold any non-obvious insight they hold into a deeper page, then delete the page.
   Before deleting, move its Discussion entries and "Your intuition" boxes to the page that absorbs
   it (never lose the person's words), and repoint every link to it
   (`python3 .claude/skills/wiki-graph/wiki_index.py report` lists inbound links and broken ones
   afterwards).
3. Mixed pages: cut the elementary sections, keep and deepen the rest.
4. Rewrite the folder's `index.html` so its map and visual show the deep path.
5. Log what was cut and why in the topic's `log.md`.

Depth is not length. A deep page is often shorter: it skips what the reader knows and spends its
words on the step that is actually hard.
