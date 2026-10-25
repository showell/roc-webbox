# roc-webbox

A Roc platform for [webbox](../zig-webbox), and a TODO list built on it.

The app is Roc (`app/todo.roc`). Webbox serves it: `/` is a thin HTML/JS page
(`web/index.html`, compiled in), and every request under `/api/` goes to the
app. The app reads and writes its list as it runs, through effects the
platform provides, so a request's file work happens during the request. The
app does not hand the host a description of work to do afterwards.

## Before you build

- **Zig 0.17** (`build.zig.zon`).
- **Sibling checkouts** under the same parent directory: `../zig-webbox`
  for every build; `../zig-metal-unikernel` and the `../zig-coverage-sdk` it
  depends on for `zig build metal` (a lazy dependency: only `metal` needs
  them).
- **Roc, the nightly `roc-version` pins** (`nightly-2026-10-09-258ab27`), as
  `roc` on the PATH or named with `-Droc=<path>`. Every build compiles
  `app/todo.roc`, and `build.zig` (`rocCompiler`) stops at configure time if
  there is no Roc or `roc version` names another.

## Build, test, serve

```
zig build test                          # src/todo_test.zig, then src/shared_check.zig
zig build serve                         # http://localhost:9110
zig build demo                          # the client test bench, zig-out/demo/ (below)
zig build metal                         # zig-out/bin/roc-todo.elf
```

`zig build -l` lists the steps. `test` runs the host's tests through the
Roc app (the seam's strings, the routes against a store in a temporary
folder), then `src/shared_check.zig`: the list with `roc_hooks` in its root,
as a binary holding two Roc apps has it. It is a program, not a test,
because a test's root is the test runner's.

`serve` reads its settings from the environment (`src/main.zig`):

| | |
|---|---|
| `TODO_PORT`, `TODO_BIND` | where it listens (default port 9110) |
| `TODO_DATA` | the data folder; default `data/` in the directory it runs in |
| `TODO_CONFIG` | path of a `key = value` file naming `data_dir` and `auth_dir` (zig-webbox's `src/linux_config.zig`); its `data_dir` wins over `TODO_DATA` |
| `TODO_TRUSTED_PROXY`, `TODO_KEEPALIVE_MS` | webbox's Linux host settings |

**Where the data lives:** one file, `<data>/todos.json`, in the folder the host
gives the app. Standalone that is `data/todos.json`; mounted by a
combination at `/todo`, `<data>/todo/todos.json`. The host also opens an
auth folder (default `auth/`); the list keeps nothing in it.

### On the unikernel

`zig build metal` builds the list as a
[zig-metal-unikernel](../zig-metal-unikernel) kernel of its own, through its
`addAppKernel`, as Dog Park does: `src/hosted.zig` gives the kernel the site
and what only the app can say about itself, `assets.zon` what it serves
besides its code, and the Roc is built for freestanding x86-64. It is
always ReleaseSafe. The kernel needs a disk: a GPT disk whose partition 1
is FAT16, empty to start; the list is made on it at `data/todos.json` and
survives a reboot.

This repo has no script to boot it. zig-metal-unikernel's README covers
QEMU and the disk image (`droplet/app_image.py`); dog-park's
`tools/metal_gate.mjs` is a worked example of booting an application kernel
under QEMU.

## Combined with other webbox apps

The list mounts beside other apps through zig-webbox's `webbox.combo.Mount`
(`zig-webbox/src/combo.zig`). Mounted at a prefix, it is served with the
prefix stripped and gets its own `<data>/<name>` and `<auth>/<name>`. The
page asks for `api/todos` relative to itself, so it works under any prefix.

**A combination's build lives in its primary's repo.** Dog Park + TODO is
in dog-park: `src/combos/dogpark_todo.zig` (the site),
`src/combos/dogpark_todo_main.zig` (Linux), and the steps `dogpark-todo`,
`serve-dogpark-todo` (Dog Park at `/`, the list at `/todo/`, port 9113,
`COMBO_PORT`) and `metal-dogpark-todo` (`zig-out/bin/dogpark-todo.elf`).

What this repo exports for a combination (`build.zig`):

| module | for |
|---|---|
| `roc_todo` | `src/hosted.zig` with its Roc linked, for a Linux combination; takes the combination's `target`, `optimize` and `roc` options |
| `roc_todo_metal` | the same for a combination's kernel: one of zig-metal-unikernel `addAppKernel`'s `parts`, with `assets.zon`; no target or mode (the kernel's), Roc built for `x64v1elf` |
| `roc_hooks` | `src/roc_hooks.zig`, Roc's runtime when a binary holds two Roc apps |

Pitfalls:

- **Two Roc apps, one binary, one set of runtime symbols.** Roc's code
  calls `roc_alloc`, `roc_realloc`, `roc_dealloc` and `roc_crashed` by name.
  A binary holding two Roc apps declares `pub const roc_hooks =
  @import("roc_hooks");` in its root; `roc_hooks` then owns the four and
  hands each call to the app inside its Roc call. Alone, `src/roc_abi.zig`
  exports its own. A kernel's root forwards the application's
  (`src/roc_hooks.zig` says how).
- **The pins must agree.** A combination builds every Roc part with its
  primary's Roc, handed down as `-Droc`. If the primary pins a different
  nightly than `roc-version`, the build stops at configure time saying so.
  Moving the pin means moving every combination's pin together.
- **Mounted apps use relative URLs.** A change to `web/index.html` that
  asks for `/api/...` works standalone and breaks under `/todo`.

## Trying the client without a server

`zig build demo` builds a **client test bench**, `demo/`, which is **not the
server**. It is the same page with the Roc app compiled to WebAssembly,
answering the page's requests inside the browser tab, with its files in the
browser's storage. It is a quick way to try the client, and nothing more:
it runs no webbox code. [demo/README.md](demo/README.md) lists what it does
not test.

## The pieces

| | |
|---|---|
| `roc-version` | The Roc nightly every build uses. |
| `platform/main.roc` | The platform. The app provides `handle! : Http.Request => Http.Response`; the host calls it as `roc_handle`. |
| `platform/Http.roc` | `Request` `{ method, path, body }`, `Response` `{ status, content_type, body }`, and `json`/`text` helpers. |
| `platform/File.roc` | The effects: `read!`, `write!`, `delete!`. Each takes a path relative to the host's data root. |
| `app/todo.roc` | The TODO list: one JSON file, `<data>/todos.json`, in the folder the host gives it. |
| `src/roc_abi.zig` | The host's side of the seam: `RocStr`, the records, Roc's runtime (`roc_alloc` and the rest), and the hosted functions. |
| `src/roc_files.zig` | The hosted file functions over `webbox.store`, under the data root. |
| `src/roc_hooks.zig` | Roc's runtime for a binary holding more than one Roc app. |
| `src/todo_app.zig` | The webbox site: the page, and `/api/*` sent to Roc. |
| `src/main.zig` | Linux main: webbox's Linux host. |
| `src/hosted.zig` | The site as a host takes it: zig-metal-unikernel's kernel (`zig build metal`), and a combination (`roc_todo`, `roc_todo_metal`). |
| `src/todo_test.zig`, `src/shared_check.zig` | `zig build test`. |
| `assets.zon` | What the site serves besides its code: the page, compiled in. |
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

- `roc_alloc`, `roc_realloc`, `roc_dealloc` and `roc_crashed` (from
  `src/roc_abi.zig`, or from `roc_hooks` in a binary with two Roc apps);
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
