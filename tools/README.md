# tools

- `get_roc.sh` installs the Roc compiler roc-version pins.
- **`chat_quick_gate.shale`** — the gate for a refactor of the Roc chat
  (chat/*.roc, its platform, its seam), with angry-gopher beside this
  checkout: zig fmt, `roc check` of the two apps, this repo's
  `zig build test` and angry-gopher's (the twins and the router's tests).
  `shale tools/chat_quick_gate.shale`, no arguments; one PASS or FAIL line.
  Its header says what it leaves to the full gates, and when a step needs
  them instead.

## Reading Roc with Roc's own parser

- **`roc_ast/`** — `roc-ast`: the parse tree of each `.roc` path on stdin,
  as roc-lang/roc's parser at the pinned commit prints it (one node a line,
  indented by tabs). Built with Zig 0.16.0, the pinned Roc's (its build.zig
  says why). Install or update it with `shale tools/roc_ast/install.shale`;
  it lands at `~/tools/roc-ast/bin/roc-ast`, where Shale may run it.
- **`roc_hunt/hunt.shale`** — Shale hunts over those trees for the
  constructs our Roc style replaces, one named function a kind, the trees
  read once (Shale has no way to share functions between scripts). Each hunt
  has plants (`plants/<hunt>.roc`) that must fire first:
  `shale tools/roc_hunt/hunt.shale self_test=1` (its budget is in its header),
  then without `self_test` for chat/'s production modules.
  - `same_typed_args` — neighbouring arguments of one type, which a swap
    leaves type-correct (a record or a nominal type names them).
  - `magic_numbers` — integer literals but 0 and 1; one that is a printable
    byte is marked `'?` (a character literal, `'_'`, says which).
  - `bools` — `Bool` arguments and record fields (a tag says which).
  - `bool_returns`: a function returning `Bool` whose name is not a
    question's (`is_`, `has_`, `can_`): a decision that wants a tag, or a
    failure that wants a `Try`.
  - `positional_lists` — a `List(List(U8))` read with `get`: parts known
    only by position (a record names them).
  - `if_chains` — `else if` three or more deep (often a `match` on a tag).
  - `long_definitions` — definitions over 40 lines, longest first.
  - `fs_bypass` — a call to Host's file primitives (`read!`, `write!`,
    `remove!`, `list!`, `append_line!`, `append_entry!`) outside
    `chat/Files.roc` and `chat/test/` (Files.roc takes only the
    `Paths.ChatPath` that Paths.roc alone can make).
  - `html_trusted_nonliteral` — a call to `Html.trusted` whose argument is
    not a string literal free of interpolation, or `Html.trusted` passed as
    a value; `Html.host_markup` outside `chat/Chrome.roc` (the host's script
    srcs); `Html.twin_script_json` anywhere (the twins' alone). `Html` is
    opaque, so these and `Html.escape` are the only ways bytes become a page.

- **`roc_hunt/zig_census.shale`** — how much of the chat is still Zig,
  from angry-gopher's zig-server (`gopher=`, a mount path): each route
  Roc's or Zig's (main.roc's `served_by`, evaluated over its tree), each
  hosted function's Zig answer sized and classed, the chat's Zig called
  from outside it, what no live root reaches (twins and tests are not
  live), and the number to watch: live chat Zig against chat Roc.
  `shale tools/roc_hunt/zig_census.shale`; its budget is in its header.

A hunt worth running again is saved here, with plants; a one-off question is
asked inline and not kept.
