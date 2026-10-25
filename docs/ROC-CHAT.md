# Roc Chat: porting angry-gopher's chat to Roc on webbox

Status: **draft for review**. It assumes the shape of LC's user support for
the TODO app (§5.3), which has not landed yet, and will be revised when it
does.

## 1. Goal

Port most of angry-gopher's chat (`zig-server/src/chat*.zig` and its
neighbours, about 6,800 lines) to a Roc app on the platform in this repo.
The requirements:

- **It is a webbox app.** Zig hosts it on webbox's Linux host, and LC hosts
  it on bare metal, as the TODO app is hosted today.
- **It reads and writes exactly the files the Zig chat does.** No migration
  step, and **rollback is switching back**: both implementations work on the
  same tree.
- **The client is unchanged.** The same `chat/*.js` is served, and it sees
  the same HTTP and SSE wire.
- **The effects are real effects.** Roc calls the host during a request
  (`File.append!`, `Bus.publish!`). It does not return a list of things for
  the host to do.

Everything the Zig chat does is mapped in three research notes made for this
doc, and this design is built on them: the route table, the byte-level file
formats, and the parts that are not request-in/response-out.

## 2. Scope

**Ported to Roc (v1):**
- Direct messages and channels.
- Topics: new, the default, resume.
- The conversation page and its sidebar data.
- Send, the per-topic stream, `raw`, reactions, pin/unpin.
- Uploads: store and serve. The topic download.
- The cross-page feeds and their streams: notifications, sidebar, recent,
  images, code, links.
- Presence.
- `/chat/conversations` and `/chat/msg/<id>`.

**Stays in Zig, called by Roc through the platform (§4):**
- Markdown rendering and the hostile-input check.
- The search index.
- gzip/tar for the download.
- Serving the embedded JS.
- Everything about connections, streams and bodies.

**Out of scope for v1 (stays in angry-gopher's Zig):**
- Login, logout, settings and API keys. Identity reaches Roc as a uid (§5.3).
- Docs and the reading list (`/chat/docs/*`, `/saved`).
- Admin tools: retire, admin search, host counters.
- The startup `.count` backfill. It is an optimization; the counts recount
  on a size mismatch anyway.

## 3. The riskiest pieces, in order

### R1. Live streams run render code outside the turn (decided, §4.4)

**Terms.**
- A **stream** is an open `GET …/<sid>/stream` (Server-Sent Events).
- A **frame** is one event written into it.
- **Backlog** frames are written by the handler that opens the stream.
- **Live** frames are the messages sent after that, which webbox writes long
  after the handler returned.
- A sender **publishes** a **blob** on the bus. Each open stream's
  **subscriber** (a 16-slot mailbox) gets a copy. webbox calls the stream's
  `render(ctx, blob)` to turn the blob into that viewer's frame.

**The hazard.** On Linux, `render` runs on each connection's own thread,
outside webbox's one-handler-at-a-time **turn**, alongside other streams and
whatever handler holds the turn (webbox `bus.zig` `serveKept`). The Zig chat
renders markdown and computes `mine` there, once per viewer per message.

If `render` called Roc, Roc would run concurrently. The glue
(`src/roc_abi.zig`) has one global arena that `end()` resets, so that is
memory corruption. Any effect Roc made there would also race the handlers.
Bare metal (one loop, `nextFrame`) would hide the bug.

**Decision.** No Roc code runs outside the turn. §4.4 gives the protocol: the
publisher builds the frame once, inside the turn, and `render` becomes a
fixed Zig splice that knows nothing about chat. A debug check in the glue
(item P7) panics if Roc is entered outside a call.

### R2. Byte-for-byte file compatibility, including the Zig quirks

The formats are simple text, but Zig made many small choices that the files
now record. The format note lists them. The ones that bite:

- The transcript separator `\n\n-------------\n` and its body-line escape.
- The `.count` sidecar's two lines, and its "trust only if the size matches"
  rule.
- `images.md`/`code.md`'s **different** 18-byte separator, and `code.md`'s
  lossy fence round-trip.
- `std.json.fmt` escaping. It escapes only `"`, `\` and control bytes, with
  lowercase `\u00xx`. It writes non-ASCII and `/` raw. It writes a non-UTF-8
  string as **an array of numbers**.
- Zig `parseInt`, which accepts `+`, `-0` and interior `_` (`1_0` is 10).
- Different trim sets at different sites.
- Bytewise sort orders.
- Message numbers come from the **block count**, refused blocks included.

**What saves us:**

1. **The file effects go through `webbox.store`.** So the store's rules
   (case-insensitive lookup, FAT names, path limits, `replace` via a
   temporary file, `append` at the stat size, durability before the response)
   are the same code for both implementations. Roc never reimplements them.
2. **A differential harness (item C2) is the oracle.** It replays one script
   of requests against the Zig chat and the Roc chat, each on a copy of the
   same data tree, with the clock and randomness fixed. Then it compares the
   two trees byte for byte, and the responses after normalizing.

Every chat item lands with harness cases. A copy of production data is run
through it before cutover.

### R3. Roc strings must be valid UTF-8, and the data need not be

Roc's `Str` is UTF-8 by type. The bytes chat handles are not guaranteed to be:
- transcript bodies are stored as sent;
- display names allow any byte ≥ 0x80 without validation;
- form fields are percent-decoded bytes.

**Today's platform has this bug:** `src/roc_abi.zig` hands the request body
to Roc as a `Str` without checking it (item P1 fixes it).

**Policy:**
- Bytes from outside (request bodies, file contents) cross into Roc as
  `List U8`.
- Roc decodes with `Str.from_utf8`, and decides per site:
  - a **new** message or field that is not UTF-8 is refused with a 400. This
    is a deliberate change: Zig stores it, and its stream then shows broken
    JSON;
  - **existing** files are decoded lossily for display, never rewritten.
- A census (item C0) counts the invalid bytes in production data before this
  is final. If it finds none, the lossy path is a formality.

### R4. A Roc crash stops the whole server

Zig answers a failed handler with a 500 and goes on. A Roc `crash`, an
integer overflow or a failed `expect` calls `roc_crashed`, and the host
panics. There is no safe way to unwind out of Roc. On bare metal that is the
machine.

**Mitigation:**
- No `crash` in chat code.
- Checked arithmetic on every number that comes from a file or a request
  (`U64.from_str` results, counts, offsets, sizes).
- The harness fuzzes requests and files (item C2).
- The crash message is logged with the route.

A nightly compiler is also a risk of its own. It has already cost a reserved
word (`has`). The archive is pinned to one nightly, as dog-park pins its own.

### R5. Identity and the shared process

Chat writes files other parts of angry-gopher also write:
- the login's welcome DM goes through `appendMessage`;
- docs/post appends a message;
- retire deletes topics;
- `next-id.txt` and the user dirs are shared.

The format note is explicit: **two processes must never write one tree at
once**. Appends are stat-then-pwrite, and nothing locks.

**Decision:** the Roc chat runs **in angry-gopher's process**, mounted at
`/chat` and `/channel` the way angry-gopher already mounts cobble-webbox's
`codex_chat` (router.zig:30, :170). That gives it:
- the same turn;
- the same bus, so login's `user-arrived` and the welcome DM reach Roc's
  streams;
- the same identity, because angry-gopher passes the uid in.

A **standalone** main, with LC's user support, comes after (item I3).

### R6. Big bodies and big files

- **Uploads arrive whole, up to 101 MiB.** Handing that to Roc as a
  `List U8` costs a copy, unless the host puts Roc's refcount word in front
  of webbox's body buffer. Item P2 measures the copy, and decides whether
  webbox reserves the word.
- **Large files are not returned through Roc.** Uploads are served with
  Range and 4 MiB-chunked streaming. That stays in the host: Roc answers a
  `File` response naming the path (§4.2), and the host does the rest.

### R7. Per-request cost in Roc

Opening a stream decodes the whole transcript, and so does every recount.
Zig does the same, but Roc's `Str` and `List` work, refcounts and the
per-call arena may be slower or use more memory, which matters on metal.

Item C1 benchmarks decoding the largest transcript in production data before
the routes are built on it.

## 4. The platform, extended

### 4.1 Request

```roc
Request : {
    method : Str,
    target : Str,              # path and query, as sent
    headers : List { name : Str, value : Str },   # names lowercased
    body : List U8,            # bytes; Roc decodes (R3)
    at_unix_ms : I64,          # the request's clock (webbox Bus.at_unix_ms)
    peer : Str,                # client address, after the trusted proxy
    user : [Nobody, Member { id : Str, name : Str }],   # §5.3
}
```

Header values that are not UTF-8 are dropped, and the drop is counted.

### 4.2 Response

One record with a `kind` byte rather than a tag union. A record's C layout
is known (fields by alignment, then name); a tag union's would have to be
pinned per nightly.

| kind | meaning | host does |
|---|---|---|
| `bytes` | `status`, `headers`, `body : List U8` | responds |
| `stream` | `key`, `preamble : List U8` (head written by the host, then this: backlog-size and backlog frames), `live : Verbatim \| Splice` | subscribes to `key` **before the turn is released**, writes the preamble, keeps the stream (§4.4) |
| `file` | `path` (under the data root), `content_type`, `headers` | stat, Range/206/416, whole read up to 4 MiB, else chunked; as chat_upload.zig does today, moved into the platform |
| `tar_gz` | `name`, `entries : List { path, as }` | builds the archive, as chat_download.zig does |

Static assets never reach Roc: the host serves `/chat/<name>.js` from its
embedded table before calling `handle!` (§4.6).

### 4.3 Effects (hosted functions)

All are called during `handle!`, inside the turn.

| module | functions | over |
|---|---|---|
| `File` | `read!`, `read_at!`, `stat!`, `list!`, `append!` (answers the new size), `write!`, `replace!`, `make_dir!`, `remove!` | `webbox.store`. Absent and failed are distinct answers, as today. |
| `Bus` | `publish! : Str, List U8 => {}` | the process's Hub |
| `Clock` | `awake_ms! : {} => U64` (the rate limit's clock; wall time is `at_unix_ms`) | host |
| `Random` | `bytes! : U64 => List U8` | host `io.random` |
| `Memo` | `get! : Str => [Some (List U8), None]`, `put!`, `drop!` | a host-held map, lost on restart |
| `Markdown` | `render : Str -> Str`, `hostile : Str -> [Ok, Hostile Str]` | angry-gopher's markdown, moved into webbox (item M1) |
| `Search` | `note_append!`, `words!`, `messages!`, `rebuild!` | angry-gopher's search index, held by the host |

About `Memo`: presence, the search rate limit and any later cache are the
chat's only cross-request state. A small host-held map is the least novel
way to keep them. The alternative is a Roc model threaded through `handle!`
(`init! : {} => Model`, `handle! : Model, Request => (Model, Response)`).
That is the better long-run shape, and a good test of Roc owning state, but
it is not needed to ship.

### 4.4 Streams without Roc outside the turn (R1)

Two live render modes, both fixed Zig in the platform:

- **`Verbatim`**: each blob is written as `data: <blob>\n\n`. This is
  webbox's `sse.forward`, used by the five per-user streams (`ntf:`, `sb:`,
  `rec:`, `img:`, `code:`) unchanged.
- **`Splice`**: for the per-topic stream.
  - A blob is `author ++ "\n" ++ before ++ "\x00" ++ after`.
  - The frame is `before ++ ("true" if ctx == author else "false") ++ after`,
    where `ctx` is the viewer's display name, as today's `mine` is.
  - A blob with no NUL after its first line is written as-is after that line:
    a reaction's frame is the same for every viewer.
  - NUL never appears in the JSON, which escapes control bytes, so the split
    is unambiguous.

So at `/send`, Roc renders the markdown **once** and builds the whole SSE
frame. That is `id: N\ndata: {"index":…,"from":…,"at":…,"html":…,`
`"markdown":…,"id":…,"mine":` + gap + `,"cid":…}\n\n`, field order as
chat_sse.zig `emitWire`. Roc publishes it with the author's name in front.
Backlog frames are made by Roc while it handles the stream request, with
`mine` filled in directly.

**What this changes:**
- The client: nothing. Frames are what it gets today.
- The bus blobs: they become finished frames. They are in memory only, so no
  file changes.
- Cost: markdown is rendered once per message, not once per viewer.
- Mailbox memory: a blob is now about markdown plus HTML. That is at most a
  few hundred KB for a 64 KiB message, times up to 16 slots per open tab.
  Item S3 measures it against the metal memory budget.

**Atomic open.** Today the backlog read and the subscribe happen in one
turn, so each message lands in the backlog or live, never both, never
neither. The `stream` response keeps that only because the host subscribes
**before releasing the turn**. That is a platform rule, with a test that
sends while streams open (item S2).

### 4.5 Markdown

Moved, not ported. `markdown*.zig` (about 1,850 lines plus the gold corpus)
moves from angry-gopher into webbox as a pure module. angry-gopher then
imports it from there with no behaviour change, and the platform exposes it.
Both chats render with **one** implementation while they coexist.

A Roc port of the dialect is possible later, with the gold corpus as its
oracle. It is not on the path.

### 4.6 The embedded JS

The 30 `chat/*.js` files stay in angry-gopher, the one source, until cutover
is final. The Roc chat's build embeds them by path, as cobble-webbox embeds
its proofs from a sibling checkout.

The host serves them with webbox `http.serveEmbedded` (ETag, `?h=`
immutable caching, 304), before Roc. Roc gets `Asset.src : Str -> Str`, the
hashed URL, for the script tags it writes into pages.

## 5. The Roc chat

### 5.1 Layout

```
chat/                      the Roc app
  main.roc                 handle!: dispatch (chat.zig's handle/topicRoute)
  Codec.roc                transcript blocks: encode, decode, escape    (pure)
  Count.roc                .count sidecar: parse, format; recount rule  (pure)
  Paths.roc                keys, validators, path builders              (pure)
  ZigText.roc              Zig-compatible parseInt, std.json.fmt, trims (pure)
  Time.roc                 RFC3339 UTC, civil dates (timefmt.zig)       (pure)
  Feeds.roc                images.md / code.md entries, fence scanner   (pure)
  Page.roc                 the page, chrome, sidebar JSON, escaping     (pure)
  Store.roc                messageCount, appendMessage, reactions, pins (effects)
  Fanout.roc               cross-page publishes per member              (effects)
  Presence.roc             over Memo                                    (effects)
  Upload.roc               multipart, sniff, quota                      (mostly pure)
src/                       the platform host (§4)
```

Pure modules are most of the code, and test without a host: Roc `expect`,
plus fixtures copied from the Zig tests.

### 5.2 One send, end to end

1. **Turn.** webbox takes the turn, the router finds `/chat/c/1_2/general/send`,
   and angry-gopher's mount calls `handle!` with `user = Member {id: "1", name: "Steve"}`.
2. **Checks.** Roc decodes the form, then validates the pair key, the topic id
   and membership. The membership check reads `auth/2/password` via
   `File.stat!`.
3. **Bookmarks.** DMs only: `File.write!` the bookmarks, if changed.
4. **Hostile check.** `Markdown.hostile`. A hostile message is a 400.
5. **Number the message.** `messageCount`: `File.stat!` the `.md` and
   `File.read!` the `.count`. If the sizes don't match, recount the
   transcript's blocks.
6. **Build the echo.** The block bytes, then `Markdown.render` once, then the
   splice blob. The echo is made before the store, as Zig makes it.
7. **Store.** `File.append!` the block (it answers the size), then
   `File.write!` the `.count`.
8. **Search and publish.** `Search.note_append!`, then
   `Bus.publish!("1_2/general", blob)`.
9. **Fan out.** For each member: notify, sidebar (first message only),
   recent, plus `images.md`/`code.md` appends.
10. **Answer.** 204.

The turn is held throughout, so no other handler interleaves, as in Zig.

### 5.3 Identity (depends on LC's user support)

What the chat needs from the platform:
- `Request.user`, filled by whoever hosts the app:
  - **mounted in angry-gopher:** its `users.currentUserID` and `getUserName`,
    with the chat gate (member or agent) applied in Zig before Roc runs;
  - **standalone:** LC's user support.
- For standalone to share accounts and sessions with angry-gopher, LC's
  version must:
  - read `auth/<id>/{name,password}`;
  - verify the `__Host-gopher_auth` cookie with `auth/_session_secret` (and
    the `.previous` pair);
  - keep the agent rule (uid 3).
- Login pages stay angry-gopher's in v1.
- If LC's design differs, the chat changes only where `Request.user` is
  filled.

**To check when LC's work lands:**
- what shape `user` has;
- whether it is verified before `handle!` (preferred) or by an effect;
- whether its account files are angry-gopher's.

## 6. Work items

Each item lands with tests, and the chat items with harness cases (C2).
Sizes are rough: S under a day, M a few days, L about a week.

### Platform (this repo)

| # | item | size |
|---|---|---|
| P1 | Request body and header bytes cross as `List U8` or validated `Str` (fixes today's unvalidated body). Add a test with invalid UTF-8 | S |
| P2 | `Request` as in §4.1 (target, headers, peer, `at_unix_ms`). Measure the copy of a 100 MiB body into Roc; decide on a refcount gap in webbox's body buffer | M |
| P3 | `Response` record with `kind`: `bytes` (status, headers, `List U8`) | S |
| P4 | `File` effects over `webbox.store`, all of §4.3, each with absent ≠ failed | M |
| P5 | `Clock`, `Random`, `Memo` | S |
| P6 | `file` and `tar_gz` responses (Range, chunking, ustar+gzip, moved from angry-gopher) | M |
| P7 | Guard: Roc entered outside a call panics in debug builds; one arena per call | S |
| P8 | Pin the nightly; `zig build` checks it (dog-park's `roc-version`) | S |

### Streams

| # | item | size |
|---|---|---|
| S1 | `Bus.publish!`; the `stream` response with `Verbatim` and `Splice` renders | M |
| S2 | Test: subscribe before the turn is released; sends while streams open land exactly once (backlog xor live); `Last-Event-ID`/`?since` resume | M |
| S3 | **Pilot on the TODO app**: live updates across tabs via `Splice`. Measure mailbox memory for 64 KiB messages | S |

### Shared Zig moved into webbox

| # | item | size |
|---|---|---|
| M1 | Move `markdown*.zig` and its gold corpus into webbox; angry-gopher imports it; no behaviour change | M |
| M2 | `Markdown.render`/`hostile` as hosted functions | S |
| M3 | Asset table for `chat/*.js` from the sibling checkout; `Asset.src` | S |
| M4 | Search index held by the host; `Search.*` effects (the Zig code as is, called from Roc) | M |

### The chat

| # | item | size |
|---|---|---|
| C0 | Census of production data: invalid UTF-8 by file kind, largest transcript, `.count` line-2 coverage, odd-case duplicates, stray `~*.tmp` | S |
| C1 | Pure core: `Codec`, `Count`, `Paths`, `ZigText`, `Time`, with the Zig test fixtures; benchmark decoding the largest transcript (R7) | L |
| C2 | Differential harness: one request script against both chats on copies of one tree, with the clock and randomness fixed; diff trees and normalized responses; fuzz mode | L |
| C3 | Routes: page and sidebar JSON, conversations, msg redirect, default/resume, new topic | L |
| C4 | Send, stream, raw, reactions/react, pin/unpin | L |
| C5 | Fan-out (notify, sidebar, recent), `Feeds` (images.md, code.md with the fence scanner and its quirk), presence | L |
| C6 | Uploads (multipart, sniff, quota, `file` response) and download | M |
| C7 | Recent, images, code, links pages; search routes over M4 | M |

### Integration and cutover

| # | item | size |
|---|---|---|
| I1 | Mount: angry-gopher serves `/chat` and `/channel` from the Roc chat behind a build flag (as `codex_chat`); identity passed in | M |
| I2 | Run C2 on a copy of production data; fix every difference or record it as intended (R3's 400) | M |
| I3 | Standalone main with LC's user support | S |
| I4 | Bare-metal build (LC) | ? |
| I5 | Cutover: flip the flag on the box. Rollback is flipping it back: the same files | S |

**Suggested order:** P1, P8, C0, then P2-P5 and C1 in parallel, then S1-S3
(the riskiest platform work, proved on the TODO app), then M1-M3, C2, C3-C7,
then I1-I5.

## 7. Questions for Steve

1. **Mounted first?** Mounted in angry-gopher first (R5), standalone later.
2. **Markdown moved, not ported?** Moved into webbox for v1 (§4.5).
3. **Invalid UTF-8 in a new message: refuse it?** Refuse with a 400 (R3),
   after C0's census.
4. **Docs and reading list out of v1?** Yes, they stay in angry-gopher.
5. **Cross-request state: `Memo`, or a Roc model now?** `Memo` (§4.3).
