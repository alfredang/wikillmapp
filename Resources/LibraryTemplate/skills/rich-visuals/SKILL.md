---
name: rich-visuals
description: Draw rich, interactive visuals in library pages — D3 charts and diagrams, animations, sliders, rotatable 3D, and KaTeX maths — using the offline copies in _assets/. Use whenever a page explains an idea that a picture, animation or interactive would make intuitive (geometry, functions, data, flows of ideas, timelines, physics simulations).
---

# Rich visuals in library pages

Pages here are HTML, so they can show what prose can't: a shape deforming as you drag a
slider, a chart that animates, a diagram of how ideas flowed. The person learns through
**intuition**: use a visual whenever it makes the *why* visible, not as decoration.

## What's available offline

Everything lives in `_assets/` at the library root. The app hides `_` folders from the
sidebar, and pages may read any file inside the library. **Never use a CDN.**

| Library | Files in `_assets/` | Use for |
|---|---|---|
| KaTeX 0.16 | `katex/katex.min.css`, `katex.min.js`, `auto-render.min.js` | All maths, as LaTeX (see the `latex-math` skill) |
| D3 v7.9 | `d3/d3.min.js` | Custom SVG, scales, axes, transitions, force layouts, drag, zoom |
| Observable Plot 0.6 | `plot/plot.umd.min.js` (load after D3) | A data chart in a few lines: `Plot.plot({marks:[Plot.line(data,{x:"t",y:"v"})]})` |
| JSXGraph 1.14 | `jsxgraph/jsxgraphcore.js`, `jsxgraph.css` | Draggable geometry and function plots that keep their constraints: points, lines, circles, sliders, curves |
| Mermaid 12 | `mermaid/mermaid.min.js` | Flowcharts, sequence, state, class, timeline and mind-map diagrams written as text |
| Matter.js 0.20 | `matter/matter.min.js` | 2D physics: bodies, gravity, collisions, springs, constraints |
| highlight.js 11 | `highlight/highlight.min.js`, `github.min.css`, `github-dark.min.css` | Colour-coded code samples |

Plain inline SVG and vanilla JS also work, need no library, and are often enough. The
existing pages (for example `Algebra/02 Determinant/area-in-2d.html`) do it that way.

## Include with a relative path

Count how deep the page is below the library root, and prefix that many `../`:

| Page | Prefix |
|---|---|
| `Topic/index.html` | `../_assets/` |
| `Topic/01 Sub/page.html` | `../../_assets/` |
| `Topic/01 Sub/02 Deeper/page.html` | `../../../_assets/` |

```html
<!-- in <head>, after the template's <style> -->
<link rel="stylesheet" href="../../_assets/katex/katex.min.css">
<script defer src="../../_assets/katex/katex.min.js"></script>
<script defer src="../../_assets/katex/auto-render.min.js"
  onload="renderMathInElement(document.body,{delimiters:[{left:'\\[',right:'\\]',display:true},{left:'\\(',right:'\\)',display:false}]})"></script>
<script src="../../_assets/d3/d3.min.js"></script>
```

Don't use `$…$` delimiters: dollar signs appear in prose. Pages that already use the
`<span class="m">` maths style can keep it, so don't mix the two styles on one page.

## Including the other libraries

Same relative prefix as above. Load only what the page uses.

```html
<!-- JSXGraph: a draggable construction -->
<link rel="stylesheet" href="../../_assets/jsxgraph/jsxgraph.css">
<script src="../../_assets/jsxgraph/jsxgraphcore.js"></script>
<div id="box" class="jxgbox" style="width:100%;aspect-ratio:4/3"></div>
<script>
  var b = JXG.JSXGraph.initBoard("box", {boundingbox:[-5,5,5,-5], axis:true, showCopyright:false, showNavigation:false});
  var a = b.create("slider", [[-4,4],[0,4],[-3,1,3]], {name:"a"});
  b.create("functiongraph", [function(x){ return a.Value()*x*x; }], {strokeColor:"#7C5CFF", strokeWidth:3});
</script>

<!-- Mermaid: a diagram from text; follow the page's light or dark mode -->
<script src="../../_assets/mermaid/mermaid.min.js"></script>
<pre class="mermaid">flowchart LR
  A[Symmetry] --> B[Representation] --> C[Character = trace]</pre>
<script>mermaid.initialize({startOnLoad:true, securityLevel:"strict",
  theme: matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "neutral"});</script>

<!-- Matter.js: a small physics scene -->
<script src="../../_assets/matter/matter.min.js"></script>

<!-- highlight.js: code samples -->
<link rel="stylesheet" href="../../_assets/highlight/github.min.css" media="(prefers-color-scheme: light)">
<link rel="stylesheet" href="../../_assets/highlight/github-dark.min.css" media="(prefers-color-scheme: dark)">
<script src="../../_assets/highlight/highlight.min.js"></script><script>hljs.highlightAll();</script>
```

Which to reach for: a picture that changes with one parameter → D3 or JSXGraph with a slider; a
construction the reader drags → JSXGraph; a process, architecture or flow of ideas → Mermaid; forces
and motion → Matter.js; measured or computed data → Plot.

## Visuals that build insight

Write each visual's question as its caption, then answer it with one of these: **predict, then
reveal** (the reader commits to a guess before the answer animates in); **morph** (a slider carries
the simple case into the general one); **invariant** (a live readout of what stays fixed while
everything moves); **linked views** (equation, picture and table update together); **break it** (push
past the theorem's assumptions and show the counterexample); **sandbox** (free controls at the end,
discoveries labelled Conjecture). When the person has offered their own analogy, build the visual on
it. A topic or subtopic `index.html` opens with a visual map of how its ideas connect.

## Make it look native

- **Colours:** use the template's CSS variables, so light and dark mode both work:
  `var(--accent)`, `var(--ink)`, `var(--muted)`, `var(--line)`, `var(--surface)`, `var(--ok)`,
  `var(--warn)`, `var(--bad)`. In D3: `.attr("stroke", "var(--accent)")`. For several series,
  use fixed mid-tones that read on both backgrounds: `#e5484d`, `#30a46c`, `#3e63dd`, `#f5a524`.
- **Layout:** put the figure in a `.card`. Use `viewBox` with `width:100%;height:auto`, so it scales.
  Put controls beside the figure in a CSS grid,
  `grid-template-columns: repeat(auto-fit, minmax(270px, 1fr))`.
- **Controls:** use `<input type="range">` with `accent-color: var(--accent)`, preset buttons
  styled as pills, and a live text readout with `aria-live="polite"` that states the numbers
  *and what they mean*.
- **Accessibility:** give every SVG `role="img"` and an `aria-label` that says what it shows. Make
  draggable figures keyboard-operable too, with arrow keys.

## Animation

- Use `d3.transition().duration(600)` for state changes, and `requestAnimationFrame` for continuous motion.
- Respect `matchMedia('(prefers-reduced-motion: reduce)')`: if it's set, jump straight to the end state.
- Prefer animations the reader controls (a slider for *t* from 0 to 1, or a play/pause
  button) over autoplay. Let the reader scrub to the moment where the insight happens.

## Patterns that teach well

1. **Morph:** interpolate from the identity, or the simple case, to the general case with a `t` slider.
2. **Invariant display:** show a quantity that stays constant while the picture changes. That
   constancy *is* the insight (for example, area while a shear slides).
3. **Before and after:** show the original faded or dashed beside its image.
4. **Presets:** give 4–7 buttons for the telling cases: typical, special, degenerate, extreme.
5. **Flow-of-ideas graph:** for history pages, draw people as nodes and influences as arrows,
   laid out by year on the x-axis (a D3 force layout with `forceX` by year, or hand-placed).
6. **Rotatable 3D:** use orthographic projection with yaw and pitch from pointer drag, and draw
   faces sorted far to near. See the `V3` helper inlined in
   `Algebra/02 Determinant/volume-in-n-dimensions.html`.

## Check before filing

- Extract each inline `<script>` and run `node --check` on it to catch syntax errors.
- Check that every `../_assets/...` path resolves from the page's folder.
- Verify every number a visual displays in the topic's `runs/` check script.
- Without JavaScript, the page must still make sense: prose and a static SVG carry the
  argument, and the interactive deepens it.

## Example: a D3 line chart that animates in

```html
<div class="card"><svg id="fig" viewBox="0 0 480 260" role="img" aria-label="y = sin x from 0 to 2π" style="width:100%;height:auto"></svg></div>
<script>
(function(){
  var svg=d3.select("#fig"), W=480, H=260, m=30;
  var x=d3.scaleLinear([0,2*Math.PI],[m,W-m]), y=d3.scaleLinear([-1.1,1.1],[H-m,m]);
  svg.append("g").attr("transform","translate(0,"+y(0)+")").call(d3.axisBottom(x).ticks(6)).attr("color","var(--muted)");
  var data=d3.range(0,2*Math.PI+0.01,0.02).map(function(t){return[t,Math.sin(t)]});
  var path=svg.append("path").datum(data).attr("fill","none").attr("stroke","var(--accent)").attr("stroke-width",2.5)
    .attr("d",d3.line().x(function(d){return x(d[0])}).y(function(d){return y(d[1])}));
  var L=path.node().getTotalLength(), still=matchMedia("(prefers-reduced-motion: reduce)").matches;
  if(!still) path.attr("stroke-dasharray",L).attr("stroke-dashoffset",L).transition().duration(1200).attr("stroke-dashoffset",0);
})();
</script>
```
