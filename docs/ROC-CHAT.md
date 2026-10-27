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
- §3, §7 and §8 follow Steve's direction (2026-10-26, through the box):
  port route by route on the branch, each route proven against the Zig it
  replaces (its twin, the judges), and **ship once, when the chat is mostly
  Roc**, in one release. "Mostly Roc" is CC's to propose in QUEUE (the
  routes still Zig), and the box takes it as the release candidate's scope.
- Z1 (one producer of topic blobs, `e4a0f60`) is merged and live (v39).

## 1. Goal

Port most of angry-gopher's chat (`zig-server/src/chat*.zig` and its
neighbours, about 6,800 lines) to a Roc app on the platform in this repo.

- **A webbox app.** The same Roc serves on webbox's Linux host and on bare
  metal. Production (lynrummy.com) is bare metal: zig-metal-unikernel builds
  `gopher.elf` from angry-gopher's checkout.
- **The same files.** The Roc chat reads and writes exactly the files the Zig
  chat does, so there is no migration, and going back is the previous
  release.
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
- **Mounted.** The Roc chat runs inside angry-gopher's process, the way
  angry-gopher already mounts cobble-webbox's `codex_chat` (router.zig:30,
  :170).
- **Router.** The Roc chat's entry point, for every `/chat` and `/channel`
  request after the static assets. It parses the path, runs the prelude
  (the gate, presence, the method checks) and answers.
- **Delegation.** An answer of `Zig(route)` (§5.2): the host runs
  angry-gopher's Zig handler for that route once the Roc call has returned.
- **Twin test.** A Zig function and the Roc function replacing it, run on the
  same inputs, their answers and the files they leave compared.
- **Owners.**
  - **CC** is the cloud session: it writes code on `claude/*` branches.
  - **LC** is the local session on the box: the bare-metal work.
  - **Box** is Steve and LC: merges, releases, production data.
  - angry-gopher, zig-webbox and zig-metal-unikernel are box repos; CC never
    pushes their main branches.

## 3. Scope

**The cut: the Roc router first, for the whole chat.** The Roc chat starts as
a router, mounted in angry-gopher. angry-gopher's top router hands it every
`/chat` and `/channel` path once its static-asset table has passed on it.
On day one it:
- **parses the path** into a typed route (`Route.roc`, pure) by Zig's rules:
  the pair key, the channel name, `validTopicID`, the reserved `new`, the
  tails. For the conversation and topic routes it is the only parser: their
  Zig handlers take the parsed route and never read the path again. The
  families delegated whole (docs, search, recent, images, code, links) are
  handed the rest of their path, which their Zig parses as it does today;
- **runs the prelude** Zig's `handle` and `handleChannel` ran: a static
  script served to anyone, the chat gate (a 303 to `/login/full?next=`),
  presence (except on streams). Who is asking stays the host's: the Roc asks
  (`Host.member!`) after the static scripts, so a script's request does no
  identity reads. The method checks stay with the Zig that serves the
  route, since Zig answered a missing topic's 404 before a wrong method's
  405 (as built, A1-A2);
- **answers with a delegation**, `Zig(route)`: the host runs the Zig handler
  for that route after the Roc call has returned, with the request's `now`
  and user. The lookups that need the disk stay in the handler on day one:
  the participant check, the other account, the channel's members, the first
  topic, whether the topic exists.

**Then Roc takes over the routes, one at a time, on the branch** (Steve,
2026-10-26). Each replaces one Zig piece with a Roc one and is proven
against it: its twin test, and the box's judges on KVM when CC marks a
milestone in QUEUE. **Production gets the Roc chat once, when it is mostly
Roc**, in one release the box gates like any other; going back is the
previous release. There is no per-route switch in production, and no route
is ever served two ways. In order (§8):
1. **Orchestration.** `send` runs §6.2's steps in Roc, calling Zig's pieces
   as hosted functions (milestone 2). Then the conversation lookup.
2. **The pure guts:** Codec, Count, Paths, ZigText, Time, the frame builder.
3. **The routes, a family at a time:** react, reactions, pin and unpin; the
   page and its sidebar data, the empty and 404 pages, `/chat/conversations`,
   `/chat/msg/<id>`, default/resume and new topic; the cross-page fan-out
   and feeds; uploads and download; the recent, images, code and links
   pages.
4. **The store's callers outside the chat** (below): docs and the reading
   list (after v1: they stay Zig for the first release, Steve), login with
   its welcome DM, and admin retire.
5. **Last, the store's writers** (append, `.count`, reactions, bookmarks,
   pins), once every caller of them is Roc.

**Each job has one implementation at a time.** A piece moving to Roc lands
with a twin test against the Zig function it replaces (C2); the Zig function
stays as the test's oracle while that is useful, and its Zig callers switch
in the same release.

**The store's callers outside the chat move to Roc too** (Steve,
2026-10-25: "hopefully we can move to Roc for everything"). Three Zig
callers use the chat's store today:
- login's welcome DM (login.zig:344-362);
- docs' post to chat (docs.zig:270-299);
- admin retire.

Each moves to Roc (C9-C11) before the store does (C8), so when the store
moves every caller of it is already Roc, and nothing needs a way into Roc
from outside a request. Until then they call Zig's store as now.
- **Login in Roc keeps the secrets in Zig.** Roc never reads the auth root
  (§6.3): passwords, the session secret and the cookie signing stay behind
  hosted functions (`Users.register!`, `Users.check_password!`,
  `Users.sign_in!`), and Roc runs the flow around them: the form, the
  checks, the welcome DM, the redirect.
- **Docs and the reading list** are a family like the chat's others: their
  routes are already the router's, delegated, from milestone 1.
- **Admin retire** is reached through the router too, behind the admin gate.

**Supplied to Roc by angry-gopher's own Zig.** These are hosted functions
over the existing modules. Nothing is moved, and there is one copy of each.
Milestone 1 needs only Users and Presence:

| Function | angry-gopher module |
|---|---|
| Markdown | `markdown.zig`: render, render trusted, hostile check |
| Users | `users.zig`: exists, name, authorized roster, agent rule; only-member-named, for blocks from before `uid:`; register, check password and sign in, for login (C10) |
| Presence | `presence.zig`: mark, is online |
| Search | `search_index.zig`: note append |
| Counters | the chat counters `/admin/host` and `/version` read: edge rejects, fan-out failures, malformed channels, refused blocks |

**Stays Zig for now, not yet planned:**
- logout, settings and API keys;
- the admin tools other than retire;
- the startup `.count` backfill;
- the search routes (parsed by the router and delegated, like the others).

**Never Roc: the host's hooks before the turn.** angry-gopher's `bodyLimit`,
uploader and `family` classify paths before the turn (R1), so they stay Zig
path classifiers beside the Roc parser. A3 holds them to the route each path
parses to.

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

With the router, every chat release builds Roc from day one, so a toolchain
bug blocks chat releases until it is fixed or worked around. Steve's call
(2026-10-25): Roc can handle small-scale chat, so there is no Zig fallback
build; the answer is how the pin is kept.

**Mitigation:**
- **T1 first:** a trivial Roc archive in angry-gopher and in `gopher.elf`,
  booted under QEMU. Measure build time, image size and gate cost, and get
  the box's agreement on the toolchain before any chat code.
- The layouts come from `roc glue`, never by hand, and every layout is
  asserted at compile time (P8).
- The build checks that every hosted `extern` has a host export.
- **Stay on the current nightly, pinned to known-good builds.** The pin
  (`roc-version`) names a nightly that has passed the whole gate: the Roc
  tests, A3, A4, the judges on `gopher.elf`. Moving it is a small, frequent
  change of its own, never folded into a chat change, so a nightly that
  breaks something is found alone and the pin stays on the last good one.
  Small steps keep each move's churn in hosted signatures small. Each
  known-good nightly is recorded with what it passed.
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
- **A delegated handler runs after the call.** The host runs a `Zig(route)`
  handler once `handle!` has returned and its call has ended, so the
  handler's writes, and on metal the network pumps inside them, nest
  nothing in Roc.
- **Subscribe before writing.** The host subscribes as soon as `handle!`
  returns, before it writes the preamble. On metal a write pumps the network.

### R2. Two writers of one set of files

While the guts move, Roc's pieces and Zig's write the same files in one
process: a Roc send over a Zig fan-out, a Zig welcome DM into a topic whose
page Roc builds, and, until C8, Zig's store under Roc's orchestration. They
append transcripts, write `.count` and bookmarks, append to
`users/<member>/images.md`/`users/<member>/code.md`, and publish on topic keys. The turn makes that safe
from interleaving. It does not make the two agree.

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
2. **One check that the two agree.** Every piece that moves has its twin
   test (C2), and the twin tests cover Zig's remaining writers too: a docs
   post and a welcome DM into Roc-written files, while those callers are
   Zig. Every Zig-side change to these files after the port is a case.
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

**C1's codec, measured** (angry-gopher `zig build codec-bench`, native,
a synthetic 5.4 MB, 11,392-block transcript): 20 ms against Zig's 10
(2.1x), the call's arena at most 21.7 MB against the Zig decoder's 15.0
(1.5x, the arena's copy of the input included). The first cut was 17x and
7x, for two reasons worth keeping:
- **A transcript is bytes, so the codec cannot use `Str`'s builtins** (the
  probe did, which is why it was faster). Found by hand, a line must be a
  `List.sublist` slice found by offset, never built a byte at a time.
- **`List.prepend` in a fold is quadratic.** ZigText.trim reversed every
  piece that way, and every block of a transcript is trimmed.
The run on the largest production transcript, on metal, is still the
box's: `codec-bench -- <transcript>` takes the file.

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
  can take it and a twin test hands both twins the same fixed `now` (Zig's
  `Now.at`).

### 5.2 Response

```roc
Response : [
    Bytes({ status : U16, headers : List({ name : Str, value : Str }), body : List(U8) }),
    Stream({ key : Str, preamble : List(U8), live : [Forward, Verbatim] }),
    File({ path : Str, content_type : Str, headers : List({ name : Str, value : Str }) }),
    TarGz({ name : Str, entries : List({ path : Str, as : Str }) }),
    Zig(ZigRoute),
]

ZigRoute : [
    Default, Conversations, Msg(Str), Notifications, SidebarStream,
    Docs(Str), Recent(Str), Images(Str), Code(Str), Links(Str), Search(Str),
    Landing(Conv), NewTopic(Conv),
    Topic({ conv : Conv, sid : Str, tail : Tail }),
]
Conv : [Dm(Str), Channel(Str)]
Tail : [Page, Stream, Send, Upload, Uploads(Str), Pin, Unpin, Raw, Download, Saved, Reactions, React]
```

**As built for the router (A2), the answer is flat.** chat/platform/Chat.roc's
`Answer` is a record, `{ kind, location, presence, route }`, `kind` 0 for
Zig's and 1 for a 303, and `route` is `ZigRoute` flattened:
`{ family, key, rest, sid, part, tail }`, small numbers that Chat.roc and
src/chat_route.zig both name, unused fields empty, so two routes are equal
exactly when they go the same place. The records are laid out by hand in
src/chat_abi.zig with their sizes asserted, and A3's agreement test catches
a number that drifts. The tag union above waits for P8's generated
layouts; the request is `{ sub : List(U8), channel : Bool }`, and the host
keeps the request's `now` for Zig rather than passing it, since no Roc
reads it yet.

**As built for C4, the Roc serves routes itself.** `Answer` grew `status`,
`content_type`, `body` and `allow`, and `kind` names what to send: 2 a
status and body, 3 a 405 (sent by webbox's `methodNotAllowed`, which also
declines an `Expect`), 4 already answered by the host inside the call (a
body too big) or failed there, 5 a malformed form (the site's own 400). The
request carries its `method`. The Roc's routes ask the host through hosted
functions inside the call: `presence!`, the reads the conversation lookup
decides on (O2: `accounts!`, below; a channel's member file and the
topics' folder through the file primitives), `body!` and the primitives
(below: the files, a line appended, a topic's count, the bus); each that
works on a conversation is
handed it (`Chat.Conv`, a record crossing by value) and the host keeps none
between calls. A failure in one is kept by the host and returned once
the call has ended, as `member!`'s already was. The writes inside a call
are safe on metal for the reason §6.2's send relies on: a pump runs the
kernel's turn and its fixed Zig render, never a handler, and the busy word
refuses any Roc call beside this one.

**As built for C3**, more answers and hosted functions: `kind` 6 is
webbox's plain 404 and 7 a 302 to `location`; the reads are
`srcs!`, `me!` and `now!` (a page's own data is the Roc's, over `online!`
and `limits!`, below), the write
`append!` (a message's whole store; since C8a the Roc's `appended!` over
`render!` and `store_message!`, and since C8b its fan-out over
`message_parts!`, `append_entry!` and `fanout_failed!`, below), and `body!` takes which
form's limit. Lists of records
(the recent rows) cross as flat lists of byte strings, one decoder
each side, until P8 generates layouts; a folder's entries cross as a list
of records (`list!`, below). **After a failure the host does
nothing more** for the call: every hosted function answers its empty or
"failed" value once one has failed, so a Roc that goes on (a duplicate
check that could not read, then the bookmark and the append) writes
nothing; the host returns the first failure.

**The file primitives: Roc owns the member's files.** `read!`, `write!`
and `remove!` take a path relative to the chat root (bytes); the names
and the formats are the Roc's: the bookmarks (`users/<uid>/last-conv`,
`users/<uid>/last-sessions/<conv>`: where a DM resumes, read, trimmed and
written only when changed, ChatState.roc), the pins
(`users/<uid>/pinned-sessions/<conv>`, ChatState.roc) and the feeds
(`users/<uid>/images.md`, `code.md`, Feeds.roc). A read has three
answers, crossing as the bytes beside a payload-less tag union
(`[Failed, Found, Missing]`, one byte): **missing and failed are never one
answer**, since a set read as empty because the disk failed would be
written back empty. `write!` makes the folders; `remove!` of a file not
there succeeds. **A path that would leave the root is a Roc bug**: empty,
absolute or through `..`, chat_abi.zig refuses it before the host sees it
(`roc_abi.inRoot`) and fails the request (`error.PathOutsideChatRoot`, a
500), never answering "missing". The rule after a failure holds: a failed
read has failed the request, so the bookmark's "written again" after one
(the Zig's `writeIfChanged`, kept in ChatState.changed) writes nothing.

**Roc owns the conversations' names and the channels' files too.**
`list!` takes a folder's path, checked as a file's is, and answers each
entry's name and kind (`[Dir, File, Other]`, as webbox's `store.list`
tells them) in the order the disk gives them, beside the same three-way
status: a folder not there is `Missing` (store.list holds it empty, and so
does the Roc), one that is a file, or through one, is `Failed` (store.list
fails it: error.NotDir), never "nothing there". The entries cross as a
list of `{ kind, name }` records (the list's two-word header, as a
`List(List(U8))`'s). Paths.roc names the folders and files
(`<key>/sessions`, `channels/<name>/sessions`, `channels/<name>.channel`,
`<conv>/sessions/<sid>.reactions.jsonl`) and owns the decisions the Zig
made on them: a conversation's topics (listTopics: every entry not a
folder ending in `.md`, cut, sorted by bytes), a channel's members
(channelMembers: one canonical uid a line, once, trimmed of spaces, tabs
and CRs, `#` and blank lines skipped, or the channel is malformed), and
every roster (channelRosters: each entry ending in `.channel`, of any kind,
read in the listing's order; one gone since the listing skipped). A
reaction sidecar not there is no events. Two small primitives stay the
host's: `fail!` fails the request for a reason, about whom (a tag, never
text, and the channel's name or the account's id: a malformed channel on
its own route is error.MalformedChannel, the old Zig's own answer;
`KindUnreadable` and `NameUnreadable` are an account a lookup needed and
`accounts!` listed as unreadable, and fail with the error that read of that
account failed with, as the host kept it; the reason crosses as a byte,
which `roc_chat_fail` refuses to compile without once FailReason would
have one tag, as one tag crosses as nothing), and
`malformed_channel!` counts a channel a listing skipped as malformed, the
operator's process-lifetime count on /admin/host.

**Identity is one primitive, `accounts!`; the lookups are the Roc's.**
It hands over every account folder named as a counter names one (a
canonical id: digits, the first not zero), in the disk's order, each as
its id, its kind (`[Agent, Guest, Member]`, one byte: the agent is decided
by the host alone, users.zig `isAgent`; a member has a password; a guest
has neither) and its `name` file's bytes as stored, beside `[Failed,
Found]`. Two reads an account (the password's stat, the name), and
nothing else of the auth root: **Roc never reads the auth root**, and
`read!`/`list!` never reach it. chat/Accounts.roc does every lookup:
`exists` (principalExists: an id empty once trimmed is none), `name`
(getUserName: the trailing CRs and LFs cut, "" for none; a member with no
name file reads "", on purpose, 156(i)) and `authorized` (listAuthorized:
members and the agent, by the id parsed as an i64, one too big counting
as 0 and coming first, ties in the disk's order, as a stable sort keeps
them). **Only canonical ids are asked**: a DM's other half and its
partner passed Paths.participant, and the member's own id is a session's,
signed only for an id a counter made, so a `007` folder (an account to
principalExists) is never looked up. **Asked at most once a request**
(chat/main.roc's `Who`: `Known` once asked, handed down), and only by a
route that looks one up: a DM's every route, a page that names the
member, a reaction (its reactor's name), the conversations, /chat/msg; a
channel's topic, reactions and pin never ask. **An account that will not read is listed, never left
out, and fails only what reads it**: a password whose stat failed is a
kind of `Unreadable`, a name that would not read a `name_read` of
`Unreadable` (its `name` empty and never taken for one), and the host
keeps each error without failing the request. A lookup that needs that
read answers `KindUnreadable(id)` or `NameUnreadable(id)` and the request
fails with it (`fail!`), so each route fails exactly when, and with the
error, the old Zig's own read failed: `name` on the account's name
(getUserName: a DM's title, read before its topics and a send's tail; the
member's own name on the pages that name them), `authorized` on the first
account in the disk's order whose password stat failed, or whose name did
and which is not a guest (listAuthorized read every password, then the
names of members and the agent, and stopped at the first failure).
`exists` never fails: principalExists looked at the folder alone. Only a
listing of the auth root that failed is `Failed` for the whole call.

**A reaction is the Roc's; three primitives store and send it.**
chat/main.roc `reacted!` does what storeReaction and appendReaction did, in
their order: the reactor's own name (Accounts.name of the member, from
`accounts!`: getUserName; one that will not read fails the request with
its error, `fail!`), the topic's count (`message_count!`), `NoSuchMessage`
for message 0 or one past the count, the stamp (Time.rfc3339 of `now!`:
formatRFC3339UTC), the line (Reaction.line: reactionLine's fields, order
and escapes, through JsonText), then the frame (Frame.reaction) and its key
(`<conv key>/<sid>`, the sid as the request spelled it) **made before the
store**, the line appended (`append_line!`), and only then the frame
published (`publish!`). The primitives are the host's:
- `append_line!(path, line)`: `line` and a newline appended to a file
  under the chat root, the path checked as the file primitives' are
  (`underRoot`), its folders made as `store.append` makes them. It owns
  **the torn-line rule** (chat_store.zig `appendLine`, `endsMidLine`): a
  file that does not end in a newline gets one first, so a line a stop cut
  short stays its own line. The rule belongs to any append-only line file,
  and keeping it here saves reading the whole sidecar into Roc. It reads
  the last byte before it stores, so a read that fails stores nothing; a
  failure fails the request.
- `message_count!(conv, sid)`: chat_count.messageCount, the count cache and
  its recount staying store infrastructure the append shares. `Failed`
  fails the request, and is never 0.
- `publish!(key, bytes)`: webbox's `bus.publish`, which copies the bytes to
  each subscriber. It cannot fail.

The old Zig (reactions.zig `storeReaction`, chat_store.zig
`appendReaction`, `reactionLine`) stays as the twins' oracle.

**A message is the Roc's (C8a, C8b); primitives store, render and fan it
out.** chat/main.roc `appended!` does what chat_store `appendMessage`
did, in its order, for every send, a new topic's "hi" and its
announcement: **no author, no message** (an empty name fails the request
with `fail!(NoAuthor)`, appendMessage's error.NoAuthor, a 500); the topic's
count (`message_count!`); the id `<sid>_<count+1>` (the sid as the request
spelled it); the stamp (Time.rfc3339 of `now!`); the block
(Transcript.stored_form: chatStoredForm's separator and body-line escape);
the HTML (`render!`) and the frame (Frame.message: messageFrame's field
order, escapes and `cid`) and its key (`<conv key>/<sid>`), **made before
the store** (metal-vmm QUEUE 177.1: nothing can fail between the store and
the publish), and so is the fan-out's every step (below); then
`store_message!`, `publish!`, and the fan-out (`fanned!`). **Stored is
done**: nothing after the store fails the send. The primitives:
- `render!(markdown)`: markdown.zig `render`, the one markdown processor.
  `Failed` fails the request, never an empty page.
- `store_message!(conv, sid, block, index, message)`: chat_store
  `storeMessage`, the block appended to the topic's transcript (its path the
  host's, from the conversation and the sid, as `message_count!`'s), then
  `writeCount(index + 1, new size, the block's offset, the author)` and
  search_index `noteAppend(message)`. The count cache and the search index
  are the store's infrastructure, so they go with the append: **the size
  check is the crash protection**, not the order, and **search sees a
  message as it lands**. An append that failed fails the request, nothing
  stored; the count and the search never fail it.

**The cross-page fan-out is the Roc's (C8b), the markdown's parts the
host's.** chat/Fanout.roc `steps` decides what fanoutCrossPage decided:
**members in the conversation's order, each member's surfaces in one order,
notify, sidebar, recent, images, code**; notify to every member but the
author; the sidebar's topic-added on a topic's first message alone; the
Recent row to everyone, "You" for the author, labelled by recentWhere ("in
<key>", or "to <the other member's name>" from the accounts the request
already holds; a name that will not read gives "", as its absent-ok did);
the images and code feeds only when the message has tags or blocks, each
entry appended and only then its event sent. The bus keys, convKeyBaseURL,
the topic and source URLs, the notify text, every event's JSON and the
feeds' entry format are its (Feeds.roc, Recent.roc). The steps are made
before the store, so after it the Roc only sends and appends. **No step of
it fails the send**, and a surface that fails for one member never costs
that member's others or anyone else's. Three primitives, none failing the
request: each that can fail hands back a `fault`, the host's error as a
number the Roc never reads, carried to the one that says it:
- `message_parts!(markdown)`: recent_feed `recentExcerpt`, images_store
  `extractImageTags`, code_store `extractCodeBlocks` (Steve: the markdown
  parsing stays Zig), **each made or failed on its own**; a part that
  failed fails its surface for every member, counted.
- `append_entry!(path, separator, entry)`: the entry appended to a feed
  under the chat root, the separator first when the file holds anything (the
  read that decides it, and its failure, as appendImagesEntry's). A path
  outside the root is this append's failure (error.PathOutsideChatRoot,
  said), never the request's.
- `fanout_failed!(surface, member, key, sid, fault)`: chat_fanout
  `fanoutFailed`, the operator's count and last failure on /admin/host,
  in its words (`<surface> for member <uid>, <error>, on <key>/<sid>`).
  `fanoutCrossPage`'s "every surface for every member" (a URL it could not
  allocate) has no Roc counterpart: Roc's allocation failure is the call's
  crash (R3), and the fan-out's bytes are all made before the store, so one
  stores nothing.

**`fanoutCrossPage` is a second implementation, for now.** login's welcome
DM and docs' post still call `appendMessage`, which fans out by the Zig's,
until they move (C9-C10); the twins hold the two equal (angry-gopher
`chat_twin_test.zig` encoder by encoder, `chat_actions_twin_test.zig` a
whole send's frames, feeds and failures both ways).

**A conversation's page is the Roc's; two reads stay the host's.**
chat/main.roc `page!` and `sidebar!` read what conversationPage and
sidebarOf read, in their order, each failing the request where theirs did
and with its error: a DM's bookmark first; the viewer's name
(Accounts.name, getUserName); every other authorized member
(Accounts.authorized, listAuthorized: an account that will not read fails
the page, the first in the disk's order); the member's channels
(`channel_rosters!` and Paths.member_channels, listUserChannels: a
malformed one skipped and counted, a member file or a channels folder that
will not read the request's failure, never the rosters read before it);
their pins in the conversation (`read!` and ChatState.pins, pinnedTopics,
sorted: a pins file that will not read is never no pins); the topics as
they were listed to find the topic. Pages.sidebar_json drops stale pins.
What is not a file stays the host's, as two primitives:
- `online!(ids)`: presence.isOnline of each id at the request's time, a
  read of presence's process-lifetime map, **one call for the whole
  roster**; the seam asks the host id by id, so the answer is one flag
  (`[Offline, Online]`, a byte each) for each id, in its place. It cannot
  fail.
- `limits!`: the upload's `image_max`, `video_max` and `accept` and the
  search's `min_len`, **single-sourced in the host**, since its upload and
  search code enforce them; the Roc never copies them.

chat_page.zig `sidebarOf` and `conversationPage` stay, as the twins'
oracle (angry-gopher chat_actions_twin.zig).

The message crosses as one record (Chat.Message: id, from, at, uid,
markdown). appendMessage stays, for the Zig's other writers (login's welcome
DM, docs' post to chat) and as the twins' oracle, held apart from
`storeMessage` so a step dropped from either shows against the other.

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
- **`Zig`**: copies the route's strings out of the call's arena, ends the
  call, and runs the Zig handler for it with the request's `now` and user
  (R1). This is milestone 1's only answer besides the prelude's `Bytes`.
  A route leaves `Zig` when Roc starts doing its work and answers with one
  of the others.
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

**Memory, as the box measured it (2026-10-26).** What crosses into the Roc
and out is copied each way, so bytes whose size a user controls cross only
when the Roc must read them. Four rules came of a large `/raw` costing 6x
its transcript and, at 16 MB, panicking the machine:
- **Bytes the Roc does not read stay the host's**: a hosted function that
  reads or renders them holds them and answers only whether it has them,
  and the Roc answers `held` (kind 8: its `body`, the host's bytes, its
  `location`). `/raw` (nothing around them: the transcript goes out as
  read) and `/chat/links` (the page cut where the rendered links go).
- **Out of memory in a call is that call's crash**, a 500, the machine
  going on (roc_abi.zig `allocate`; the request's strings are made inside
  the guarded frame, so a failure there jumps to a live one).
- **No arena over the request's**: angry-gopher hands the Roc the request's
  own allocator (`useRequest`), freed whole with the request.
- **No memory kept between calls** (`end` frees all; it kept a node the
  size of the largest call, and a failure to was silent).

angry-gopher `chat_actions_twin_test.zig` holds `/raw` of an 8 MB topic to
the old Zig's cost (12,023,880 bytes asked for at once, the Roc's within
1 KB of it); a topic's page is 44,673 bytes against the old Zig's 18,988
(58,568 before the arena went).

### 5.3 Effects

All hosted functions are effectful (`=>`): the nightly refuses a pure one
(probe 3). So a caller is an effectful function, effects in loops use `for`
or `List.*_try!`, and pure modules (Page, Transcript) take already-rendered HTML
as an argument.

| Module | Functions |
|---|---|
| `File` | `read!`, `read_at!`, `stat!`, `list!`, `append!` (answers the new size), `append_line!` (as built: a line, the torn-line rule the host's), `write!` (truncate), `replace!` (temporary file then rename), `make_dir!`, `remove!`, under the data root. Absent and failed are distinct answers; per-call size limits. **Never the auth root.** |
| `Store` | as built: `message_count!` (the count cache and its recount, chat_count.zig); `store_message!` (a message's block appended, then its `.count` and the search index, chat_store `storeMessage`); the fan-out's (C8b): `message_parts!` (a message's excerpt, image tags and code blocks, each made or failed on its own), `append_entry!` (a feed's entry, the separator first when the file holds anything), `fanout_failed!` (a surface counted and said); none fails the request |
| `Bus` | `publish! : List(U8), List(U8) => {}` (as built: the key as bytes) |
| `Random` | `bytes! : U64 => List(U8)` |
| `Markdown` | `render!` (as built: a message's HTML, `{ html, status : [Failed, Rendered] }`), `render_trusted!`, `hostile!` |
| `Users` | `accounts!` (as built: every account, its kind and name; exists, name and the roster are Accounts.roc's lookups), `only_member_named!` (blocks from before `uid:` only); for login (C10), `register!`, `check_password!`, `sign_in!` (the cookie) |
| `Presence` | `mark!`, `online!` (as built: `online!(ids)`, a flag for each id at the request's time; `presence!` marks) |
| `Limits` | as built: `limits!`, the upload's and the search's limits a page tells its client, the host's constants |
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
  main.roc                 handle!: the prelude, then the route's answer (chat.zig handle); a message's author, number, stamp, block and frame, stored and sent (appended!: appendMessage); a page's viewer and sidebar, read in the Zig's order (page!, sidebar!: conversationPage, sidebarOf)
  Route.roc                the path parsed into a route, by Zig's rules     (pure)
  Transcript.roc           transcript blocks: encode, decode, escape (chat_codec.zig); every new block is its stored_form (C8a) (pure)
  Bytes.roc                std.mem's searches and splits, lessThan and sort, on bytes (pure)
  JsonText.roc             JSON as the Zig's encoders write it (pure)
  Count.roc                .count: parse, format, both trust rules (chat_count.zig) (pure)
  Paths.roc                keys, validators, path builders, firstOf; a conversation's folders and topics, a channel's member file parsed, every roster and a member's channels (chat_paths.zig) (pure)
  ZigText.roc              parseInt, std.json.fmt, trims, byte lines        (pure)
  Time.roc                 RFC3339 UTC, civil dates (timefmt.zig)           (pure)
  ChatState.roc            the member's files: their paths; where a DM resumes, the bookmarks read and their write-if-changed; a pin set, parsed (sorted, pinnedTopics) and rewritten (chat_state.zig) (pure)
  Conversation.roc         a route's DM or channel: the pair's other half, members, URL base, titles, a topic found without case (chat.zig findConv) (pure)
  Accounts.roc             who has an account, its name, the authorized roster by numeric id, over Host.accounts! (users.zig) (pure)
  Reaction.roc             the react form judged; the sidecar's line (reactions.zig parseReactForm, chat_store.zig reactionLine) (pure)
  Frame.roc                a message's frame and a reaction's (chat_frame.zig) (pure)
  Feeds.roc                images.md / code.md: their paths, entries, fence scanner (pure)
  Page.roc                 page, chrome, sidebar JSON, escaping             (pure)
  Store.roc                not made: the store's writes are primitives (append_line!, store_message!, message_count!) and main.roc's
  Fanout.roc               a stored message's cross-page fan-out: which member gets which surface, the bus keys, the notify text and every event, recentWhere, in fanoutCrossPage's order (chat_fanout.zig) (pure; main.roc `fanned!` carries its steps out)
  Feeds.roc                (also) the feeds' entries and events as the fan-out writes them, and convKeyBaseURL (images_store.zig, code_store.zig)
  Upload.roc               multipart, sniff, quota                          (mostly pure)
```

Pure modules test with `roc test`, which finds `expect`s through imports and
exits 1 on failure, using fixtures copied from the Zig tests.

### 6.2 One send, in Zig's order

1. **Gate.** The router's prelude has already applied the chat gate (a
   member or the agent) and marked presence; the host filled `user`.
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
   - fan out (the Roc's own since C8b, chat/Fanout.roc).
   - Each of these is best-effort: a failure bumps a counter, never fails the
     send.
10. **Answer.** 204 for `X-Chat-Async`, else 303 to the topic.

O1's tests inject failures at every step (as Zig's FailingAllocator tests do)
and check that stored implies echoed, and that an error implies nothing
stored.

**As O1 landed (2026-10-26).** Steps 1, 2 and 10 are the Roc's (chat/main.roc
`send!`, `store!`), and so is the order of 3-5: the conversation first
(chat/main.roc `find!`, the old `findConv`'s rule: the pair's other account,
the channel's members), then the method, the `X-Chat-Async` header, the
body, the empty and non-UTF-8 checks, the hostile check (`Host.hostile!`,
whose 400 and edge count are the host's), the bookmark for a DM, and the
store. **Since C8a steps 6-9 are the Roc's too** (chat/main.roc `appended!`,
§5.2): the author, the number, the stamp, the block, the render and the
frame before the store, then `store_message!` (the append, `.count`, search),
`publish!`, and since C8b the Roc's fan-out (Fanout.roc's steps, made before
the store, carried out by `fanned!`). The hostile check cannot be
reached by any message a person could send (16 units of work a byte; 200,000
random messages of the formatting characters found none), so its branch is
held by the scripted host, not the twin.

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

## 7. Milestones

### Milestone 1: the Roc router serves the whole chat, on metal

Every `/chat` and `/channel` request enters Roc. Roc parses it, runs the
prelude, and delegates every route to Zig (§3). Nothing else is Roc's yet.

It proves, on every chat request and before any chat logic moves: the
toolchain in `gopher.elf` (R0), the Request and Response layouts with the
delegation, the busy word (R1), the arena's peak (R5), and a crash as a 500
(R3).

**Exit criteria:**
1. **The router agrees with Zig's dispatch** on A3's corpus: the same route,
   or the same refusal, for every path, method and gate state.
2. **angry-gopher's route tests pass through the router** (A4): the existing
   tests are the harness.
3. The box's judges and metal-vmm's checks pass on `gopher.elf` with the
   router.
4. A planted Roc crash on `gopher.elf` under QEMU answers 500, is logged with
   its route, and does not loop.
5. Peak arena bytes and the router's cost per request on metal; `gopher.elf`
   build time and size with Roc.
6. Steve using it.

**Where it stands** (A1-A4, angry-gopher `bb9ad6c`, roc-webbox `a7aa6ab`):
1. Met: A3's agreement test, 11,000+ decisions, every route-test path and
   generated ones, under both areas, member or not. It found one
   disagreement between the router and the pre-turn hooks, which was Zig's
   before: a topic's `.../stream/` counted as chat and as presence (fixed:
   presence is read from the route).
2. Met: the route tests run through the router; a broken `/c/` in the Roc
   fails seven of them.
3. Met under QEMU (TCG), open on KVM: probe/judge_gopher.py on the router's
   `gopher.elf` against the Linux server of the same commit passed every
   case but two, neither the router's: `/version` (built `-Dstamp=off`, so
   it names no commit) and an upload bigger than the kernel's heap (a
   broken pipe where Linux answers 413; the pre-Roc kernel fails it the
   same way here, so it is the box's to see on KVM). The member story's 53
   requests and both chat stream cases passed through the router.
4. Met (roc-webbox `3fe6000`): a Roc crash jumps back to the call's entry
   (P9) and is a 500. On `gopher.elf` under QEMU, with the planted crash
   app in the router's place: `GET /chat/crash -> RocCrashed, 500` in the
   log, and the machine went on serving. The busy word (P7) refuses a call
   inside or beside another and stops Roc running outside one.
5. Partly: build size and time measured (41,529,840 bytes; 84 s). The
   router's Roc memory is the request's own allocator now, so R5's "the
   arena keeps its peak" is gone for it; its cost per request on metal is
   not measured.

### Milestone 2: one send, orchestrated in Roc

`send` leaves `Zig`: Roc runs §6.2's steps, calling Zig's pieces as hosted
functions (membership, the count, the frame, the append, the publish, the
fan-out).

**Exit criteria:** O1's failure injection at every step (stored implies
echoed; an error implies nothing stored); the twin test of a send, Roc's
order against Zig's `appendMessage`, on the same tree and `now`; the judges
on `gopher.elf`.

**Where it stands (2026-10-26):** met but for U2. The send is the Roc's
(O1), held by its twin and by failures injected at the host's three steps
(the members, the bookmark, the append); since C8a the append's own steps
are the Roc's too, over the store's primitives, but for the fan-out. The box judges it on
`gopher.elf` as a milestone (QUEUE RC-M2).

## 8. Work items

Each item lands with tests; a piece that replaces Zig lands with its twin
test (C2).
- **Sizes:** S is under a day, M a few days, L about a week, XL two or more
  weeks.
- **Repo:** rw is roc-webbox, ag is angry-gopher, wb is zig-webbox, zmu is
  zig-metal-unikernel.
- Box repos take CC's `claude/*` branches, and the box merges them.

### First: prove the toolchain

| # | item | repo | owner | size |
|---|---|---|---|---|
| P1 | Bytes cross as `List(U8)` (body, header values); the TODO app's ids parsed byte-wise, not by `from_str` | rw | CC | S |
| P8 | Pin the nightly; the build checks it (**done by LC**, `roc-version`). Layouts generated by `roc glue`, asserted at compile time. The build checks every hosted `extern` has an export (weak symbols). Moving the pin is its own change, gated like a release, and each known-good nightly is recorded (R0) | rw | CC | M |
| C0 | Census of production data (R2, R4, R5 lists) | — | box | S |
| T1 | A trivial Roc archive linked into angry-gopher and `gopher.elf`, booted under QEMU; build time, size, gate cost; the box agrees the toolchain | ag, zmu | box + CC | M |

### The platform

| # | item | repo | owner | size |
|---|---|---|---|---|
| P2 | `Request` (§5.1) with `now` and `user`; the zero-copy body on Linux; measure the copy on metal | rw | CC | M |
| P3 | `Response` (§5.2): `Bytes`, and the `Zig` delegation | rw | CC | S |
| P5 | `Random`, `Counter`, `Asset` | rw | CC | S |
| P7 | The busy word (CAS) per app inside its `roc_hooks` bracket, checked in `roc_alloc` and in every hosted function (**done**, roc-webbox `3fe6000`, one word for the binary); the arena with a retention limit; a capped region on metal (the router's arena is the request's already) | rw | CC | M |
| P9 | **Done** for the router, roc-webbox `3fe6000`: `roc_crashed` longjmps to the call's entry; a test on Linux, a planted crash on gopher.elf under QEMU (TCG); on KVM, the box's | rw | CC (+ LC on metal) | M |
| U1 | Hosted functions over angry-gopher's modules: Users and Presence for milestone 1; Markdown, Search and Counter as the guts need them (Users, as built: one primitive, `accounts!`, users.zig `listAccounts`; §5.2) | ag | CC → box | M |
| P4 | `File` effects: `write` vs `replace` per site, per-call limits, no double copy, absent ≠ failed. Needed from the first gut that touches the disk itself (O2, C8) | rw | CC | M |
| P6 | `File` and `TarGz` responses (moved from chat_upload/chat_download). Needed for C6 | rw | CC | M |

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

### The router

| # | item | repo | owner | size |
|---|---|---|---|---|
| A1 | **Done**, angry-gopher `bb9ad6c`: chat.zig `serve(route)`, the handlers take a parsed route, the uid and `now`, and no longer read the path; chat_router.zig, the prelude's host side and the dispatch; a failure reading who is asking kept and returned, a 500 | ag | CC → box | M |
| A2 | **Done**, roc-webbox `a7aa6ab`: chat/Route.roc, chat/main.roc, the chat's own platform (chat/platform/), the path as `List(U8)` | rw | CC | M |
| A3 | **Done**, angry-gopher `bb9ad6c`: chat_route_twin.zig, Zig's old dispatch as a pure function, held to the Roc over the corpus; router.zig's hooks test | ag, rw | CC | M |
| A4 | **Done**: the route tests go through the router as they are (router.zig hands it /chat and /channel) | ag | CC → box | M |
| M1 | **Milestone 1** (§7) | rw, ag | CC; box releases | L |

### Orchestration in Roc

| # | item | repo | owner | size |
|---|---|---|---|---|
| U2 | The send's pieces as hosted functions: `appendMessage` split into its steps, so §6.2's order is Roc's (**done by C8a**: steps 6-9 are the Roc's `appended!` over `render!`, `store_message!`, `publish!` and `fan_out!`; see §5.2 and the note under §6.2) | ag | CC → box | M |
| C2 | The twin-test kit: a Zig function and its Roc twin run on the same inputs (a fixed `now`, a copy of one tree, seeded randomness), their answers and the files they leave compared; corpora of poison blocks, mixed-case sids and non-UTF-8 names; failure injection | ag, rw | CC | L |
| O1 | `send` in Roc (§6.2) over U2, with failure injection at every step (**done for steps 1-5 and 10**: chat/main.roc `send!` and `store!` serve every send, a DM's and a channel's, judging the form, the empty and non-UTF-8 message, the async header and the bookmark's order in Roc; the conversation, the hostile check and the store's `appendMessage` are the host's, as hosted functions; a conversation that is not there or not the member's is handed back, so its 404s are the Zig's own; held to the old Zig by angry-gopher `chat_actions_twin_test.zig`, now 129 requests both ways, every answer and file the same, by chat_hosted.zig's scripted host for the order of the calls and the hostile and failed-store paths no request can reach, and by router_failures_test.zig for a store, a bookmark and a member list that fail; every mutant killed) | rw | CC | M |
| M2 | **Milestone 2** (§7) | rw, ag | CC; box releases | S |
| O2 | The conversation lookup in Roc (**done**: chat/Conversation.roc decides a DM's other half by chatKeyParticipant's rule, its members, the URL bases, the titles and whether a topic is there without case; chat/main.roc `find!` asks the host only `accounts!` (every account, once a request; chat/Accounts.roc looks up the other half, the names and the roster, held to principalExists, getUserName and listAuthorized by a twin over 1,500 generated account trees: canonical and not, files where folders belong, passwords or none, the agent with and without one, names with CR LF, ids past an i64; `account!`, `name!`, `viewer!` and `members!` gone, 24 hosted functions to 21), reads a channel's member file and the topics' folder through the file primitives (Paths.roc parses and chooses), and hands the conversation it found (`Chat.Conv`: family, key, base, members) to every hosted function that works on one, so the host holds no conversation between calls (`topic!`, `landing!`, `conv!`, `send_conv!` gone); a DM page's bookmark is the Roc's `bookmark!` before `page!`; held by twins over generated keys, malformed ones too, and hostile names, the scenario (the DM with yourself, keys not canonical, a partner with no name) and failures injected (a malformed channel, a name that will not read); every mutant killed) | rw | CC | M |

### Streams

S3 measures the Zig chat as it is, and can run any time.

| # | item | repo | owner | size |
|---|---|---|---|---|
| S1 | `Bus.publish!`; the `Stream` response; the `Forward` and `Verbatim` renders. Needed when Roc builds frames (C1) and serves streams itself | rw | CC | S |
| S2 | Tests: subscribe before any write; exactly once (backlog xor live) under sends; `Last-Event-ID` and `?since=` resume; on Linux and metal | rw | CC (+ LC) | M |
| S3 | Mailbox worst case on metal (64 KiB of markdown that escapes badly × 16 slots × subscribers), measured on the Zig chat first, since it publishes the same frames now; the frame cap | ag, rw | CC (+ LC) | S |

### The guts in Roc

Each is a release, with its twin test. A route that moves answers with
`Bytes`, `Stream` or `File` instead of `Zig`.

| # | item | repo | owner | size |
|---|---|---|---|---|
| C1 | Codec, Count (both trust rules), Paths, ZigText, Time, the frame builder, with the Zig fixtures; benchmark on the largest transcript with peak arena bytes (**done but the metal run**: chat/{Time,ZigText,Paths,Codec,Count,Frame}.roc behind the test-only `chat/twin.roc`, each held to its Zig in angry-gopher `src/chat_twin_test.zig`, every module mutation-checked; chat_count's pure decisions pulled out of its I/O to be twinned; `zig build codec-bench` for R6; the run on the largest production transcript, on metal, is the box's) | rw | CC | XL |
| C4 | React, reactions, pin, unpin (**done**: chat/main.roc `act!` serves them, with chat/Form.roc and chat/Reaction.roc for the form; the store's writes stay Zig's as hosted functions until C8; the pins and the reaction sidecar are the Roc's files, read through the file primitives (the pin set's name and format ChatState.roc's, the sidecar's path Paths.roc's); a topic Zig cannot find is handed back to it, so its 404s are its own; held to the Zig it replaced by angry-gopher `src/chat_actions_twin_test.zig`, 45 requests both ways on two copies of one tree, every answer and file the same, and by twins of the form, the react form and the glyph rule; every mutant killed but one equivalent; **the reaction's store too** (§5.2: chat/main.roc `reacted!` decides the reactor, the bound, the stamp, the line and the frame, over three primitives, `append_line!` with the torn-line rule, `message_count!` and `publish!`; `react!` gone, 21 hosted functions to 23; held by angry-gopher `chat_actions_twin_test.zig`'s reactions both ways (the sidecar's bytes and every frame on its key, a sidecar that starts torn, names with quotes, backslashes, control bytes, non-ASCII and not UTF-8, every bound) and its failures (a sidecar, a count and a reactor's name that will not read: the old Zig's error, nothing stored, nothing sent), a twin of the line against reactionLine, the scripted host for the order, and the seam's probes; every mutant killed) | rw | CC | M |
| C3 | Page, chrome (matches Zig's settings page byte for byte; a twin test), sidebar JSON, 404 and empty pages, conversations, msg (302), default/resume, new topic (with the `general<N>` announcement) (**done**: chat/Chrome.roc, Pages.roc and Html.roc build the chrome and the pages byte for byte to the Zig's, by twins; the Roc serves a conversation's landing, a topic's page, /chat and /chat/default, /chat/conversations, /chat/msg/<id> and a new topic, chat/Topics.roc judging names without case and the `general<N>` an announcement goes to; the store's reads and writes (a page's data, the append) are the host's, as hosted functions, and the member's bookmarks, a conversation's topics and every channel's roster are the Roc's files, through the file primitives (ChatState.roc and Paths.roc name and parse them; the malformed-channel count stays the host's); held to the old Zig by angry-gopher `chat_actions_twin_test.zig`, 97 requests both ways, every answer and file the same; every mutant killed but two equivalent; **the page's data too** (§5.2: chat/main.roc `page!` and `sidebar!` read the viewer, the roster, the channels, the pins and the topics as conversationPage and sidebarOf did, over `accounts!` and the file primitives; `online!` and `limits!` the host's; `page!` gone, 27 hosted functions to 28; held by angry-gopher `chat_actions_twin_test.zig`'s pages both ways (DMs and a channel, members at the presence window's edges, stale pins, a malformed channel, names needing escaping, markup in a topic's name), `online!` against isOnline over generated last-seen times at the edge, `router_failures_test.zig`'s failures both ways (an account the roster reads, the viewer's name, a member file, the channels folder, a pins file that is a folder, topics that will not list: the old Zig's error, byte for byte), the scripted host for the order and the seam's probes; every mutant killed) | rw | CC | XL |
| C5 | Fan-out (notify, sidebar, recent, `users/<member>/images.md`, `users/<member>/code.md` with the fence scanner and its quirk), replacing angry-gopher's | rw | CC | L |
| C6 | Uploads (multipart, sniff, quota as `write`, lossy filename) and download | rw | CC | L |
| C7 | Recent (including doc rows from docs_store), images, code and links pages (**done, but their streams**: chat/Feeds.roc names a member's images.md and code.md (read through `read!`) and reads them as images_store and code_store do, the fences by markdown_fence's rules, and writes their pages' JSON; chat/Recent.roc names, dates, excerpts (recent_feed's rules) and orders, stably, the rows recent.zig `gatherRows` read, the host keeping every read and the choice of a message's date or a file's; Pages.roc builds the three pages byte for byte; held by twins over random feed files, messages and rows (ties and all), the scenario and failures injected; every mutant killed; the **links**, with a topic's raw transcript: chat/main.roc `links!` serves /chat/links by any method, as the Zig did, and Pages.roc builds the page byte for byte; `links.md`'s trusted render is the host's, `Host.links!`; a topic's `/raw` is `act!`'s, GET or HEAD after the topic, its bytes `Host.raw!`'s and answered as text with `nosniff`, a new flag on the Answer; held by angry-gopher `chat_actions_twin_test.zig`, now 149 requests both ways (one a transcript that is not UTF-8), by the scripted host for a transcript gone since its topic was found, and by a links.md that cannot be read; every mutant killed) | rw | CC | L |
| C9 | Docs and the reading list (`/chat/docs/*`, `…/<sid>/saved`), including docs' post to chat | rw | CC | L |
| C10 | Login in Roc, with its welcome DM; the secrets behind `Users` hosted functions (§3) | rw, ag | CC → box | L |
| C11 | Admin retire, through the router behind the admin gate | rw | CC | M |
| C8 | The store's writers: append, `.count`, bookmarks, pins, once C9-C11 have made every caller Roc (reactions done, over `append_line!`, C4). **C8a done**: a message's own decisions are the Roc's (chat/main.roc `appended!`: no author, the count, the id, the stamp, Transcript.stored_form, Frame.message over `render!`, made before the store; §5.2), over `store_message!` (the append with its `.count` and search note, chat_store `storeMessage`) and `publish!`; `append!` gone, 23 hosted functions to 25 (`render!`, `store_message!`, `fan_out!`); held by angry-gopher `chat_actions_twin_test.zig`'s sends both ways on one hub (the transcripts, `.count` files and feeds, every frame on the topics' keys and every member's ntf/sb/rec/img/code keys, and search after: separator lines bare and escaped, a leading `>`, CRLF, empty lines, a trailing newline, names and cids JSON escapes, a name not UTF-8, first messages in a DM and a channel, a stale `.count`), its failures (an append, a count and a nameless sender: the old Zig's error, nothing stored or sent), the stored form's round trip through decodeChatFile, the scripted host for the order, and the seam's probes; every mutant killed. **C8b done**: the cross-page fan-out is the Roc's (chat/Fanout.roc: who gets which of notify, sidebar, recent, images and code, members in the conversation's order and surfaces in that order; the five bus keys, convKeyBaseURL, the topic and source URLs, the notify text, every event's JSON, the images.md and code.md entries, recentWhere over the request's accounts), made before the store and carried out after it (main.roc `fanned!`), the markdown's parts the host's (`message_parts!`: Steve, the markdown parsing stays Zig), a feed's append `append_entry!`, each failure counted and said by `fanout_failed!` (chat_fanout's count and `fanout_last`, its words unchanged), **none failing the send**; `fan_out!` gone, 25 hosted functions to 27; held by angry-gopher `chat_twin_test.zig` (every encoder, entry and key against chat_fanout's, recent_feed's, images_store's and code_store's over generated bytes; recentWhere over generated account trees), `chat_actions_twin_test.zig` (the sends both ways grown: image tags and fences of every kind, a DM's new topic, a channel of three, the DM with yourself, a partner whose name will not read; and a member whose images.md is a folder: the same failures counted, the same `fanout_last`, their code and everyone else's surfaces whole, the send done), the scripted host for the order and the failures, the seam's probes; every mutant killed. **Owed**: `fanoutCrossPage` stays as a second implementation for the Zig's own writers (login's welcome DM, docs' post, through `appendMessage`) until they move with C9-C10, held equal by the twins; then it and `appendMessage` go | rw | CC | L |

### Standalone, after Roc serves everything

| # | item | repo | owner | size |
|---|---|---|---|---|
| I3 | Standalone main with LC's user support (§6.3) | rw | LC + CC | L |
| I4 | Markdown moved into webbox; search held by the platform; presence and the rate limit in a Roc model (feasible; needs ownership beyond the per-call arena) | wb, rw | CC → box | XL |

**Order:**
1. P1, P8, C0, T1.
2. P2, P3, P7, P9, U1 and A1-A4, each booting on metal. C1's pure modules
   start in parallel; they reach production only when a gut uses them.
3. M1, judged by the box (not released: Steve ships once, mostly Roc).
4. C1, C4, C3, O1, raw, links and C7's pages (done on the branch),
   each a milestone the box judges.
5. **v1, one release**: the chat as mostly Roc, its scope the QUEUE line
   naming what is still Zig (proposed there by CC, taken by the box).
6. After v1: O2, C5, C6, the streams (S1, S2), C9 (docs, the reading list,
   search), C10, C11.
7. C8, with P4.
8. I3, I4.

**Releases and rollback.** There is no production switch, and the steps are
not each a release (Steve, 2026-10-26): they land on CC's branch, the box
judges each milestone CC marks, and production takes the Roc chat once, in
one release, when it is mostly Roc (QUEUE names what is still Zig). Going
back is the previous release.
Every release reads and writes the same files in the same formats, which
each twin test checks, so going back loses only what a restart loses:
- presence (came-online fires again);
- the rate limit;
- bus subscribers, whose clients reconnect and resume by index.

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

- **The Roc router (Steve, 2026-10-25).** Steve was not bought in to a
  route-by-route cutover in production, and proposed instead a Roc platform
  for the chat whose Roc routes all delegate to Zig from day one, with Roc
  then replacing Zig's guts at leisure. §3, §7 and §8 now follow it. What it
  changed:
  - one production switch, the day the router ships, instead of one per
    route, and no route ever served two ways;
  - the riskiest parts (R0, R1, R3, R5) proved on every chat request at
    milestone 1, before any chat logic moves;
  - the two-process differential harness (old C2a-c) replaced by twin tests
    of each piece, angry-gopher's own route tests run through the router,
    and the judges;
  - no per-route switch, and no Zig fallback build either (Steve: Roc can
    handle small-scale chat); the pin is kept on known-good nightlies,
    moved often and on its own (R0);
  - the cost: Roc is a hard dependency of every chat release from day one
    (R0).

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

1. ~~A route-by-route cutover in production?~~ No (Steve, 2026-10-26):
   route by route on the branch, proven there; production gets the Roc chat
   once it is mostly Roc, in one release.
2. ~~Z1, one producer of topic blobs?~~ Done (`e4a0f60`), merged and live.
3. ~~Roc in `gopher.elf` (T1)?~~ Yes (Steve): the pinned nightly joins the
   lynrummy.com kernel's build when the Roc chat ships; T1/A's diff is the
   way in, kept current.
4. ~~Refuse a new message that is not UTF-8, with a 400?~~ Done in Zig
   (`f2601c4`); the Roc chat matches it. C0 still counts old non-UTF-8
   transcripts and names.
5. ~~`cid` to every viewer, or only the sender?~~ Settled by `e4a0f60`: it
   still goes to every viewer, and the client shows "sent" only for its own.
6. ~~Docs and the reading list stay Zig for v1?~~ Yes, and search too
   (Steve, 2026-10-26): the router delegates them to Zig in v1; C9 is after
   v1.
7. ~~The fallback build?~~ None (Steve): Roc can handle small-scale chat;
   the pin stays on known-good nightlies, as current as they come (R0).
8. ~~Login, docs and retire when the store moves?~~ They move to Roc first
   (C9-C11), so the store moves with only Roc callers (§3).
