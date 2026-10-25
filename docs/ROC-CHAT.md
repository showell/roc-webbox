# Roc Chat: porting angry-gopher's chat to Roc on webbox

Status: **revised draft, after review** (§9 lists what the four reviews
changed), **updated for the new bus** (§5.4) and **for the Zig-side
cleanups** (§8, "Done in Zig"):
- since angry-gopher `e4a0f60`, a topic's bus blobs are finished SSE frames,
  built once at send and the same for every viewer, and the client decides
  `mine`. That removed the Splice protocol this draft had designed, and most
  of R1;
- since `f2601c4`, `3425d51`, `62155c5` and `838f357`, the Zig chat parses
  numbers strictly, refuses non-UTF-8 names and messages, records each
  message's author by uid, reads the clock once per request, and uses the
  names this doc uses. Several of the port's "match Zig's quirk" items are
  now plain rules instead.

Still open:
- LC's user support for the TODO app has landed (`20f6505`) as a signed
  visitor id, not accounts; §6.3 says what that leaves for a standalone
  chat.
- Steve is not bought in to an incremental cutover in production (§10, 1).
  §3, §7 and §8 still describe one; they are reworked once that is decided.

## 1. Goal

Port most of angry-gopher's chat (`zig-server/src/chat*.zig` and its
neighbours, about 6,800 lines) to a Roc app on the platform in this repo.

- **A webbox app.** The same Roc serves on webbox's Linux host and on bare
  metal. Production (lynrummy.com) is bare metal: zig-metal-unikernel builds
  `gopher.elf` from angry-gopher's checkout.
- **The same files.** The Roc chat reads and writes exactly the files the Zig
  chat does, so there is no migration, and going back is serving the Zig
  routes again.
- **The client is unchanged.** The same `chat/*.js` sees the same HTTP and
  SSE wire, byte for byte where the client could notice.
- **Real effects.** Roc calls the host during a request (`File.append!`,
  `Bus.publish!`). It does not return a list of work for the host to do.

## 2. Terms

- **The turn.** webbox runs one request handler at a time, under one lock.
  The Zig chat has no other locking; it relies on the turn.
- **Stream.** An open `GET …/<sid>/stream`, using Server-Sent Events.
  - A **frame** is one event written into it.
  - **Backlog** frames are written by the handler that opens the stream.
  - **Live** frames are messages sent after that. The host writes them after
    the handler has returned.
- **Bus.** webbox's in-memory publish/subscribe, keyed by strings
  (`1_2/general`, `ntf:1`).
  - A sender **publishes** a **blob**.
  - Each open stream has a **subscriber**, a 16-slot mailbox that gets its
    own copy.
  - The host calls the stream's **render** function to turn each blob into
    a frame. Since `e4a0f60` a topic stream's blob already is its frame, the
    same for every viewer, so its render only copies it through
    (chat_sse.zig `verbatim`).
- **Mounted.** The Roc chat runs inside angry-gopher's process, serving some
  of its routes, the way angry-gopher already mounts cobble-webbox's
  `codex_chat` (router.zig:30, :170).
- **Switch.** A per-route choice, read once at start, of Roc or Zig.
- **Owners.**
  - **CC** is the cloud session: it writes code on `claude/*` branches.
  - **LC** is the local session on the box: the bare-metal work.
  - **Box** is Steve and LC: merges, releases, production data.
  - angry-gopher, zig-webbox and zig-metal-unikernel are box repos; CC never
    pushes their main branches.

## 3. Scope

**The cut: mounted first, route by route.** The Roc chat runs inside
angry-gopher, which keeps every route the Roc chat does not serve yet. Each
route moves to Roc behind the switch, and moves back the same way.

That makes Zig a **permanent second writer of some chat files**, not a
temporary one. These callers stay in Zig and keep calling Zig's
`appendMessage`:
- login's welcome DM (login.zig:344-362);
- docs' post to chat (docs.zig:270-299);
- admin retire.

R2 deals with the consequences.

**Roc takes, in order (§8):**
1. Milestone 1: `raw`, `stream` and `send` for topics.
2. Then react, reactions, pin and unpin.
3. Then the page and its sidebar data, the empty and 404 pages,
   `/chat/conversations`, `/chat/msg/<id>`, default/resume, and new topic.
4. Then the cross-page fan-out and feeds (notify, sidebar, recent, images,
   code), uploads and download, and the recent, images, code and links pages.

**Supplied to Roc by angry-gopher's own Zig, while mounted.** These are
hosted functions over the existing modules. Nothing is moved, and there is
one copy of each:

| Function | angry-gopher module |
|---|---|
| Markdown | `markdown.zig`: render, render trusted, hostile check |
| Users | `users.zig`: exists, name, authorized roster, agent rule; only-member-named, for blocks from before `uid:` |
| Presence | `presence.zig`: mark, is online |
| Search | `search_index.zig`: note append |
| Counters | the chat counters `/admin/host` and `/version` read: edge rejects, fan-out failures, malformed channels, refused blocks |

**Stays Zig, not ported:**
- login, logout, settings and API keys;
- docs and the reading list: `/chat/docs/*`, plus `…/<sid>/saved`, which
  stays a Zig route under the mount;
- admin tools;
- the startup `.count` backfill;
- the search routes, for v1.

**Later, for a standalone Roc chat (I3):**
- markdown moved into webbox;
- search held by the platform;
- presence over a Roc model;
- LC's user support with angry-gopher's cookies and API keys.

## 4. Risks, in order

### R0. The toolchain in the production kernel

Mounted means `gopher.elf` links a Roc archive built for `x64v1elf`. That
puts a pinned Roc nightly into the box's kernel build, and into every gate
that builds it: metal-vmm's checks, sweeps and determinism runs.

The nightly is young, and churns in exactly the places this design leans on:
- it rejects the syntax this doc was first written in;
- `List.walk` is now `List.fold`;
- hosted symbols are **weak**, so a missing host export links cleanly and
  jumps to address 0 at its first call.

A bug found in month two means moving the pin across every hosted signature,
or working around it.

**Mitigation:**
- **T1 first:** a trivial Roc archive in angry-gopher and in `gopher.elf`,
  booted under QEMU. Measure build time, image size and gate cost, and get
  the box's agreement on the toolchain before any chat code.
- The layouts come from `roc glue`, never by hand, and every layout is
  asserted at compile time (P8).
- The build checks that every hosted `extern` has a host export.
- **More than one Roc app in a binary** (the chat beside Dog Park's Roc, or
  the TODO list) works through LC's `src/roc_hooks.zig`. The root exports
  the four runtime functions once, and hands each call to the app whose
  Roc call is open (`enter`/`leave`). Hosted function names must still be
  unique per app, so the chat's are prefixed (`roc_chat_file_read`, …).

### R1. Roc must never run outside a call, on either host

Until `e4a0f60` the Zig chat rendered markdown and computed `mine` inside
**render**, once per viewer per live message. Render still runs in two
places, though it now only copies bytes:
- **On Linux**, on each connection's own thread, outside the turn, alongside
  other streams and the handler (webbox bus.zig `serveKept`).
- **On metal**, inside the turn. Every network pump while a handler writes
  its response runs `streamTurn`, then `nextFrame`, then render
  (zig-metal-unikernel stream.zig:187, stream_turn.zig:102). That is
  **nested inside a live Roc call**, before its `end()`.

The glue (`src/roc_abi.zig`) has one arena, reset by `end()`. So a render
that called Roc would be concurrent corruption on Linux and re-entrant
corruption on metal. The cause is how compiled Roc reaches memory: through
four global functions with no context, so the host can only say which call
an allocation belongs to by global state.

**Decision:**
- **No Roc in render.** This now holds by construction: the publisher builds
  each frame inside the turn (§5.4), and render is fixed Zig that copies
  bytes.
- **Never Roc in the host's other hooks.** `bodyLimit`, `uploader` and
  `family` run before the turn on Linux, so they are host-only too. The same
  goes for any `between`.
- **A guard.** An atomic busy word set by compare-and-swap on entry
  (0 → 1), panicking if it is already set. It is asserted in `roc_alloc` and
  in every hosted function (P7). This catches both the concurrent case and
  the nested one; a plain "inside a call?" flag would pass both.
  - It builds on `roc_hooks`, which already panics on a runtime call outside
    any bracketed call. `roc_hooks` lets one app's call nest inside
    another's on purpose (`enter` keeps the previous app), so the busy word
    is per app, inside its own bracket.
- **Subscribe before writing.** The host subscribes as soon as `handle!`
  returns, before it writes the preamble. On metal a write pumps the network.

### R2. Two writers of one set of files

Roc and Zig both append transcripts, write `.count`, write bookmarks,
append to `users/<member>/images.md`/`users/<member>/code.md`, and publish on topic keys, in one process.
The turn makes that safe from interleaving. It does not make the two agree.

**Decisions:**

1. **One frame format on topic keys.** Done in angry-gopher `e4a0f60`
   (item Z1): Zig's `appendMessage` publishes the finished frame
   (chat_frame.zig `messageFrame`), and a reaction its `event: reaction`
   frame.
   - Zig callers (welcome DM, docs post) reach any topic stream in the one
     format.
   - A Roc publisher must build **byte-identical** frames for the same
     message: field order, JSON escaping (item 4 below), `cid` last and only
     when non-empty, HTML from the one markdown renderer. C2 compares them.
2. **One check that the two agree.** The differential harness (C2) runs Zig's
   own writers too (a docs post, a welcome DM) against Roc-written files.
   Every Zig-side change to these files after the port is a harness case.
3. **The format facts that bite** (the full list is in the format note):
   - the transcript separator `\n\n-------------\n` (16 bytes) and its
     body-line escape;
   - the block header `MSG_<sid>_<n>`, `from:`, `date:`, and since `3425d51`
     `uid:` (only on blocks written since; every reader skips header lines
     it does not know, so a block without it still reads);
   - a reaction appended to a file that does not end in `\n` starts with
     one, so a line torn by a stop loses only itself (`f2601c4`);
   - the `users/<member>/images.md`/`users/<member>/code.md` separator (17 bytes, a different one);
   - `.count`'s two lines and **two** trust rules:
     - `messageCount` trusts it only when the recorded size matches;
     - `lastMessage` trusts the offset when the last block's number is at
       least the count, and uses line 2's uid only on an exact match;
   - message numbers come from the **block count**, refused blocks included;
   - `users/<member>/code.md`'s lossy fence round-trip;
   - Zig `write` (truncate) vs `replace` (temporary file then rename), site
     by site (P4).
4. **What `std.json.fmt` writes.**
   - It escapes `"`, `\` and bytes below 0x20 (lowercase `\u00xx`).
   - It writes DEL, `/` and non-ASCII raw.
   - It writes a string that is not UTF-8 **as an array of byte numbers**.
5. **Parsing numbers.**
   - **Since `f2601c4` Zig parses digits only.** Message ids, `.count`
     fields, the react form's number, `general<N>`, account folders and
     Range offsets go through `decimal.parseInt`: one or more ASCII digits,
     nothing else, overflow refused. Before, Zig's `std.fmt.parseInt`
     accepted `+`, `_` inside (`topic_1_0` was message 10), and the port
     would have had to copy that.
   - **Roc's `U64.from_str` is a number-literal parser.** It accepts `0x10`,
     `0b11`, `0o17` and `1e3`, so it is still not the rule.
   - So **no Roc code parses an id, count, size or offset with `from_str`**:
     ZigText has the same digits-only parser (probe: `docs/roc-chat-probes/p7/chat/ZigText.roc`,
     to be narrowed to it).
   - Today's TODO app has the `from_str` bug (`/api/todos/0x1/toggle`
     works); P1 fixes it.

### R3. A Roc crash

Zig answers a failed handler with a 500 and goes on. A Roc `crash` or an
integer overflow (Roc's `+` crashes) calls `roc_crashed`, and today's host
panics.

On metal, `gopher.elf` restarts on failure, so a crash that **stored data**
triggers on every request (one poison block, an overflow in a recount) is a
crash loop, not one 500.

**Decision: a crash is a 500.**
- `roc_crashed` longjmps out to the call's entry, the per-call arena is
  dropped, and the host answers 500 and logs the route.
- The probe proved this on x86-64 Linux (`docs/roc-chat-probes/p4/hostjmp.zig`, using Roc's own
  `sljmp`). It is architecture code, not OS code, and P9 proves it on metal.
- The per-call arena is what makes it clean: Roc owns nothing that outlives
  the call. Effects already performed stay performed, as when a Zig handler
  fails halfway. That is why §6.2 orders the effects as Zig does.

**Also:**
- Checked arithmetic (`plus_try`, `minus_try`) on every number from a file
  or a request.
- No `crash` in chat code.
- A poison-block corpus in C2.
- A planted crash observed on `gopher.elf` (milestone 1's exit).

Note: `expect` never crashes. It is compiled out of the default build and
reported, not fatal, in a dev build.

### R4. Bytes that are not UTF-8

Roc's `Str` is UTF-8 by type. Chat's bytes are not guaranteed to be:
- transcript bodies are stored as sent;
- display names admitted any byte ≥ 0x80 until `f2601c4`; registration now
  refuses a name that is not UTF-8, but a name from before may still be one
  (C0 counts them);
- form fields are percent-decoded bytes;
- the multipart filename is decoded lossily on purpose (chat_upload.zig).

**Policy:**
- **Bytes cross as `List(U8)`:** request bodies, header values, file
  contents, and **the display name**.
  - A name is written into transcripts, reactions and feeds.
  - Decoding it lossily would write U+FFFD where Zig wrote the raw bytes.
  - Zig's `onlyMemberNamed`, which still credits blocks written before
    `uid:`, would then stop matching that author, after rollback too.
- **ZigText's JSON writer** emits Zig's byte-number array for non-UTF-8, so
  the files match.
- **A new message whose markdown is not UTF-8 is refused with a 400**, as
  Zig has done since `f2601c4`. Before, Zig stored it and its stream sent
  the client a number array where a string belongs. The upload filename
  stays lossy, as in Zig.
- **Read-modify-write files are handled as byte lines, never through
  lossy `Str`:** pins, and the bookmark compare. `/raw` and `/reactions`
  pass bytes through untouched.
- **`Str.from_utf8_lossy`** exists, and turns a *run* of invalid bytes into
  one U+FFFD. That is display only; the harness expects it.
- **The census (C0) counts** invalid UTF-8 in transcripts and in `auth/*/name`
  files, and number arrays already in `reactions.jsonl`/`users/<member>/images.md`.

### R5. Memory

- **The arena keeps its peak.** `roc_dealloc` frees nothing, and `end()`
  keeps the arena's capacity, so the largest call's memory is held for the
  process's life. On metal, out of memory in `roc_alloc` stops the machine.
  Zig handlers there get a 32 MiB heap and fail with a 500.
  **Fix (P7):**
  - reset with a retention limit;
  - give Roc a capped region on metal;
  - make out-of-memory a crash, so R3 turns it into a 500.
- **Reads.**
  - Zig reads transcripts and feeds whole (`.unlimited`); today's `File.read!`
    stops at 1 MiB. P4 sets per-call limits matching Zig's.
  - The store's buffer is handed to Roc without the second copy.
- **Bodies.**
  - On Linux a body can cross without a copy: a static refcount word (0) in
    an aligned prefix, which Roc never writes (probe: `p8/`).
  - On metal the body sits right after the HTTP head in one buffer
    (drain.zig:201), so it is copied, unless the box changes the drain.
  - A 100 MiB copy cost 55-170 ms in the probe.
- **Mailboxes.**
  - A topic blob is now the finished frame: markdown plus HTML, JSON-escaped.
    That is up to about 0.5-0.8 MiB for a 64 KiB message, by escaping alone;
    before `e4a0f60` the blob carried the markdown only.
  - The bus copies it per subscriber, up to 16 slots each. On Linux render
    makes no further copy; on metal `nextFrame` dupes it once more.
  - This is the same for the Zig chat today, so S3 measures it there first,
    on metal. Sends past a frame cap are refused.

### R6. Speed (low risk)

The probe decoded a 5 MB, 11,392-block transcript in Roc in 12-18 ms. The
same in Zig took 8.5 ms: about 1.2-1.5x, with identical results.
Concatenating 400 KB of strings took about 2 ms. C1 repeats this on the
largest production transcript, on metal, and reports peak arena bytes, not
only time.

## 5. The platform, extended

All types below are in the pinned nightly's syntax.

### 5.1 Request

```roc
Request : {
    method : Str,
    target : Str,                                   # path and query, as sent
    headers : List({ name : Str, value : List(U8) }),   # names lowercased
    body : List(U8),
    peer : Str,
    user : [Nobody, Member({ id : Str, name : List(U8) })],
    now : { unix_ms : I64, awake_ms : I64 },        # read inside the turn
}
```

**The request carries its time, read once, inside the turn.** Since
`62155c5` the Zig chat reads both clocks once as a handler starts
(`request_time.Now.read`) and hands that one reading to everything that
stamps or compares a time: message and reaction dates, a new DM's dated
topic, a doc's Recent entry, presence, the search rate limit. The host does
the same for Roc: it reads `now` after taking the turn, just before
`handle!`.
- It is not the host's `at_unix_ms`, which is read before the turn for the
  log line; with that, a request that waited for the turn would be stamped
  before one that went first.
- One reading per request means everything one request writes carries one
  time, and Roc needs no clock effect: the time is data, so the pure modules
  can take it and C2 hands both chats the same fixed `now` (Zig's
  `Now.at`).

### 5.2 Response

```roc
Response : [
    Bytes({ status : U16, headers : List({ name : Str, value : Str }), body : List(U8) }),
    Stream({ key : Str, preamble : List(U8), live : [Forward, Verbatim] }),
    File({ path : Str, content_type : Str, headers : List({ name : Str, value : Str }) }),
    TarGz({ name : Str, entries : List({ path : Str, as : Str }) }),
]
```

**Tag unions cross the ABI fine** (probe 2). The layout is the payload
first, then a `u8` tag. Discriminants are alphabetical, so adding a tag
renumbers the others. That is why the layout is generated and asserted
(P8), never hand-written.

Two layout facts:
- `RocList` is `{ptr, length, capacity}`, a different order from
  `RocStr`'s.
- A list of refcounted elements has a two-word header (count, then
  refcount).

What the host does with each:
- **`Stream`**:
  - subscribes to `key` right after `handle!` returns, before writing
    anything;
  - writes the head and the preamble (the backlog-size and backlog frames,
    which Roc built);
  - keeps the stream with the fixed `Forward` or `Verbatim` render (§5.4).
    Neither needs to know the viewer.
- **`File`**: stat; Range with 206/416 and an 8 MiB window; files up to
  4 MiB read whole; bigger ones streamed in 256 KiB pieces. This is
  chat_upload.zig's serving, moved into the platform.
- **`TarGz`**: chat_download.zig's archive. Entries are sorted, so it is
  reproducible.

Static assets never reach Roc: the host serves `/chat/<name>.js` from its
table before calling `handle!`.

### 5.3 Effects

All hosted functions are effectful (`=>`): the nightly refuses a pure one
(probe 3). So a caller is an effectful function, effects in loops use `for`
or `List.*_try!`, and pure modules (Page, Codec) take already-rendered HTML
as an argument.

| Module | Functions |
|---|---|
| `File` | `read!`, `read_at!`, `stat!`, `list!`, `append!` (answers the new size), `write!` (truncate), `replace!` (temporary file then rename), `make_dir!`, `remove!`, under the data root. Absent and failed are distinct answers; per-call size limits. **Never the auth root.** |
| `Bus` | `publish! : Str, List(U8) => {}` |
| `Random` | `bytes! : U64 => List(U8)` |
| `Markdown` | `render!`, `render_trusted!`, `hostile!` |
| `Users` | `exists!`, `name!`, `authorized!` (the roster), `only_member_named!` (blocks from before `uid:` only), `is_agent!` |
| `Presence` | `mark!`, `online!` |
| `Search` | `note_append!` |
| `Counter` | `bump!(name, detail)` |
| `Asset` | `src! : Str => Str` (the hashed URL) |

When mounted, angry-gopher supplies Markdown, Users, Presence, Search and
Counter over its own modules (§3).

**Lifetimes.** A Roc string can alias the buffer it was decoded from, so
anything the host keeps past `end()` is copied in, and anything it hands
Roc is copied into the call's arena. That covers publish blobs, the stream
preamble and response bodies.

### 5.4 Streams: what is published is what goes out

Since angry-gopher `e4a0f60`, every blob on every chat key is exactly what a
browser is sent, or its `data:` payload. There are two fixed renders, both
webbox/angry-gopher Zig, and neither runs any chat code:

- **`Forward`**: each blob is written as `data: <blob>\n\n`. This is webbox
  `sse.forward`, used by the five per-user streams (`ntf:`, `sb:`, `rec:`,
  `img:`, `code:`).
- **`Verbatim`**: each blob is written as it is. This is the topic streams'
  render (chat_sse.zig `verbatim`). The blob is one of:
  - a message frame (chat_frame.zig `messageFrame`):
    `id: N\ndata: {"index":…,"from":…,"from_uid":…,"at":…,"html":…,"markdown":…,"id":…}\n\n`,
    with `from_uid` only when the block records its author (`3425d51`), and
    `,"cid":…` before the closing brace when the send carried one;
  - a reaction frame (`reactionFrame`): `event: reaction\ndata: <sidecar line>\n\n`.

A Roc chat builds these frames inside the turn: at `/send` (and react), to
publish; and while handling a stream request, for its backlog, with the same
function, so a message reads the same live or replayed.

**The client decides `mine`, by account.** The frame no longer carries it.
Since `3425d51` chat.js sets `m.mine = m.from_uid ? (m.from_uid === ME) :
(m.from === ME_NAME)`: the page's `data-me` against the author's uid, as
reactions already did, and the name only for a message from before `uid:`
was stored. A rename no longer turns your own messages into someone else's.

**`cid` goes to every viewer, as before**, and is harmless now: the "your
message was sent" notice shows only for cids the tab itself sent (chat.js,
chat_compose.js `sentHere`).

## 6. The Roc chat

### 6.1 Layout

```
chat/                      the Roc app
  main.roc                 handle!: dispatch (chat.zig handle/topicRoute)
  Codec.roc                transcript blocks: encode, decode, escape (chat_codec.zig) (pure)
  Count.roc                .count: parse, format, both trust rules (chat_count.zig) (pure)
  Paths.roc                keys, validators, path builders, firstOf (chat_paths.zig) (pure)
  ZigText.roc              parseInt, std.json.fmt, trims, byte lines        (pure)
  Time.roc                 RFC3339 UTC, civil dates (timefmt.zig)           (pure)
  Feeds.roc                images.md / code.md entries, fence scanner       (pure)
  Page.roc                 page, chrome, sidebar JSON, escaping             (pure)
  Store.roc                messageCount, append, reactions, pins, bookmarks (effects)
  Fanout.roc               cross-page publishes per member                  (effects)
  Upload.roc               multipart, sniff, quota                          (mostly pure)
```

Pure modules test with `roc test`, which finds `expect`s through imports and
exits 1 on failure, using fixtures copied from the Zig tests.

### 6.2 One send, in Zig's order

1. **Gate.** The mount's router has already applied the chat gate (a member
   or the agent) and filled `user`.
2. **Form.** Decode the form. Then:
   - no `markdown` field: 400;
   - whitespace only: 400;
   - not UTF-8: 400 (R4, as Zig).
3. **Topic and membership.**
   - Validate the pair key and the topic id.
   - The DM's other half must **exist**: `Users.exists!`, an account
     directory. It needs no password; Zig opens DMs with password-less
     accounts on purpose.
   - Channel membership comes from the `.channel` file.
4. **Hostile check.** `Markdown.hostile!`. A hostile message is a 400, and
   the edge counter is bumped.
5. **Bookmarks.** DMs only: write them if changed (`File.write!`, as Zig's
   `write`).
6. **Author.** An empty author name is refused (`NoAuthor`). The block
   records the author's uid (`uid:`) as well as their name.
7. **Number.** `messageCount`, then the id `<sid>_<n>` in the request's
   spelling of the sid, as Zig does.
8. **Stamp and build.** The request's `now` gives the date. Then the block,
   then `Markdown.render!` once, then the message frame (§5.4). **Everything
   that can fail is built here, before the store.**
9. **Store.** `File.append!` the block. From here on **nothing fails the
   send**: a send that answered an error after storing makes the client
   resend, which is a duplicate.
   - `File.write!` the `.count`;
   - `Search.note_append!`;
   - `Bus.publish!`;
   - fan out (Zig's `fanoutCrossPage` while mounted; Roc's own from C5).
   - Each of these is best-effort: a failure bumps a counter, never fails the
     send.
10. **Answer.** 204 for `X-Chat-Async`, else 303 to the topic.

C2 injects failures at every step (as Zig's FailingAllocator tests do) and
checks that stored implies echoed, and that an error implies nothing stored.

### 6.3 Identity (depends on LC's user support)

**Mounted:** angry-gopher fills `user` from `users.currentUserID` and
`getUserName`, after its own prelude (legacy cookie moves, the gate). Roc
never reads the auth root: names, the roster and the agent rule come through
`Users`.

**Standalone (I3) needs LC's user support to cover everything angry-gopher
does:**
- `auth/<id>/{name,password}`;
- the `__Host-gopher_auth` cookie, verified with `_session_secret` and its
  `.previous` pair;
- Bearer API keys, which `chat_client.py` uses;
- the agent rule;
- the legacy cookie moves;
- the upload gate, judged from the request head;
- `/login/full?next=`.

**What LC's work gives (`20f6505`), checked:**
- **Its shape:** `Http.Request.user : Str`, the visitor's id, 16 hex digits,
  and a new one on a first visit. §5.1's `user` is a tag
  (`Nobody`/`Member`) with a name; the chat needs that.
- **Verified before `handle!`:** yes. The host reads webbox's
  `signed_cookie.visitor` before the body, and answers with its Set-Cookie
  when one is due. The site secret is made once in the app's auth folder.
- **angry-gopher's accounts:** no. A visitor is anonymous, with no name, no
  password, no API key and no agent rule, so none of the list above is
  covered yet. The signed-cookie mechanism is the part I3 builds on: the
  same verification before `handle!`, answering for an account instead of
  a visitor.

## 7. Milestone 1: one topic, live, on metal

Mounted in angry-gopher behind the per-route switch.
- **Roc serves only** `GET …/<sid>/raw`, `GET …/<sid>/stream` and
  `POST …/<sid>/send`.
- **Zig serves everything else**, including the page, whose JS opens the
  Roc stream.
- **Roc owns:** Codec, Count, ZigText, Time, the bookmark write, append and
  `.count`, the message frame, and the stream with backlog and resume.
- **angry-gopher supplies:** Markdown, Users, Presence, Search, Counter, and
  its fan-out.

**Exit criteria:**
1. C2 clean on these routes, including a docs post and a welcome DM landing
   while a Roc stream is open.
2. A planted Roc crash on `gopher.elf` under QEMU answers 500, is logged with
   its route, and does not loop.
3. Peak arena bytes on the largest production transcript, on metal.
4. `gopher.elf` build time and size with Roc.
5. Steve using it on one DM.

This proves R0-R5 and the mount before the other routes are built.

## 8. Work items

Each item lands with tests, and the chat items with C2 cases.
- **Sizes:** S is under a day, M a few days, L about a week, XL two or more
  weeks.
- **Repo:** rw is roc-webbox, ag is angry-gopher, wb is zig-webbox, zmu is
  zig-metal-unikernel.
- Box repos take CC's `claude/*` branches, and the box merges them.

### First: prove the toolchain

| # | item | repo | owner | size |
|---|---|---|---|---|
| P1 | Bytes cross as `List(U8)` (body, header values); the TODO app's ids parsed byte-wise, not by `from_str` | rw | CC | S |
| P8 | Pin the nightly; the build checks it (**done by LC**, `roc-version`). Layouts generated by `roc glue`, asserted at compile time. The build checks every hosted `extern` has an export (weak symbols) | rw | CC | M |
| C0 | Census of production data (R2, R4, R5 lists) | — | box | S |
| T1 | A trivial Roc archive linked into angry-gopher and `gopher.elf`, booted under QEMU; build time, size, gate cost; the box agrees the toolchain | ag, zmu | box + CC | M |

### The platform

| # | item | repo | owner | size |
|---|---|---|---|---|
| P2 | `Request` (§5.1); the zero-copy body on Linux; measure the copy on metal | rw | CC | M |
| P3 | `Response` (§5.2) `Bytes` | rw | CC | S |
| P4 | `File` effects: `write` vs `replace` per site, per-call limits, no double copy, absent ≠ failed | rw | CC | M |
| P5 | `now` in the request (read in the turn), `Random`, `Counter`, `Asset` | rw | CC | S |
| P6 | `File` and `TarGz` responses (moved from chat_upload/chat_download) | rw | CC | M |
| P7 | The busy word (CAS) per app inside its `roc_hooks` bracket, checked in `roc_alloc` and in every hosted function; the arena with a retention limit; a capped region on metal | rw | CC | M |
| P9 | A crash is a 500: `roc_crashed` longjmps to the call's entry; proved on Linux and on metal | rw | CC (+ LC on metal) | M |
| U1 | The mounted hosted functions over angry-gopher's modules (Markdown, Users, Presence, Search, Counter) | ag | CC → box | M |

### Done in Zig

Fixes made in angry-gopher on their own merit, each also something the port
no longer has to copy. All are on `claude/great-wright-i7aste`; the box has
merged Z1 (master `c9ac283`), and Z2-Z5 await its merge.

| # | commit | what changed | what the port no longer copies |
|---|---|---|---|
| Z1 | `e4a0f60` | Frames built once at send, the same for every viewer; the client decides `mine`; reactions as finished frames; the "sent" notice only in the sender's tab | A per-viewer render; the Splice protocol |
| Z2 | `f2601c4` | Torn-reaction guard; digits-only `decimal.parseInt`; UTF-8 checked for new names and messages; the read-only routes answer only GET and HEAD; the self-DM lists its member once (`ConvMeta.dm`); the store's `Topic` is `TopicAddress` | `parseInt`'s `+` and `_`; storing non-UTF-8; doubled feed entries |
| Z3 | `3425d51` | `uid:` header on new blocks; `from_uid` in the frame; `mine` and author lookups by uid | Name matching, except for old blocks |
| Z4 | `62155c5` | The clock read once per request, inside the turn (`request_time.Now`), passed to everything that stamps or compares a time | A clock effect; a fake clock for the harness |
| Z5 | `838f357` | Names: "topic" for session in the code (`listTopics`, `transcriptPath`, `readTranscript`, `validTopicID`, `lastViewedTopic`, `pinnedTopics`, …); `firstTopic` (the conversation's pick, one pure `firstOf`) and `resumeTopic` (the viewer's last view, then that pick, then today); `at` for a message's time; chat_store's re-exports gone, each name imported from its module | Translating the code's words; the modules map one to one onto §6.1's |

Not changed, on purpose: the disk keeps `<conv>/sessions/<sid>.md`,
`<uid>/last-sessions/<conv>` and `<uid>/pinned-sessions/<conv>`; `sid` stays the topic id's name, as in URLs and JSON;
the transcript header stays `date:`; and `.count` still has two trust rules
(R2, 3), which Count.roc copies as they are.

### Streams

| # | item | repo | owner | size |
|---|---|---|---|---|
| S1 | `Bus.publish!`; the `Stream` response; the `Forward` and `Verbatim` renders | rw | CC | S |
| S2 | Tests: subscribe before any write; exactly once (backlog xor live) under sends; `Last-Event-ID` and `?since=` resume; on Linux and metal | rw | CC (+ LC) | M |
| S3 | Mailbox worst case on metal (64 KiB of markdown that escapes badly × 16 slots × subscribers), measured on the Zig chat first, since it publishes the same frames now; the frame cap | ag, rw | CC (+ LC) | S |

### The chat in Roc

| # | item | repo | owner | size |
|---|---|---|---|---|
| C1 | Codec, Count (both trust rules), Paths, ZigText, Time, with the Zig fixtures; benchmark on the largest transcript with peak arena bytes | rw | CC | XL |
| C2a | Zig side of the harness: a fixed `Now` per request (the seam exists since `62155c5`), seeded randomness, and a persistent Hub that drains kept streams | ag | CC → box | M |
| C2b | Skeleton mount reached by test requests, with the per-route switch | ag | CC → box | M |
| C2c | The diff: both chats as separate processes on copies of one tree; trees sorted and compared with mtimes dropped; uploads renamed by order of creation; tars unpacked; leftover `~*.tmp` files are findings; fault injection; a poison-block corpus; mixed-case sids; GETs included (page views write bookmarks) | rw | CC | XL |
| M1 | **Milestone 1** (§7): raw, stream, send | rw, ag | CC; box flips | L |
| C4 | React, reactions, pin, unpin | rw | CC | M |
| C3 | Page, chrome (matches Zig's settings page byte for byte; a harness case), sidebar JSON, 404 and empty pages, conversations, msg (302), default/resume, new topic (with the `general<N>` announcement) | rw | CC | XL |
| C5 | Fan-out ported (notify, sidebar, recent, `users/<member>/images.md`, `users/<member>/code.md` with the fence scanner and its quirk), replacing angry-gopher's | rw | CC | L |
| C6 | Uploads (multipart, sniff, quota as `write`, lossy filename) and download | rw | CC | L |
| C7 | Recent (including doc rows from docs_store), images, code and links pages | rw | CC | L |

### Standalone, after the mounted chat serves everything

| # | item | repo | owner | size |
|---|---|---|---|---|
| I3 | Standalone main with LC's user support (§6.3) | rw | LC + CC | L |
| M2 | Markdown moved into webbox; search held by the platform; presence and the rate limit in a Roc model (feasible; needs ownership beyond the per-call arena) | wb, rw | CC → box | XL |

**Order:**
1. P1, P8, C0, T1.
2. P2-P5, P7, P9 and U1, each booting on metal, with C1's Codec, Count and
   ZigText started in parallel.
3. S1-S3 (Z1-Z5 are done).
4. C2a-c.
5. M1, flipped in production.
6. C4, C3, C5, C6, C7, each flipped route by route.
7. I3, M2.

**Flips.** The switch is read at start, so a flip is a restart, not a
release. Changing the Roc code is a release, through the box's gates.

**Rollback.** Flip the route back. These are lost, as on any restart:
- presence (came-online fires again);
- the rate limit;
- bus subscribers, whose clients reconnect and resume by index.

Nothing Roc writes is unknown to Zig, which C2 proves.

## 9. What the reviews changed

Four reviews attacked the first draft: streams and concurrency, data
fidelity, Roc feasibility (probes built with the pinned nightly), and scope
and plan.

**Three of the four found, independently, that Zig's welcome DM and docs
post would keep publishing the old blob format onto topic keys that Roc
streams read.** That became R2's first decision and item Z1.

| Draft | Revised |
|---|---|
| Bare metal "would hide" the render bug | It would be **re-entrant**: metal renders inside the handler's writes. The guard is a CAS busy word |
| Roc's File effects read `auth/` | A `Users` module; Roc never sees the auth root |
| DM membership checked a password | It checks that the account exists |
| Presence in a new `Memo` map | angry-gopher's presence; a new map would split it in two |
| Search held by the platform | angry-gopher's index; a second index would keep retired DMs searchable |
| A crash stops the server | A crash is a 500 (longjmp, proved on Linux); unhandled, it loops on metal |
| Records are safer than tag unions | Both are compiler choices; layouts are generated and asserted |
| `Markdown.render : Str -> Str` | Effectful, because the nightly refuses pure hosted functions |
| `U64.from_str` differs from parseInt only at the edges | It accepts hex, binary, octal and exponents; ZigText parses bytes |
| `at_unix_ms` as the clock | Read before the turn; dates would run backwards |
| A 1 MiB read cap | Per-call limits as Zig's |
| The arena reset kept capacity | A retention limit and a capped region |
| Send steps missed Zig's rules | Order and "stored is done" restored |
| The display name crosses as `Str` | It crosses as `List(U8)` |
| Cutover was one flag, all at once, at the end | A per-route switch read at start, milestone 1 first, metal from day one |
| Owners and repos unstated | Owner and repo for every item |
| Sizes | C1, C2 and C3 are XL; I3 is L |

### Since the reviews

- **The bus (angry-gopher `e4a0f60`).** Steve asked what made the bus a
  problem for Roc and not for Zig. The answer was the per-viewer render
  callback, which Zig could run concurrently and nested because it is handed
  its allocator, and compiled Roc cannot. Making that render a plain copy
  was worth doing in Zig on its own: markdown rendered once per message
  instead of once per viewer, no chat code outside the turn, one stream
  mechanism, and the "sent" notice bug fixed. It replaced the Splice
  protocol (old §5.4), the `ctx`, and item Z1's design.
- **The Zig cleanups (Z2-Z5).** Steve asked what else on the Zig side was a
  flaw worth fixing anyway. Each fix removed a rule the port would have had
  to reproduce exactly: lenient `parseInt` (R2, 5), non-UTF-8 messages
  stored (R4), authors known only by name (§5.4), clocks read wherever a
  date was needed (§5.1, and the `Clock` effect is gone), and names that
  differed between the UI, the code and this doc.

## 10. Questions for Steve

1. **Mounted first, route by route, starting with milestone 1?** Steve: not
   bought in to an incremental cutover, at least in production. Open: what
   replaces it (for example, the Roc chat proved against a copy of the data
   and switched over whole), and whether mounting still makes sense without
   route-by-route flips. §3, §7 and §8 are reworked once decided.
2. ~~Z1, one producer of topic blobs?~~ Done (`e4a0f60`), merged by the box.
3. **Roc in `gopher.elf` (T1)?** The pinned nightly becomes part of the
   production kernel's build.
4. ~~Refuse a new message that is not UTF-8, with a 400?~~ Done in Zig
   (`f2601c4`); the Roc chat matches it. C0 still counts old non-UTF-8
   transcripts and names.
5. ~~`cid` to every viewer, or only the sender?~~ Settled by `e4a0f60`: it
   still goes to every viewer, and the client shows "sent" only for its own.
6. **Docs, the reading list and the search routes stay Zig for v1?**
