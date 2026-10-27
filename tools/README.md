# tools

- `get_roc.sh` installs the Roc compiler roc-version pins.

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
  `shale --budget steps=200000000 tools/roc_hunt/hunt.shale self_test=1`,
  then without `self_test` for chat/'s production modules.
  - `same_typed_args` — neighbouring arguments of one type, which a swap
    leaves type-correct (a record or a nominal type names them).
  - `magic_numbers` — integer literals but 0 and 1; one that is a printable
    byte is marked `'?` (a character literal, `'_'`, says which).
  - `bools` — `Bool` arguments and record fields (a tag says which).
  - `positional_lists` — a `List(List(U8))` read with `get`: parts known
    only by position (a record names them).
  - `if_chains` — `else if` three or more deep (often a `match` on a tag).
  - `long_definitions` — definitions over 40 lines, longest first.

A hunt worth running again is saved here, with plants; a one-off question is
asked inline and not kept.
