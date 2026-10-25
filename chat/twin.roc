## THE ROC CHAT'S PURE MODULES, BEHIND ONE TEST-ONLY ENTRY (docs/ROC-CHAT.md
## C1): `call` runs the function `which` names. Every argument and result is
## bytes; a number crosses as its decimal digits, a missing value as no
## result at all. angry-gopher's chat_twin_test.zig holds each to the Zig
## it replaces. Never linked into a server.
app [call] { pf: platform "twin/platform/main.roc" }

import Time

call : { which : U8, args : List(List(U8)) } -> List(List(U8))
call = |req| {
	arg = |i| List.get(req.args, i) ?? []
	match req.which {
		1 => [Str.to_utf8(Time.rfc3339(int(arg(0))))]
		2 => [Str.to_utf8(Time.date(int(arg(0))))]
		3 =>
			match Time.unix_from_rfc3339(arg(0)) {
				Ok(n) => [Str.to_utf8(I64.to_str(n))]
				Err(None) => []
			}
		_ => crash "twin: no function ${U8.to_str(req.which)}"
	}
}

## A signed decimal the test wrote.
int : List(U8) -> I64
int = |digits| match digits {
	[45, .. as rest] => 0 - List.fold(rest, 0, |n, c| n * 10 + U8.to_i64(c - 48))
	_ => List.fold(digits, 0, |n, c| n * 10 + U8.to_i64(c - 48))
}
