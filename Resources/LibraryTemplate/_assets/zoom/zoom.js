/* Enlarge button for figures in library pages (Wiki LLM). Self-contained and offline.
   Every diagram (Mermaid), image, SVG figure and canvas gets a visible "⤢ Enlarge" button.
   It opens a popup that fills the window, with zoom in / out / fit buttons; scroll or pinch to
   zoom, drag to pan, Esc or ✕ to close. The figure itself is left alone, so links and controls
   inside it keep working. Opt out on an element with class "nozoom". Include once:
   <script defer src="../../_assets/zoom/zoom.js"></script>                                      */
(function () {
  if (window.__wikiZoom) return;
  window.__wikiZoom = true;

  var css = document.createElement("style");
  css.textContent =
    ".wz-wrap{position:relative}" +
    ".wz-btn{position:absolute;top:8px;right:8px;z-index:5;display:inline-flex;align-items:center;gap:5px;" +
    "padding:4px 10px;border-radius:999px;border:1px solid var(--line,#ddd);background:var(--card,#fff);" +
    "color:var(--accent,#6d4aff);font:600 12px/18px -apple-system,BlinkMacSystemFont,sans-serif;cursor:pointer;" +
    "box-shadow:0 1px 4px rgba(0,0,0,.08);opacity:.92}" +
    ".wz-btn:hover{opacity:1;border-color:var(--accent,#6d4aff)}" +
    ".wz-overlay{position:fixed;inset:0;z-index:99999;background:rgba(8,8,12,.95);overflow:hidden;" +
    "touch-action:none;cursor:grab}" +
    ".wz-overlay.dragging{cursor:grabbing}" +
    ".wz-stage{position:absolute;left:0;top:0;background:#fff;color:#1b1a22;border-radius:12px;padding:20px;" +
    "box-shadow:0 20px 60px rgba(0,0,0,.5);transform-origin:0 0;will-change:transform}" +
    ".wz-stage svg,.wz-stage img{display:block;max-width:none!important;height:auto}" +
    ".wz-bar{position:fixed;top:0;left:0;right:0;height:52px;z-index:100000;display:flex;align-items:center;" +
    "justify-content:center;gap:8px;background:rgba(8,8,12,.85);border-bottom:1px solid rgba(255,255,255,.08)}" +
    ".wz-bar button{min-width:38px;height:34px;padding:0 12px;border-radius:9px;border:0;" +
    "background:rgba(255,255,255,.14);color:#fff;font:600 14px -apple-system,sans-serif;cursor:pointer}" +
    ".wz-bar button:hover{background:rgba(255,255,255,.28)}" +
    ".wz-bar .wz-close{position:absolute;right:12px}" +
    ".wz-bar .wz-pct{color:rgba(255,255,255,.7);font:12px -apple-system,sans-serif;min-width:48px;text-align:center}" +
    ".wz-hint{position:fixed;bottom:12px;left:50%;transform:translateX(-50%);color:rgba(255,255,255,.6);" +
    "font:12px -apple-system,sans-serif;z-index:100000;pointer-events:none}";
  document.head.appendChild(css);

  function contentFor(el) {
    if (el.tagName === "CANVAS") {
      var img = new Image(); img.src = el.toDataURL("image/png"); img.width = el.width; return img;
    }
    if (el.tagName === "IMG") {
      var i = new Image(); i.src = el.currentSrc || el.src; i.alt = el.alt || "";
      i.width = el.naturalWidth || el.width; return i;
    }
    var c = el.cloneNode(true);   // keep the id: Mermaid scopes its styles to it
    var box = el.getBoundingClientRect(), vb = el.viewBox && el.viewBox.baseVal;
    var w = vb && vb.width ? vb.width : box.width, h = vb && vb.height ? vb.height : box.height;
    if (!el.getAttribute("viewBox") && w && h) c.setAttribute("viewBox", "0 0 " + w + " " + h);
    c.removeAttribute("style"); c.style.maxWidth = "none";
    c.setAttribute("width", Math.round(w)); c.setAttribute("height", Math.round(h));
    return c;
  }

  function open(el) {
    var overlay = document.createElement("div"); overlay.className = "wz-overlay";
    overlay.setAttribute("role", "dialog"); overlay.setAttribute("aria-label", "Enlarged figure");
    var stage = document.createElement("div"); stage.className = "wz-stage";
    stage.appendChild(contentFor(el)); overlay.appendChild(stage);
    var bar = document.createElement("div"); bar.className = "wz-bar";
    bar.innerHTML = '<button aria-label="Zoom out">−</button><span class="wz-pct"></span>' +
      '<button aria-label="Zoom in">+</button><button aria-label="Fit to window">Fit</button>' +
      '<button aria-label="Actual size">1:1</button><button class="wz-close" aria-label="Close">✕ Close</button>';
    var hint = document.createElement("div"); hint.className = "wz-hint";
    hint.textContent = "Scroll or pinch to zoom · drag to move · Esc to close";
    document.body.appendChild(overlay); document.body.appendChild(bar); document.body.appendChild(hint);
    var prevOverflow = document.documentElement.style.overflow;
    document.documentElement.style.overflow = "hidden";
    var pct = bar.querySelector(".wz-pct"), top = 52;

    var s = 1, x = 0, y = 0, natW = 0, natH = 0;
    function apply() {
      stage.style.transform = "translate(" + x + "px," + y + "px) scale(" + s + ")";
      pct.textContent = Math.round(s * 100) + "%";
    }
    function measure() {
      stage.style.transform = "none";
      var r = stage.getBoundingClientRect(); natW = r.width; natH = r.height;
    }
    function center() {
      x = (innerWidth - natW * s) / 2; y = top + (innerHeight - top - natH * s) / 2; apply();
    }
    function fit() {
      measure();
      s = Math.min((innerWidth - 32) / natW, (innerHeight - top - 40) / natH, 8);
      center();
    }
    function actual() { measure(); s = 1; center(); }
    function zoomAt(f, cx, cy) {
      var ns = Math.max(0.1, Math.min(16, s * f)); f = ns / s;
      x = cx - (cx - x) * f; y = cy - (cy - y) * f; s = ns; apply();
    }
    function close() {
      overlay.remove(); bar.remove(); hint.remove();
      document.documentElement.style.overflow = prevOverflow;
      removeEventListener("keydown", onKey, true);
      removeEventListener("resize", fit);
    }
    function onKey(e) {
      if (e.key === "Escape") { e.preventDefault(); close(); }
      else if (e.key === "+" || e.key === "=") zoomAt(1.25, innerWidth / 2, innerHeight / 2);
      else if (e.key === "-") zoomAt(0.8, innerWidth / 2, innerHeight / 2);
      else if (e.key === "0") fit();
    }
    addEventListener("keydown", onKey, true);
    addEventListener("resize", fit);
    var b = bar.querySelectorAll("button");
    b[0].onclick = function () { zoomAt(1 / 1.3, innerWidth / 2, innerHeight / 2); };
    b[1].onclick = function () { zoomAt(1.3, innerWidth / 2, innerHeight / 2); };
    b[2].onclick = fit; b[3].onclick = actual; b[4].onclick = close;

    overlay.addEventListener("wheel", function (e) {
      e.preventDefault();
      if (e.ctrlKey || Math.abs(e.deltaY) > Math.abs(e.deltaX)) {
        zoomAt(Math.exp(-e.deltaY * (e.ctrlKey ? 0.012 : 0.003)), e.clientX, e.clientY);
      } else { x -= e.deltaX; apply(); }
    }, { passive: false });
    // Trackpad pinch in Safari/WebKit arrives as gesture events.
    var g0 = 1;
    overlay.addEventListener("gesturestart", function (e) { e.preventDefault(); g0 = 1; });
    overlay.addEventListener("gesturechange", function (e) {
      e.preventDefault(); zoomAt(e.scale / g0, e.clientX || innerWidth / 2, e.clientY || innerHeight / 2); g0 = e.scale;
    });
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
    overlay.addEventListener("pointerup", function (e) { up(e); if (!moved && e.target === overlay) close(); });
    overlay.addEventListener("pointercancel", up);
    overlay.addEventListener("dblclick", fit);
    requestAnimationFrame(function () { requestAnimationFrame(fit); });
  }

  function candidates() {
    var out = [];
    document.querySelectorAll(".mermaid svg, img, svg, canvas").forEach(function (el) {
      if (el.__wz || el.closest(".nozoom, .wz-overlay, .katex, button, .wz-btn")) return;
      if (el.tagName === "svg" || el.tagName === "SVG" || el instanceof SVGElement) {
        if (el.parentElement && el.parentElement.closest("svg")) return;   // nested svg
      }
      var r = el.getBoundingClientRect();
      if (r.width < 140 || r.height < 80) return;                          // icons and glyphs
      out.push(el);
    });
    return out;
  }

  function setup() {
    candidates().forEach(function (el) {
      el.__wz = true;
      var host = el.closest(".mermaid") || el.parentElement;
      if (host.__wzBtn) return;                                            // one button per figure
      host.__wzBtn = true;
      host.classList.add("wz-wrap");
      var btn = document.createElement("button");
      btn.type = "button"; btn.className = "wz-btn"; btn.innerHTML = "⤢ Enlarge";
      btn.setAttribute("aria-label", "Open this figure in a larger view");
      btn.addEventListener("click", function (e) { e.preventDefault(); e.stopPropagation(); open(el); });
      host.appendChild(btn);
    });
  }

  // Mermaid and other scripts draw after load: set up now and again as the page changes.
  var pending = null;
  function schedule() { clearTimeout(pending); pending = setTimeout(setup, 300); }
  if (document.readyState === "loading") addEventListener("DOMContentLoaded", schedule); else schedule();
  addEventListener("load", schedule);
  new MutationObserver(function (list) {
    for (var i = 0; i < list.length; i++) {
      var t = list[i].target;
      if (t.closest && (t.closest(".wz-overlay") || t.closest(".wz-bar"))) return;
    }
    schedule();
  }).observe(document.body || document.documentElement, { childList: true, subtree: true });
})();
