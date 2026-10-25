# Probes behind docs/ROC-CHAT.md

Small programs that tested the design's assumptions against the pinned Roc
nightly (2026-10-18-1df370f), each built with `roc build --target=x64musl`
and linked into a minimal Zig 0.17 host (`common/rt.zig`, copied into each
probe as `rt.zig`). Kept as evidence; they are not built by `zig build`. The
generated glue (`roc glue … ZigGlue.roc`) is left out: regenerate it.

| probe | what it showed |
|---|---|
| `p1/` | Records holding `List(U8)` and `List({name, value})` cross `roc_handle` and hosted functions; tag unions cross too. `host_missing.zig`: a missing hosted export links (weak symbol) and jumps to 0 |
| `p3/` | A pure (`->`) hosted function is refused: hosted functions are effectful |
| `p4/app/str.roc` | `Str.from_utf8`, `from_utf8_lossy` (a run of bad bytes becomes one U+FFFD), concatenation speed |
| `p4/app/decode.roc`, `p4/zigdecode.zig` | A 5 MB transcript decoded in Roc at about 1.2-1.5x Zig |
| `p4/app/ints.roc`, `p4/zigint.zig` | `U64.from_str` vs Zig `parseInt` (Roc takes hex, binary, octal, exponents); overflow crashes |
| `p4/hostjmp.zig`, `p4/rt_jmp.zig`, `p4/sljmp.zig` | A Roc crash recovered by longjmp (Roc's own sljmp), the arena reset, the next call served |
| `p7/chat/` | Many app modules, `import "file" as x : List(U8)`, effects in `for` and `*_try!`; `ZigText.roc`, a byte-wise Zig-compatible parseInt |
| `p8/` | Nominal record layout; a Roc model held across calls (`Box(Model)`); a zero-copy body with a static refcount word |
