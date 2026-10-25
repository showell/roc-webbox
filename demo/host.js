// ╔══════════════════════════════════════════════════════════════════════╗
// ║ NOT THE SERVER. A TEST BENCH FOR THE CLIENT (web/index.html) ONLY.    ║
// ╚══════════════════════════════════════════════════════════════════════╝
//
// A quick way to try the TODO page without running webbox anywhere: the
// page's own code, unchanged, with its requests to /api/ answered here, in
// the tab, by the Roc app built for wasm32 (todo.wasm, demo/wasm_host.zig).
// Its files live in this browser's localStorage (or in memory when that is
// refused), not in webbox's store.
//
// What this does NOT test: webbox (its HTTP, body limits, durability), the
// real file effects (src/roc_files.zig), or anything about the bare-metal
// host. The real server is src/: `zig build serve`.
//
// To try the page's error paths from the browser console:
//   rocDemo.files.put("todos.json", "garbage")   // the next request is a 500
//   rocDemo.files.failNext = "disk on fire"           // the next file call fails
//   rocDemo.files.clear()                             // an empty list again
(() => {
  "use strict";
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  const wasmUrl = new URL("todo.wasm", document.currentScript.src);

  // ── the files: localStorage when the browser allows it, else memory ──
  const prefix = "roc-webbox-demo:";
  let storage = null;
  try {
    localStorage.setItem(prefix + "probe", "1");
    localStorage.removeItem(prefix + "probe");
    storage = localStorage;
  } catch (_) {}
  const memory = new Map();
  const files = {
    failNext: null,
    get(path) {
      try { if (storage) return storage.getItem(prefix + path); } catch (_) {}
      return memory.has(path) ? memory.get(path) : null;
    },
    put(path, text) {
      try { if (storage) { storage.setItem(prefix + path, text); return; } } catch (_) {}
      memory.set(path, text);
    },
    remove(path) {
      try { if (storage) { storage.removeItem(prefix + path); return; } } catch (_) {}
      memory.delete(path);
    },
    clear() {
      memory.clear();
      try {
        if (storage) for (const k of Object.keys(storage)) if (k.startsWith(prefix)) storage.removeItem(k);
      } catch (_) {}
    },
    where: storage ? "this browser's localStorage" : "memory (gone on reload)",
  };

  // ── the wasm module's imports ──
  let x = null; // its exports
  let pending = new Uint8Array(0);
  // Wasm hands back pointers as signed numbers; an empty string's may be
  // anything (Zig's zero-length slices point nowhere), so it is never read.
  const bytes = (ptr, len) => len === 0 ? new Uint8Array(0) : new Uint8Array(x.memory.buffer, ptr >>> 0, len);
  const text = (ptr, len) => decoder.decode(bytes(ptr, len));
  const leave = s => { pending = encoder.encode(s); };
  function failed() {
    if (files.failNext === null) return false;
    leave(files.failNext);
    files.failNext = null;
    return true;
  }
  const env = {
    js_file_read(p, n) {
      if (failed()) return 2;
      const got = files.get(text(p, n));
      if (got === null) { leave(""); return 1; }
      leave(got);
      return 0;
    },
    js_file_write(p, n, t, tn) {
      if (failed()) return 2;
      try { files.put(text(p, n), text(t, tn)); return 0; } catch (e) { leave(String(e)); return 2; }
    },
    js_file_delete(p, n) {
      if (failed()) return 2;
      files.remove(text(p, n));
      return 0;
    },
    js_pending_len: () => pending.length,
    js_take(dst) { bytes(dst, pending.length).set(pending); },
    js_crashed(p, n) { throw new Error("roc crashed: " + text(p, n)); },
  };

  const ready = fetch(wasmUrl)
    .then(r => { if (!r.ok) throw new Error(`todo.wasm: ${r.status}`); return r.arrayBuffer(); })
    .then(buf => WebAssembly.instantiate(buf, { env }))
    .then(({ instance }) => { x = instance.exports; x.demo_init(); });

  // One request through the Roc app, as webbox would hand it over.
  async function serve(method, path, body) {
    await ready;
    const put = s => {
      const b = encoder.encode(s);
      if (b.length === 0) return [0, 0];
      const p = x.demo_alloc(b.length);
      bytes(p, b.length).set(b);
      return [p, b.length];
    };
    try {
      const a = x.demo_handle(...put(method), ...put(path), ...put(body));
      const w = new Uint32Array(x.memory.buffer, a >>> 0, 5);
      return { status: w[0], contentType: text(w[1], w[2]), body: text(w[3], w[4]) };
    } catch (e) {
      return { status: 500, contentType: "text/plain; charset=utf-8", body: String(e.message || e) };
    } finally {
      x.demo_end();
    }
  }

  // ── the page's fetch: .../api/ goes to the Roc app, the rest as before ──
  const realFetch = window.fetch.bind(window);
  window.fetch = async (input, init = {}) => {
    const url = new URL(typeof input === "string" ? input : input.url, location.href);
    // The page asks relative to itself, so /api/ follows wherever it is.
    const at = url.pathname.indexOf("/api/");
    if (at < 0) return realFetch(input, init);
    const method = (init.method || "GET").toUpperCase();
    const body = init.body == null ? "" : typeof init.body === "string" ? init.body : await new Response(init.body).text();
    const r = await serve(method, url.pathname.slice(at), body);
    return new Response(r.body, { status: r.status, headers: { "content-type": r.contentType } });
  };

  // ── say so on the page ──
  function banner() {
    const style = document.createElement("style");
    style.textContent = `
      .roc-demo-banner { border: 1px dashed var(--line, #999); border-radius: 6px; padding: .6rem .8rem;
        margin-block: 0 1.25rem; font-size: .85rem; line-height: 1.45; color: var(--muted, #555); }
      .roc-demo-banner strong { color: var(--fg, inherit); }
      .roc-demo-banner code { font-size: .8rem; }`;
    const aside = document.createElement("aside");
    aside.className = "roc-demo-banner";
    aside.innerHTML = `<strong>Client test bench, not the server.</strong> The Roc app runs here in the tab,
      compiled to WebAssembly, and keeps its list in <span class="where"></span>. The real server is webbox,
      on Linux or bare metal. This stand-in exercises the page and the Roc app only.`;
    aside.querySelector(".where").textContent = files.where;
    document.body.prepend(style, aside);
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", banner);
  else banner();

  window.rocDemo = { files, serve };
})();
