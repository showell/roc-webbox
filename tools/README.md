# tools

- `get_roc.sh` installs the Roc compiler roc-version pins.
- **`chat_quick_gate.shale`** — the gate for a refactor of the Roc chat
  (chat/*.roc, its platform, its seam), with angry-gopher beside this
  checkout: zig fmt, `roc check` of the two apps, this repo's
  `zig build test` and angry-gopher's (the twins and the router's tests).
  `shale tools/chat_quick_gate.shale`, no arguments; one PASS or FAIL line.
  Its header says what it leaves to the full gates, and when a step needs
  them instead.
- **`chat_glue.shale`**: `roc glue`'s snapshot of the chat's seam
  (src/glue/chat_platform_abi.zig) regenerated with the pinned Roc, which
  src/chat_glue_test.zig holds every `roc_chat_` function's records to.
  `shale tools/chat_glue.shale`, no arguments, after any change to
  chat/platform/; the quick gate runs it too.

## Reading Roc with Roc's own parser

- **`roc-ast`** — the parse tree of each `.roc` path on stdin, as Roc's own
  parser prints it, lives in Shale (`tools/roc_ast`, its one user being
  Shale's `roc_tree` and Roc recipes). Install or update it from Shale's
  checkout with `shale tools/roc_ast/install.shale`; it lands at
  `~/tools/roc-ast/bin/roc-ast`.
- **The chat's style hunts** are retired (2026-11-01; git history has them):
  the chat is frozen as reference, and Shale's cookbook recipes
  (`cookbook/roc/`, on `roc_tree`) hunt the Roc we still write.

A hunt worth running again is saved here, with plants; a one-off question is
asked inline and not kept.
