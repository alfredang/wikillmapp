#!/usr/bin/env node
// Renders every \( … \) and \[ … \] formula in the given pages with the library's own KaTeX
// and reports failures, leftover <span class="m"> maths and $…$ delimiters.
// Usage (from the library root): node .claude/skills/latex-math/check_math.js page.html [...]
const fs = require("fs"), path = require("path");
const root = path.resolve(__dirname, "..", "..", "..");
const katex = require(path.join(root, "_assets", "katex", "katex.min.js"));
const macros = { "\\Q": "\\mathbb{Q}", "\\R": "\\mathbb{R}", "\\C": "\\mathbb{C}", "\\Z": "\\mathbb{Z}",
  "\\N": "\\mathbb{N}", "\\F": "\\mathbb{F}", "\\Gal": "\\operatorname{Gal}", "\\Aut": "\\operatorname{Aut}",
  "\\tr": "\\operatorname{tr}" };
const decode = s => s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")
  .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&nbsp;/g, " ");
let failures = 0, formulas = 0;
for (const file of process.argv.slice(2)) {
  const html = fs.readFileSync(file, "utf8");
  const body = html.replace(/<script\b[\s\S]*?<\/script>/gi, "").replace(/<style\b[\s\S]*?<\/style>/gi, "")
    .replace(/<(pre|code)\b[\s\S]*?<\/\1>/gi, "");
  const problems = [];
  const rx = /\\\[([\s\S]*?)\\\]|\\\(([\s\S]*?)\\\)/g;
  let m;
  while ((m = rx.exec(body))) {
    formulas++;
    const tex = decode((m[1] ?? m[2]).replace(/<[^>]+>/g, ""));
    try { katex.renderToString(tex, { displayMode: m[1] !== undefined, throwOnError: true, macros: { ...macros }, strict: "ignore" }); }
    catch (e) { problems.push(`  formula error: ${e.message.split("\n")[0]}\n    in: ${tex.slice(0, 120)}`); }
  }
  const spans = (body.match(/<span class="m">/g) || []).length;
  if (spans) problems.push(`  ${spans} old <span class="m"> maths left to convert`);
  const dollars = (body.replace(/<[^>]+>/g, "").match(/\$[^$\s][^$]*\$/g) || []).filter(s => /[\\^_{}]/.test(s));
  if (dollars.length) problems.push(`  ${dollars.length} $…$ formulas (use \\( \\) instead): ${dollars[0].slice(0, 60)}`);
  if (formulas && !/katex\.min\.js/.test(html)) problems.push("  uses LaTeX but doesn't include _assets/katex");
  if (problems.length) { failures += problems.length; console.log(file + "\n" + problems.join("\n")); }
}
console.log(`${formulas} formulas checked, ${failures} problem${failures === 1 ? "" : "s"}`);
process.exit(failures ? 1 : 0);
