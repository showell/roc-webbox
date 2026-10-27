# Roc Chat: porting angry-gopher's chat to Roc on webbox

angry-gopher's chat (`zig-server/src/chat*.zig` and its neighbours) is moving
to a Roc app in this repo, `chat/`, route by route. This doc is the design
and the plan: how it is built, the rules it keeps, and what is left. Live
tracking (milestones, the release candidate and its scope) is in metal-vmm's
`QUEUE.md`.

## 1. Goal

- **A webbox app.** The same Roc serves on webbox's Linux host and on bare
  metal. Production (lynrummy.com) is bare metal: zig-metal-unikernel builds
  `gopher.elf` from angry-gopher's checkout.
- **The same files.** The Roc chat reads and writes exactly the files the Zig
  chat does, so there is no migration, and going back is the previous
  release.
- **The client is unchanged.** The same `chat/*.js` sees the same HTTP and
  SSE wire, byte for byte where the client could notice.
- **Real effects.** Roc calls the host during a request. It does not return
  a list of work for the host to do.

## 2. Terms

- **The turn.** webbox runs one request handler at a time, under one lock.
  The Zig chat has no other locking; it relies on the turn.
- **Stream.** An open `GET …/<sid>/stream`, using Server-Sent Events. A
  **frame** is one event written into it; **backlog** frames are written by
  the handler that opens it, **live** frames by the host after the handler
  has returned.
- **Bus.** webbox's in-memory publish/subscribe, keyed by strings
  (`1_2/general`, `ntf:1`). A sender publishes a **blob**; each open stream
  has a subscriber, a 16-slot mailbox with its own copy, and a **render**
  that turns each blob into a frame.
- **Mounted.** The Roc chat runs inside angry-gopher's process, as
  angry-gopher mounts cobble-webbox's `codex_chat`.
- **Router.** The Roc chat's entry point (`chat/main.roc` `handle!`), for
  every `/chat` and `/channel` request.
- **Delegation.** An answer that names a route for Zig to serve; the host
  runs angry-gopher's Zig handler for it once the Roc call has ended.
- **Twin test.** A Zig function and the Roc replacing it, run on the same
  inputs, their answers and the files they leave compared.
- **Owners.** **CC** is the cloud session: it writes code on `claude/*`
  branches. **LC** is the local session on the box. **Box** is Steve and LC:
  merges, releases, production data. angry-gopher, zig-webbox and
  zig-metal-unikernel are box repos; CC never pushes their main branches.

## 3. Scope

**The router takes every `/chat` and `/channel` path** angry-gopher's
router.zig hands it (`chat_router.zig` `handle`). It parses the path into a
route (`chat/Route.roc`, pure, by the old Zig dispatch's rules) and runs the
prelude in Zig's order:
1. a static script under `/chat` (`/<name>.js`) goes to Zig, before the gate;
2. anyone not a member or the agent gets a 303 to `/login/full?next=`
   (`Host.member!`, asked only after the scripts, so a script's request does
   no identity reads);
3. every other request counts as presence, but a stream (judged by its
   route, not the path's spelling).

**Then it serves the route itself or delegates it.** `chat/main.roc`
(`is_action`, `is_page`, `is_own`, `act!`) serves: `/chat` and
`/chat/default`, `/chat/conversations`, `/chat/msg/<id>`, `/chat/links`, the
pages of `/chat/recent`, `/chat/images` and `/chat/code`; and in a DM or
channel the landing, a new topic, a topic's page, `/raw`, `/reactions`,
react, pin, unpin and send. Every read and every store write those routes
need is the host's, as a hosted function inside the call. A conversation or
topic the host cannot find, or that is not the member's, is handed back to
Zig, so its 404s are Zig's own.

**Still Zig, delegated:** docs, the reading list (`saved`) and search
(Zig for v1); every SSE stream (a topic's `/stream`,
`/chat/notifications`, `/chat/sidebar/stream`, the feeds' `/stream`);
uploads and download; and, behind hosted functions, the fan-out and every
store writer (append, `.count`, reactions, bookmarks, pins).

**Each job has one implementation at a time.** A piece moving to Roc lands
with a twin test against the Zig it replaces (§6); the old Zig stays as the
test's oracle while that is useful. There is no per-route switch in
production, and no route is served two ways: the branch moves route by
route, the box judges each milestone CC marks, and production takes the Roc
chat once, in one release, when it is mostly Roc. Going back is the
previous release, which loses only what a restart loses: presence, the rate
limit, and bus subscribers (whose clients reconnect and resume by index).

**The store's callers outside the chat move to Roc before the store does**:
login's welcome DM (`login.zig`), docs' post to chat (`docs.zig`) and admin
retire (`chat_retire.zig`), all through the router. Then the store's
writers move with only Roc callers left, and nothing needs a way into Roc
from outside a request. **Login in Roc keeps the secrets in Zig**:
passwords, the session secret and the cookie signing stay behind hosted
functions, and Roc runs the flow around them.

**Stays Zig, not yet planned:** logout, settings and API keys; the admin
tools but retire; the startup `.count` backfill.

**Never Roc: the host's hooks before the turn.** angry-gopher's `bodyLimit`,
uploader and `family` classify paths before the turn, so they stay Zig path
classifiers beside the Roc parser. router.zig's hooks test holds them to
the route each path parses to.

## 4. Rules

### R0. The toolchain

`gopher.elf` links the chat's Roc archive built for `x64v1elf`, so the
pinned nightly (`roc-version`) is in the production kernel's build and every
gate that builds it. There is no Zig fallback build. So:
- **The pin names a nightly that has passed the whole gate.** Moving it is
  a small change of its own, never folded into a chat change.
- Hosted symbols are **weak**: a missing host export links cleanly and jumps
  to address 0 at its first call. Every hosted function in
  `chat/platform/main.roc` needs its `roc_chat_*` export in
  `src/chat_abi.zig`.
- The records are laid out by hand in `src/chat_abi.zig`, their sizes
  asserted at compile time. Roc lays fields out by alignment, then by name;
  tag-union discriminants are alphabetical, so adding a tag renumbers the
  others.
- Hosted function names are unique per app (`roc_chat_` prefixed), so the
  chat can share a binary with another Roc app through `src/roc_hooks.zig`
  (README, "Combined with other webbox apps").

### R1. Roc runs only inside a call, one call at a time

Compiled Roc reaches memory through four context-free functions, so a call
beside another (Linux: a connection's thread) or inside another (metal:
every network pump during a write runs the kernel's turn and the streams'
render) would corrupt it. So:
- **The busy word** (`src/roc_abi.zig` `enter`): set by compare-and-swap as
  a call starts, refusing a call inside or beside one; the runtime's
  functions and every hosted function panic when no call is open.
- **No Roc in render or in any hook before the turn.** A topic stream's
  blob is its finished frame, and its render (`chat_sse.zig` `verbatim`)
  only copies it.
- **A delegated handler runs after the call.** `decide` (`src/chat_abi.zig`)
  copies the answer out and ends the call before it returns.
- **Writes inside a call are safe on metal**: a pump runs the kernel's turn
  and its fixed Zig render, never a handler, and the busy word refuses any
  other Roc.
- **A stream subscribes before it writes** (for S1): on metal a write pumps
  the network.

### R2. Two writers of one set of files

Until the store's writers move, Roc's routes and Zig's write the same files
in one process. The turn stops interleaving, not disagreement. So every
piece that moves has its twin, and the twins cover Zig's remaining writers
too (a docs post or welcome DM into Roc-written files). The format facts
that bite:
- the transcript separator `\n\n-------------\n` and its body-line escape
  (`chat/Codec.roc`);
- the block header `MSG_<sid>_<n>`, `from:`, `date:`, and `uid:` on newer
  blocks; every reader skips header lines it does not know;
- a reaction appended to a file that does not end in `\n` starts with one,
  so a torn line loses only itself;
- `users/<uid>/images.md` and `users/<uid>/code.md` have their own separator, and the code feed a lossy
  fence round-trip (`chat/Feeds.roc`);
- `.count`'s two lines and its two trust rules (`chat/Count.roc`);
- message numbers come from the block count, refused blocks included;
- Zig `write` (truncate) vs `replace` (temporary file then rename), site by
  site;
- `std.json.fmt` escapes `"`, `\` and bytes below 0x20 (lowercase
  `\u00xx`), writes DEL, `/` and non-ASCII raw, and writes a string that is
  not UTF-8 as an array of byte numbers (`chat/ZigText.roc`);
- numbers (ids, `.count` fields, the react form, `general<N>`, account
  folders, Range offsets) are one or more ASCII digits, overflow refused
  (`decimal.parseInt`). **No Roc code parses them with `U64.from_str`**,
  which takes `0x10`, `0b11`, `0o17` and `1e3`; ZigText has the digits-only
  parser.

### R3. A Roc crash is a 500

`roc_crashed` longjmps to the call's entry (`src/sljmp.zig`, architecture
code, the same on Linux and metal), the call's memory is dropped, and the
host answers 500 and logs the route; the next request is served. Effects
already performed stay performed, as when a Zig handler fails halfway,
which is why the send keeps Zig's order (§6.2). On metal a crash that stored
data would trigger on every request, so: checked arithmetic (`plus_try`,
`minus_try`) on every number from a file or a request (Roc's `+` crashes on
overflow), and no `crash` in chat code. `expect` never crashes.

### R4. Bytes that are not UTF-8

Roc's `Str` is UTF-8 by type; chat's bytes are not (old transcripts and
names, form fields, the path). So:
- **Bytes cross as `List(U8)`**: the path, bodies, header values, file
  contents, and the display name (a name decoded lossily would be written
  back with U+FFFD, and `onlyMemberNamed` would stop matching blocks from
  before `uid:`).
- **A new message that is not UTF-8 is a 400**, as Zig's.
- **Read-modify-write files are byte lines**, never lossy `Str`; `/raw` and
  `/reactions` pass bytes through. `Str.from_utf8_lossy` (one U+FFFD per
  run of bad bytes) is for display only.

### R5. Memory

What crosses into the Roc and out is copied each way. So:
- **Bytes the Roc does not read stay the host's.** A hosted function that
  reads or renders them holds them and answers only whether it has them,
  and the Roc answers `held` (kind 8). `/raw` and `/chat/links` work so.
- **Out of memory in a call is that call's crash**, a 500
  (`src/roc_abi.zig` `allocate`).
- **No arena over the request's**: angry-gopher hands the Roc the request's
  own allocator (`useRequest`), freed whole with the request. A host with
  its own arena (`use`) has it freed whole at each `end`.
- **A topic blob is the finished frame**, up to about 0.5-0.8 MiB for a
  64 KiB message by escaping alone, copied per subscriber, 16 slots each
  (S3 measures it).

### R6. Speed

Not a worry: `zig build codec-bench [-- <transcript>]` in
angry-gopher decodes a transcript in Zig and in Roc and gives time and
peak memory. A transcript is bytes, so the codec cannot use `Str`'s
builtins: a line is a `List.sublist` found by offset, never built a byte at
a time, and `List.prepend` in a fold is quadratic.

## 5. The platform

The chat has its own platform, `chat/platform/`, beside the TODO app's
`platform/`. Its host is angry-gopher's Zig, through `src/chat_abi.zig`;
`src/chat_hosted.zig` is the module angry-gopher imports (`roc_chat`, and
`roc_chat_metal` for `gopher.elf`), and `src/chat_route.zig` the route as
Zig reads it.

### 5.1 Request

`chat/platform/Chat.roc` `Request`: the path under `/chat` or `/channel` as
bytes, which area, and the method's number. The host keeps the request's
user and its time, read once inside the turn (angry-gopher
`request_time.Now`), and Roc asks for what it needs; a twin test hands both
sides one fixed `now`.

### 5.2 Answer

A flat record, `Answer`, whose `kind` says what the host
sends: Zig serves `route`, a 303, a status and body, a 405, already
answered (or failed) inside the call, a malformed form's 400, webbox's 404,
a 302, or a body around bytes the host holds. Chat.roc's comments and
constructors name each. `Route` is the delegated route flattened (family,
key, rest, sid, part, tail), its numbers named only in Chat.roc and
`src/chat_route.zig`; two routes are equal exactly when they go the same
place.

### 5.3 Hosted functions

They are `chat/platform/Host.roc`, answered by the
`Host` vtable `decide` is handed (`chat_abi.zig`; angry-gopher's is
`chat_router.zig` `Call`). Lists of records cross as flat lists of byte
strings, one decoder each side. **After a failure the host does nothing
more** for the call: every hosted function then answers its empty or
failed value and writes nothing, and the host returns the first failure,
a 500. What the platform still lacks (streams, files, generated layouts)
is in §7.

### 5.4 Frames: what is published is what goes out

Every blob on a chat bus key is exactly what a browser is sent, or its
`data:` payload. **`Forward`** (webbox `sse.forward`) writes
`data: <blob>\n\n`, for the per-user streams (`ntf:`, `sb:`, `rec:`, `img:`,
`code:`). **`Verbatim`** writes the blob as it is, for topic streams: a
message frame (`chat_frame.zig` `messageFrame`, `chat/Frame.roc`) or a
reaction frame (`reactionFrame`). A Roc publisher builds byte-identical
frames, with the same function for live and backlog, so a message reads the
same either way. The client decides `mine` (`from_uid` against the page's
`data-me`, the name only for blocks before `uid:`), and `cid` goes to every
viewer; only the sending tab shows "sent".

## 6. How it is held

### 6.1 The twins and the oracle

- **The pure modules**: `chat/twin.roc` puts them behind one test-only
  entry (`roc_chat_twin`, `src/twin_abi.zig`); angry-gopher
  `chat_twin_test.zig` calls each beside the Zig it replaces, on many
  inputs, and the bytes must match.
- **The routes**: angry-gopher `chat_actions_twin.zig` keeps the old Zig as
  the oracle, run when a test sets `chat_router.test_oracle`;
  `chat_actions_twin_test.zig` runs one scenario both ways on two copies of
  one tree at one fixed `now`, and every answer and file left must be the
  same.
- **The router**: angry-gopher `chat_route_twin.zig`, the old dispatch as a
  pure function, held to the Roc over a corpus; angry-gopher's route tests
  all run through the router.
- **What no request can reach** (the order of hosted calls, a failed store,
  a hostile message, a transcript gone since its topic was found): the
  scripted hosts in `src/chat_hosted.zig`'s tests, and angry-gopher
  `router_failures_test.zig`.
- **A crash and the busy word**: `src/chat_crash_test.zig`, over the planted
  crash `chat/test/crash.roc`.
- Each change is mutation-checked: every mutant killed, or named as
  equivalent.

### 6.2 One send, in Zig's order

`chat/main.roc` `send!` and `store!`: the conversation (`Host.send_conv!`;
a miss is Zig's); the method; the `X-Chat-Async` header (before the body);
the body to a message's limit; the form (`markdown`, `cid`); empty,
not-UTF-8 and hostile messages refused (`Host.hostile!`, whose 400 and
edge count are the host's); a DM's bookmark; then `Host.append!`, which is
Zig's `appendMessage`: number, date, block, `.count`, search, publish and
fan-out, building everything that can fail before it stores and failing
nothing after (a send that errors after storing makes the client resend a
duplicate); then 204 for an async sender, else a 303 to the topic.

### 6.3 Identity

**Mounted:** angry-gopher answers who is asking (`users.principalAuthorized`,
names, the roster, the agent rule) through hosted functions; Roc never
reads the auth root. **Standalone (I3)** needs the platform to cover what
angry-gopher does: `auth/<id>/{name,password}`; the `__Host-gopher_auth`
cookie, verified with `_session_secret` and its `.previous` pair; Bearer API
keys (`chat_client.py` uses them); the agent rule; the legacy cookie moves;
the upload gate, judged from the request head; `/login/full?next=`. The
TODO app's signed visitor cookie (README) is the mechanism to build on: the
same verification before `handle!`, answering for an account instead of a
visitor.

## 7. Work left

- **Sizes:** S under a day, M a few days, L about a week, XL two or more
  weeks. **Repos:** rw roc-webbox, ag angry-gopher, wb zig-webbox. Box
  repos take CC's `claude/*` branches, and the box merges them.
- **Done items** that code comments cite: A1-A4 the router, C1 the pure
  modules, C2 the twin kit, C3 the pages, C4 a topic's actions, C7 the
  feeds' pages, O1 the send, P7 the busy word, P9 a crash as a 500.

| # | item | repo | owner | size |
|---|---|---|---|---|
| P1 | The TODO app's ids parsed digits-only (`app/todo.roc` still uses `U64.from_str`, so `/api/todos/0x1/toggle` works) | rw | CC | S |
| P8 | Layouts generated by `roc glue`, asserted at compile time; the build checks every hosted `extern` has an export; each known-good nightly recorded with what it passed | rw | CC | M |
| C0 | Census of production data: invalid UTF-8 in transcripts and `auth/*/name`, number arrays already in `reactions.jsonl` and `users/<uid>/images.md` | — | box | S |
| C1 | The codec benchmark on the largest production transcript, on metal | ag | box | S |
| O2 | The conversation lookup in Roc: the participant check, the other account, the channel's members, the first topic, whether the topic exists, the titles | rw | CC | M |
| S1 | `Bus.publish!`; a `Stream` answer (subscribe first, then the head and the Roc's backlog frames, then the fixed `Forward` or `Verbatim` render) | rw | CC | S |
| S2 | Stream tests: subscribe before any write; exactly once (backlog xor live) under sends; `Last-Event-ID` and `?since=` resume; on Linux and metal | rw | CC (+ LC) | M |
| S3 | Mailbox worst case on metal (64 KiB of badly escaping markdown × 16 slots × subscribers), on the Zig chat first; a frame cap, sends past it refused | ag, rw | CC (+ LC) | S |
| C5 | Fan-out (notify, sidebar, recent, `users/<uid>/images.md`, `users/<uid>/code.md` with the fence scanner and its quirk) | rw | CC | L |
| C6 | Uploads (multipart, sniff, quota as `write`, lossy filename) and download, with `File` (stat, Range) and `TarGz` answers moved from `chat_upload.zig` and `chat_download.zig` | rw | CC | L |
| C9 | Docs and the reading list (`/chat/docs/*`, `…/<sid>/saved`), including docs' post to chat; search | rw | CC | L |
| C10 | Login in Roc, with its welcome DM; the secrets behind hosted functions | rw, ag | CC → box | L |
| C11 | Admin retire, through the router behind the admin gate | rw | CC | M |
| U2 | `appendMessage` split into hosted steps, so the send's whole order is Roc's | ag | CC → box | M |
| C8 | The store's writers (append, `.count`, reactions, bookmarks, pins) in Roc, once C9-C11 have made every caller Roc; with `File` effects under the data root, never the auth root: absent and failed distinct, per-call limits as Zig's, `write` vs `replace` per site | rw | CC | L |
| I3 | Standalone main with user support (§6.3) | rw | LC + CC | L |
| I4 | Markdown moved into webbox; search held by the platform; presence and the rate limit in a Roc model | wb, rw | CC → box | XL |

**Order:** v1 first (QUEUE, RC-v1); then O2, C5, C6, S1-S3, C9, C10, C11;
then U2 and C8 together; then I3, I4. P1, P8 and C0 any time.
