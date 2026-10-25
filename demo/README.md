# demo/: a client test bench. NOT the server.

> **Nothing in this folder is the TODO app's host.** The host is `src/`, a
> webbox site, served by webbox's Linux host (`zig build serve`) or its
> bare-metal one. This folder exists for one reason: to try the client
> (`web/index.html`) quickly, with no server anywhere.

`zig build demo` writes `zig-out/demo/`:

| file | what |
|---|---|
| `index.html` | `web/index.html`, unchanged except for one `<script src="host.js">` before its own script. |
| `artifact.html` | The same page without its `<html>`, `<head>` and `<body>` tags, for a claude.ai artifact (which supplies them). |
| `host.js` | The stand-in. It answers the page's `/api/` requests in the tab. |
| `todo.wasm` | `app/todo.roc` built for wasm32, with `demo/wasm_host.zig`. |

It needs the Roc `roc-version` pins, as every build does (README.md,
"Before you build"). Any static file server will do; the page's `api/`
requests never leave the tab:

```
zig build demo
python3 -m http.server -d zig-out/demo     # then open http://localhost:8000/
```

## What it is

- The page's own code, unchanged. `host.js` replaces `window.fetch` for
  any path containing `/api/` (the page asks relative to itself, so the
  bench works from any folder) and passes everything else through.
- The same Roc app (`app/todo.roc`) and the same runtime glue
  (`src/roc_abi.zig`) as the real host. So the client gets the same answers,
  errors included, that it will get from webbox.
- File effects that go to the browser's `localStorage`, or to memory when
  the browser refuses it. They do not go to webbox's store.

## What it does not test

- webbox: its HTTP handling, body limits, keep-alive, durability.
- The real file effects (`src/roc_files.zig` over `webbox.store`), or FAT's
  rules for names.
- Anything about the bare-metal host.
- Two users at once. Each browser has its own list.

## Trying the error paths

From the browser console:

```js
rocDemo.files.put("todos.json", "garbage")  // the next request answers 500
rocDemo.files.failNext = "disk on fire"          // the next file call fails
rocDemo.files.clear()                            // an empty list again
```
