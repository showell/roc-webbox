## THE ROC CHAT'S PURE MODULES, BEHIND ONE TEST-ONLY ENTRY (docs/ROC-CHAT.md
## C1): `call` runs the function `which` names. Every argument and result is
## bytes; a number crosses as its decimal digits, a missing value as no
## result at all. angry-gopher's chat_twin_test.zig holds each to the Zig
## it replaces. Never linked into a server.
app [call] { pf: platform "twin/platform/main.roc" }

import Time
import ZigText
import Paths
import Transcript
import Count
import Frame
import Form
import Reaction
import Chrome
import Pages
import Html
import Feeds
import Recent
import ChatState

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
		15 => {
			d = Transcript.decode_file(arg(0))
			List.fold(d.messages, [Str.to_utf8(U64.to_str(d.refused))], |out, m| List.concat(out, [m.id, m.from, m.at, m.uid, m.markdown]))
		}
		16 => [Transcript.stored_form(u64(arg(0)), { id: arg(1), from: arg(2), at: arg(3), uid: arg(4), markdown: arg(5) })]
		17 => [num(Count.count_blocks(arg(0)))]
		18 => maybe(Count.number_in(arg(0), arg(1)))
		19 => maybe(Count.index_of(arg(0), arg(1)))
		20 =>
			match Count.parse(arg(0)) {
				Ok({ count, size, last: Known(l) }) => [num(count), num(size), num(l.offset), l.uid]
				Ok({ count, size, last: Unknown }) => [num(count), num(size)]
				Err(None) => []
			}
		21 => {
			last = if List.len(req.args) == 4 Known({ offset: u64(arg(2)), uid: arg(3) }) else Unknown
			[Count.text(u64(arg(0)), u64(arg(1)), last)]
		}
		22 => maybe(Count.believed(Count.parse(arg(0)), u64(arg(1))))
		23 =>
			match Count.recorded_author(Count.parse(arg(0)), u64(arg(1)), u64(arg(2))) {
				Ok(uid) => [uid]
				Err(None) => []
			}
		24 =>
			match Count.window_last(u64(arg(0)), arg(1), arg(2) == [49], arg(3)) {
				Ok(w) => [num(w.number), bool(w.current), w.msg.id, w.msg.from, w.msg.at, w.msg.uid, w.msg.markdown]
				Err(None) => []
			}
		25 => [Frame.message({ index: u64(arg(0)), from: arg(1), from_uid: arg(2), at: arg(3), html: arg(4), markdown: arg(5), id: arg(6), cid: arg(7) })]
		26 => [Frame.reaction(arg(0))]
		27 =>
			match Form.field(arg(0), arg(1)) {
				Found(v) => [[70], v]
				Missing => []
				Malformed => [[77]]
			}
		28 =>
			match Reaction.form(arg(0)) {
				Reacted(r) => [[82], num(r.msg), r.emoji, bool(r.on)]
				Bad(why) => [[66], why]
				Malformed => [[77]]
			}
		29 => [bool(Reaction.valid_emoji(arg(0)))]
		30 => [Chrome.page({ tab: arg(0), title: arg(1), viewer: arg(2), active: arg(3), src: srcs(req.args, 5) }, arg(4))]
		31 => [Pages.not_found(srcs(req.args, 3), arg(0), arg(1), arg(2))]
		32 => [Pages.no_topics(srcs(req.args, 3), arg(0), arg(1), arg(2))]
		33 => [Pages.no_conversations(srcs(req.args, 1), arg(0))]
		34 => [Pages.sidebar_json(Pages.decode_sidebar(req.args))]
		35 => {
			limits = { image_max: u64(arg(7)), video_max: u64(arg(8)), accept: arg(9), search_min: u64(arg(10)) }
			view = { key: arg(0), base: arg(1), sid: arg(2), title: arg(3), uid: arg(4), viewer: arg(5), sidebar_json: arg(6) }
			[Pages.conversation(srcs(req.args, 11), limits, view)]
		}
		36 => [Html.escape(arg(0))]
		37 => [Html.script_safe(arg(0))]
		38 => [Feeds.images_json(Feeds.images(arg(0)), u64(arg(1)))]
		39 => [Feeds.code_json(Feeds.code(arg(0)))]
		40 => [Recent.excerpt(arg(0))]
		41 => [Recent.json(arg(0), Recent.rows(List.drop_first(req.args, 1)))]
		42 => [ChatState.resume_topic(List.drop_first(req.args, 2), arg(0), int(arg(1)))]
		43 =>
			match ChatState.pinned(arg(0), arg(1), arg(2) == [49]) {
				Write(bytes) => [bytes]
				Remove => []
			}
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

num : U64 -> List(U8)
num = |n| Str.to_utf8(U64.to_str(n))

u64 : List(U8) -> U64
u64 = |digits| ZigText.parse_u64(digits) ?? 0

maybe : Try(U64, [None]) -> List(List(U8))
maybe = |t| match t {
	Ok(n) => [num(n)]
	Err(None) => []
}

## The scripts' srcs, as `name, src` pairs from argument `from` on.
srcs : List(List(U8)), U64 -> (List(U8) -> List(U8))
srcs = |args, from| Chrome.src_in(List.drop_first(args, from))
