# tools

- `get_roc.sh` installs the Roc compiler roc-version pins.

## Reading Roc with Roc's own parser

- **`roc_ast/`** — `roc-ast`: the parse tree of each `.roc` path on stdin,
  as roc-lang/roc's parser at the pinned commit prints it (one node a line,
  indented by tabs). Built with Zig 0.16.0, the pinned Roc's (its build.zig
  says why). Install or update it with `shale tools/roc_ast/install.shale`;
  it lands at `~/tools/roc-ast/bin/roc-ast`, where Shale may run it.
- **`roc_hunt/`** — Shale hunts over those trees, one script a kind of
  finding. Each has plants (`plants/<hunt>.roc`) that must fire first:
  `shale tools/roc_hunt/<hunt>.shale self_test=1`, then without it for
  `chat/`.
  - `same_typed_args.shale` — neighbouring arguments of one type, which a
    swap leaves type-correct (a record or a nominal type names them).

A hunt worth running again is saved here, with plants; a one-off question is
asked inline and not kept.
