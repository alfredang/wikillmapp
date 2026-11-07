/* Click-to-zoom for library pages (Wiki LLM). Self-contained, offline, no dependencies.
   - Mermaid diagrams, images and figures marked .zoom open full screen when clicked.
   - Other sizeable SVGs and canvases (often interactive) get a small ⤢ button instead, so their
     controls keep working; the button opens a still copy.
   - In the viewer: scroll or pinch to zoom, drag to pan, double-click to reset, Esc to close.
   Opt out on an element with class "nozoom". Include once:
   <script defer src="../../_assets/zoom/zoom.js"></script>                                      */
(function () {
  if (window.__wikiZoom) return;
  window.__wikiZoom = true;

  var css = document.createElement("style");
  css.textContent =
    ".wz-target{cursor:zoom-in}" +
    ".wz-wrap{position:relative}" +
    ".wz-btn{position:absolute;top:6px;right:6px;z-index:5;width:28px;height:28px;border-radius:8px;" +
    "border:1px solid var(--line,#ddd);background:var(--card,#fff);color:var(--ink,#222);font:15px/26px -apple-system,sans-serif;" +
    "text-align:center;cursor:zoom-in;opacity:0;transition:opacity .15s}" +
    ".wz-wrap:hover .wz-btn,.wz-btn:focus{opacity:.9}" +
    ".wz-overlay{position:fixed;inset:0;z-index:99999;background:rgba(10,10,16,.86);" +
    "overflow:hidden;touch-action:none;cursor:grab}" +
    ".wz-overlay.dragging{cursor:grabbing}" +
    ".wz-stage{position:absolute;left:0;top:0;background:var(--card,#fff);border-radius:12px;padding:18px;" +
    "box-shadow:0 20px 60px rgba(0,0,0,.4);transform-origin:0 0;will-change:transform;max-width:none}" +
    ".wz-stage svg,.wz-stage img,.wz-stage canvas{display:block;max-width:none!important;height:auto}" +
    ".wz-bar{position:fixed;top:14px;right:14px;z-index:100000;display:flex;gap:6px}" +
    ".wz-bar button{width:36px;height:36px;border-radius:10px;border:0;background:rgba(255,255,255,.14);color:#fff;" +
    "font:18px -apple-system,sans-serif;cursor:pointer}.wz-bar button:hover{background:rgba(255,255,255,.26)}" +
    ".wz-hint{position:fixed;bottom:14px;left:50%;transform:translateX(-50%);color:rgba(255,255,255,.7);" +
    "font:12px -apple-system,sans-serif;z-index:100000}";
  document.head.appendChild(css);

  function contentFor(el) {
    if (el.tagName === "CANVAS") {
      var img = new Image(); img.src = el.toDataURL("image/png"); img.width = el.width; return img;
    }
    var c = el.cloneNode(true);
    // Keep an SVG's id: Mermaid scopes its styles to it (#mermaid-123 .node rect …).
    if (c.tagName.toLowerCase() !== "svg") c.removeAttribute("id");
    if (c.tagName.toLowerCase() === "svg") {
      var box = el.getBoundingClientRect(), vb = el.viewBox && el.viewBox.baseVal;
      var w = vb && vb.width ? vb.width : box.width, h = vb && vb.height ? vb.height : box.height;
      if (!el.getAttribute("viewBox") && w && h) c.setAttribute("viewBox", "0 0 " + w + " " + h);
      c.style.maxWidth = "none";
      // Vector: render at its natural size; the viewer scales it to fit, sharply.
      c.setAttribute("width", Math.round(w)); c.setAttribute("height", Math.round(h));
    }
    return c;
  }

  function open(el) {
    var overlay = document.createElement("div"); overlay.className = "wz-overlay";
    overlay.setAttribute("role", "dialog"); overlay.setAttribute("aria-label", "Zoomed view");
    var stage = document.createElement("div"); stage.className = "wz-stage";
    stage.appendChild(contentFor(el)); overlay.appendChild(stage);
    var bar = document.createElement("div"); bar.className = "wz-bar";
    bar.innerHTML = '<button aria-label="Zoom in">+</button><button aria-label="Zoom out">−</button>' +
                    '<button aria-label="Fit">⤢</button><button aria-label="Close">✕</button>';
    var hint = document.createElement("div"); hint.className = "wz-hint";
    hint.textContent = "Scroll or pinch to zoom · drag to pan · double-click to fit · Esc to close";
    document.body.appendChild(overlay); document.body.appendChild(bar); document.body.appendChild(hint);
    var prevOverflow = document.documentElement.style.overflow;
    document.documentElement.style.overflow = "hidden";

    var s = 1, x = 0, y = 0;
    function apply() { stage.style.transform = "translate(" + x + "px," + y + "px) scale(" + s + ")"; }
    function fit() {
      stage.style.transform = "none";
      var r = stage.getBoundingClientRect();
      s = Math.min(innerWidth * 0.94 / r.width, innerHeight * 0.88 / r.height, 4);
      x = (innerWidth - r.width * s) / 2; y = (innerHeight - r.height * s) / 2; apply();
    }
    function zoomAt(f, cx, cy) {
      var ns = Math.max(0.2, Math.min(12, s * f)); f = ns / s;
      x = cx - (cx - x) * f; y = cy - (cy - y) * f; s = ns; apply();
    }
    function close() {
      overlay.remove(); bar.remove(); hint.remove();
      document.documentElement.style.overflow = prevOverflow;
      removeEventListener("keydown", onKey, true);
    }
    function onKey(e) {
      if (e.key === "Escape") { e.preventDefault(); close(); }
      else if (e.key === "+" || e.key === "=") zoomAt(1.25, innerWidth / 2, innerHeight / 2);
      else if (e.key === "-") zoomAt(0.8, innerWidth / 2, innerHeight / 2);
    }
    addEventListener("keydown", onKey, true);
    var b = bar.querySelectorAll("button");
    b[0].onclick = function () { zoomAt(1.3, innerWidth / 2, innerHeight / 2); };
    b[1].onclick = function () { zoomAt(1 / 1.3, innerWidth / 2, innerHeight / 2); };
    b[2].onclick = fit; b[3].onclick = close;

    overlay.addEventListener("wheel", function (e) {
      e.preventDefault();
      zoomAt(Math.exp(-e.deltaY * (e.ctrlKey ? 0.01 : 0.0025)), e.clientX, e.clientY);
    }, { passive: false });
    var pts = new Map(), last = null, moved = false, pinch = null;
    overlay.addEventListener("pointerdown", function (e) {
      overlay.setPointerCapture(e.pointerId); pts.set(e.pointerId, [e.clientX, e.clientY]);
      moved = false; last = [e.clientX, e.clientY]; overlay.classList.add("dragging");
      if (pts.size === 2) { var p = Array.from(pts.values()); pinch = Math.hypot(p[0][0] - p[1][0], p[0][1] - p[1][1]); }
    });
    overlay.addEventListener("pointermove", function (e) {
      if (!pts.has(e.pointerId)) return;
      pts.set(e.pointerId, [e.clientX, e.clientY]);
      if (pts.size === 2 && pinch) {
        var p = Array.from(pts.values()), d = Math.hypot(p[0][0] - p[1][0], p[0][1] - p[1][1]);
        zoomAt(d / pinch, (p[0][0] + p[1][0]) / 2, (p[0][1] + p[1][1]) / 2); pinch = d; moved = true; return;
      }
      var dx = e.clientX - last[0], dy = e.clientY - last[1];
      if (Math.abs(dx) + Math.abs(dy) > 2) moved = true;
      x += dx; y += dy; last = [e.clientX, e.clientY]; apply();
    });
    function up(e) {
      pts.delete(e.pointerId); if (pts.size < 2) pinch = null;
      if (!pts.size) overlay.classList.remove("dragging");
      if (pts.size === 1) last = Array.from(pts.values())[0];
    }
    overlay.addEventListener("pointerup", function (e) {
      up(e);
      if (!moved && e.target === overlay) close();      // a click on the backdrop closes
    });
    overlay.addEventListener("pointercancel", up);
    overlay.addEventListener("dblclick", fit);
    requestAnimationFrame(fit);
  }

  function isInteractive(el) {
    return !!el.closest("a, button, input, label, .jxgbox") ||
           !!el.querySelector("[draggable], input, foreignObject") ||
           el.matches(".interactive, [data-interactive]");
  }

  function setup() {
    // Diagrams and images: click anywhere on them.
    document.querySelectorAll(".mermaid svg, img, figure.zoom svg, .zoom > svg, svg.zoom").forEach(function (el) {
      if (el.__wz || el.closest(".nozoom, a, .wz-overlay")) return;
      var r = el.getBoundingClientRect();
      if (el.tagName === "IMG" && (r.width < 60 || r.height < 40)) return;
      el.__wz = true; el.classList.add("wz-target");
      el.addEventListener("click", function (e) { e.preventDefault(); open(el); });
    });
    // Other sizeable SVGs and canvases: a corner button, so their own controls keep working.
    document.querySelectorAll("svg, canvas").forEach(function (el) {
      if (el.__wz || el.closest(".nozoom, .wz-overlay, .katex, button, a") || el.closest(".mermaid")) return;
      if (el.parentElement && el.parentElement.closest("svg")) return;       // nested svg
      var r = el.getBoundingClientRect();
      if (r.width < 160 || r.height < 100) return;                           // icons, tiny glyphs
      el.__wz = true;
      var host = el.parentElement;
      host.classList.add("wz-wrap");
      var btn = document.createElement("button");
      btn.type = "button"; btn.className = "wz-btn"; btn.textContent = "⤢";
      btn.title = "Zoom"; btn.setAttribute("aria-label", "Open a zoomed view");
      btn.addEventListener("click", function (e) { e.preventDefault(); e.stopPropagation(); open(el); });
      host.appendChild(btn);
      if (!isInteractive(el) && el.tagName !== "CANVAS") {
        el.classList.add("wz-target");
        el.addEventListener("dblclick", function () { open(el); });
      }
    });
  }

  // Mermaid and other scripts render after load: set up now and again as the page changes.
  var pending = null;
  function schedule() { clearTimeout(pending); pending = setTimeout(setup, 250); }
  if (document.readyState === "loading") addEventListener("DOMContentLoaded", schedule); else schedule();
  addEventListener("load", schedule);
  new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
})();
