---
name: latex-math
description: Write every formula in library pages as LaTeX, rendered offline by KaTeX from _assets/katex. Use whenever a page contains mathematics or physics notation, when converting old plain-text maths (<span class="m">) to LaTeX, and before filing any page with equations. Includes a checker that renders every formula and reports errors.
---

# LaTeX maths in library pages

All mathematics is written in **LaTeX** and typeset by **KaTeX**, which ships offline in
`_assets/katex/`. Never write maths as plain text or Unicode look-alikes (`x^2`, `√2`, `ℚ`,
`<span class="m">…</span>`, `<sup>`): they render badly and can't be searched or reused.

## Include KaTeX in the page

In `<head>`, after the template's `<style>`, with `../` repeated once per folder level below the
library root (`Topic/page.html` → `../_assets/`, `Topic/01 Sub/page.html` → `../../_assets/`):

```html
<link rel="stylesheet" href="../../_assets/katex/katex.min.css">
<script defer src="../../_assets/katex/katex.min.js"></script>
<script defer src="../../_assets/katex/auto-render.min.js" onload="renderMathInElement(document.body,{
  delimiters:[{left:'\\[',right:'\\]',display:true},{left:'\\(',right:'\\)',display:false}],
  macros:{'\\Q':'\\mathbb{Q}','\\R':'\\mathbb{R}','\\C':'\\mathbb{C}','\\Z':'\\mathbb{Z}','\\N':'\\mathbb{N}',
          '\\F':'\\mathbb{F}','\\Gal':'\\operatorname{Gal}','\\Aut':'\\operatorname{Aut}','\\tr':'\\operatorname{tr}'},
  throwOnError:false})"></script>
```

The Wiki LLM app also loads KaTeX by itself for any page that contains `\(` or `\[`, but include
it anyway so the page renders in a plain browser too.

## Writing the maths

- Inline maths: `\( \Gal(\Q(\sqrt[3]{2},\omega)/\Q) \cong S_3 \)`. Display maths:
  `\[ \chi_{V\oplus W} = \chi_V + \chi_W \]`. **Never use `$…$`**: dollar signs appear in prose.
- HTML still parses the page first, so write `<` and `>` as `\lt` and `\gt` (or `&lt;`, `&gt;`)
  and `&` in matrices as `&amp;`.
- Use real notation: `\mathbb{Q}`, `\sqrt[3]{2}`, `\frac{1}{|G|}\sum_{g\in G}`, `\langle a \rangle`,
  `\hbar`, `\vec{J}`, `\left( \right)`, `\begin{pmatrix} … \end{pmatrix}`, `\begin{aligned} … \end{aligned}`.
- Make the key idea visible: `\boxed{\,\dim V^G = \tfrac{1}{|G|}\sum_g \chi(g)\,}`, and colour the
  terms a nearby visual also colours: `{\color{#e5484d} \lambda_1}`.
- Walk through derivations one step per line in `aligned`, with a few words of reasoning between
  displays. A formula should read as the end of an argument the reader already followed.
- Inside SVG or Canvas, KaTeX doesn't reach: put formulas in HTML labels positioned over the figure,
  or render with `katex.render(tex, element)` from your own script.

## Converting old pages

Replace each `<span class="m">…</span>` (and bare Unicode maths in prose) with the LaTeX it means:
`ℚ` → `\(\Q\)`, `∛2` → `\(\sqrt[3]{2}\)`, `φ(17) = 16` → `\(\varphi(17) = 16\)`, `x²` → `\(x^2\)`,
`a ∈ G` → `\(a \in G\)`. Keep the wording around it, keep every link, tag and label, and leave
code samples alone. Remove the `.m` style only once no `.m` span is left on the page.

## Check before filing

Run the checker on every page you touched; it renders each formula with KaTeX exactly as the
page will and lists any that fail, plus leftover `.m` spans and `$` maths:

```bash
node .claude/skills/latex-math/check_math.js "Topic/01 Sub/page.html" [more pages…]
```

Fix every error it reports before you finish.
