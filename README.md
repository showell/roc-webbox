# roc-webbox

A Roc platform for [webbox](../zig-webbox), and a TODO list built on it.

The app is Roc (`app/todo.roc`). Webbox serves it: `/` is a thin HTML/JS page
(`web/index.html`, compiled in), and every request under `/api/` goes to the
app. The app reads and writes its list as it runs, through effects the
platform provides, so a request's file work happens during the request. The
app does not hand the host a description of work to do afterwards.

```
zig build serve -Droc=<path to roc>     # http://localhost:9110
zig build test  -Droc=<path to roc>
```

`roc` on the PATH needs no `-Droc`. The Roc used is the nightly
`2026-10-18-1df370f`.

### Trying the client without a server

`zig build demo` builds a **client test bench**, `demo/`, which is **not the
server**. It is the same page with the Roc app compiled to WebAssembly,
answering the page's requests inside the browser tab, with its files in the
browser's storage. It is a quick way to try the client, and nothing more:
it runs no webbox code. [demo/README.md](demo/README.md) lists what it does
not test.

## The pieces

| | |
|---|---|
| `platform/main.roc` | The platform. The app provides `handle! : Http.Request => Http.Response`; the host calls it as `roc_handle`. |
| `platform/Http.roc` | `Request` `{ method, path, body }`, `Response` `{ status, content_type, body }`, and `json`/`text` helpers. |
| `platform/File.roc` | The effects: `read!`, `write!`, `delete!`. Each takes a path relative to the host's data root. |
| `app/todo.roc` | The TODO list: one JSON file, `todo/todos.json`. |
| `src/roc_abi.zig` | The host's side of the seam: `RocStr`, the records, Roc's runtime (`roc_alloc` and the rest), and the hosted functions. |
| `src/todo_app.zig` | The webbox site: the page, and `/api/*` sent to Roc. |
| `src/main.zig` | Linux main: webbox's Linux host. |
| `web/index.html` | The client. Every API answer is the whole list, and the page draws it. |
| `demo/` | **Not the server.** A test bench for the client: the Roc app as wasm in the tab (demo/README.md). |

## The API

```
GET    /api/todos              the list
POST   /api/todos              a new item, its text the body
POST   /api/todos/<id>/toggle  done, or not done again
DELETE /api/todos/<id>         gone
```

## Portability

Nothing here calls Linux. The hosted file functions go through
`webbox.store`, using the `Io` the host hands each request, under the
site's data root. Only `src/main.zig` names the Linux host, so a bare-metal
main can serve the same site.

The build picks the Roc target from the Zig target: `x64musl` for Linux, and
`x64v1elf` for freestanding x86-64. (The platform also lists `wasm32`, for
the client test bench in `demo/` alone.)

The archive asks its host for:

- `roc_alloc`, `roc_realloc`, `roc_dealloc` and `roc_crashed`;
- `memcpy`, `memmove` and `memset`;
- `roc_file_read`, `roc_file_write` and `roc_file_delete`.

## Two rules the seam keeps

- **A file that is not there and a file that could not be read are different
  answers.** `File.read!` says `NotFound` or `ReadFailed`, and the app turns a
  failed read into a 500. If a failed read looked like an empty list, the
  next write would replace the real list with it. The tests check this.
- **Everything Roc allocates during a request is in one arena, dropped when
  the request ends.** So `roc_dealloc` frees nothing, and the host keeps no
  refcounts for the strings it hands Roc. Webbox runs one handler at a time,
  so the arena and the request's `Io` are plain globals in `roc_abi.zig`.
