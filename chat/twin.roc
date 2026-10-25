## THE ROC CHAT'S PURE MODULES, BEHIND ONE TEST-ONLY ENTRY (docs/ROC-CHAT.md
## C1): `call` runs the function `which` names. Every argument and result is
## bytes; a number crosses as its decimal digits, a missing value as no
## result at all. angry-gopher's chat_twin_test.zig holds each to the Zig
## it replaces. Never linked into a server.
app [call] { pf: platform "twin/platform/main.roc" }

import Time
import ZigText
import Paths

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
		4 =>
			match ZigText.parse_u64(arg(0)) {
				Ok(n) => [Str.to_utf8(U64.to_str(n))]
				Err(None) => []
			}
		5 => [ZigText.json_string(arg(0))]
		6 => [ZigText.trim(arg(0))]
		7 => [bool(Paths.participant(arg(0), arg(1)))]
		8 => [Paths.pair_key(arg(0), arg(1))]
		9 => [bool(Paths.valid_topic_id(arg(0)))]
		10 => [bool(Paths.valid_channel_name(arg(0)))]
		11 => [bool(Paths.valid_msg_ref_id(arg(0)))]
		12 => [Paths.join(req.args)]
		13 => [Paths.first_of(req.args)]
		14 => [Paths.transcript_path(arg(0), arg(1))]
		_ => crash "twin: no function ${U8.to_str(req.which)}"
	}
}

bool : Bool -> List(U8)
bool = |b| if b [49] else [48]

## A signed decimal the test wrote.
int : List(U8) -> I64
int = |digits| match digits {
	[45, .. as rest] => 0 - List.fold(rest, 0, |n, c| n * 10 + U8.to_i64(c - 48))
	_ => List.fold(digits, 0, |n, c| n * 10 + U8.to_i64(c - 48))
}
