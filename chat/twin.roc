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
import Conversation
import Accounts
import Fanout
import Uid

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
		7 => [bool(Paths.participant(arg(0), Uid.from_bytes(arg(1))))]
		8 => [Paths.pair_key(Uid.from_bytes(arg(0)), Uid.from_bytes(arg(1)))]
		9 => [bool(Paths.valid_topic_id(arg(0)))]
		10 => [bool(Paths.valid_channel_name(arg(0)))]
		11 => [bool(Paths.valid_msg_ref_id(arg(0)))]
		12 => [Paths.join(req.args)]
		13 => [Paths.first_of(req.args)]
		# A DM's folder is its key as joined, so any `arg(0)` stands for a folder.
		14 => [Paths.transcript_path(Dm, { key: arg(0), topic: arg(1) })]
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
			match Count.window_last(u64(arg(0)), arg(1), if arg(2) == [49] Full else Partial, arg(3)) {
				Ok(w) => [num(w.number), bool(w.record == Current), w.msg.id, w.msg.from, w.msg.at, w.msg.uid, w.msg.markdown]
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
				Reacted(r) => [[82], num(r.msg), r.emoji, bool(Reaction.is_added(r.change))]
				Bad(why) => [[66], why]
				Malformed => [[77]]
			}
		29 => [bool(Reaction.valid_emoji(arg(0)))]
		30 => [Chrome.page({ tab: arg(0), title: arg(1), viewer: arg(2), active: arg(3), src: srcs(req.args, 5) }, arg(4))]
		31 => [Pages.not_found(srcs(req.args, 3), { viewer: arg(0), what: arg(1), back: arg(2) })]
		32 => [Pages.no_topics(srcs(req.args, 3), { viewer: arg(0), base: arg(1), title: arg(2) })]
		33 => [Pages.no_conversations(srcs(req.args, 1), arg(0))]
		34 => [Pages.sidebar_json(Pages.decode_sidebar(req.args))]
		35 => {
			limits = { image_max: u64(arg(7)), video_max: u64(arg(8)), accept: arg(9), search_min: u64(arg(10)) }
			view = { key: arg(0), base: arg(1), topic: arg(2), title: arg(3), uid: arg(4), viewer: arg(5), sidebar_json: arg(6) }
			[Pages.conversation(srcs(req.args, 11), limits, view)]
		}
		36 => [Html.escape(arg(0))]
		37 => [Html.script_safe(arg(0))]
		38 => [Feeds.images_json(Feeds.images(arg(0)), u64(arg(1)))]
		39 => [Feeds.code_json(Feeds.code(arg(0)))]
		40 => [Recent.excerpt(arg(0))]
		41 => [Recent.json(arg(0), Recent.rows(written(req.args, 1, [])))]
		42 => [ChatState.resume_topic(List.drop_first(req.args, 2), arg(0), int(arg(1)))]
		43 =>
			match ChatState.pinned(arg(0), arg(1), if arg(2) == [49] Pinned else Unpinned) {
				Write(bytes) => [bytes]
				Remove => []
			}
		44 =>
			match Conversation.dm_other(arg(0), Uid.from_bytes(arg(1))) {
				Ok(other) => [Uid.bytes(other)]
				Err(None) => []
			}
		45 => Conversation.dm_members(arg(0))
		46 => [Conversation.dm_title(arg(0), arg(1))]
		47 => [Conversation.channel_title(arg(0))]
		48 => [Conversation.topic_title(arg(0), arg(1))]
		49 => [bool(Conversation.has_topic(List.drop_first(req.args, 1), arg(0)))]
		50 => [Conversation.dm_base(arg(0)), Conversation.channel_base(arg(0))]
		51 => Paths.member_channels(flat_rosters(req.args, 1, []), arg(0))
		52 => [ChatState.bookmark(file(arg(0), arg(1)))]
		53 => [bool(ChatState.changed(file(arg(0), arg(1)), arg(2))), ChatState.bookmark_line(arg(2))]
		54 => List.map([Paths.last_conv_path(arg(0)), Paths.last_session_path(arg(0), arg(1)), Paths.pinned_path(arg(0), arg(1)), Paths.feed_path(arg(0), Images), Paths.feed_path(arg(0), Code)], Paths.bytes)
		55 => Paths.topics(entries(req.args, 0, []))
		56 =>
			match Paths.channel_members(arg(0)) {
				Ok(members) => List.prepend(members, [79])
				Err(Malformed) => [[77]]
			}
		57 => Paths.channel_names(entries(req.args, 0, []))
		58 => {
			# The names, then as many reads (how, bytes); the malformed
			# count and names, then each roster as `name, count, member...`.
			n = u64(arg(0))
			names = List.sublist(req.args, { start: 1, len: n })
			got = Paths.rosters(names, reads(req.args, 1 + n, []))
			List.join([[num(List.len(got.malformed))], got.malformed, List.join(List.map(got.rosters, |r| List.concat([r.name, num(List.len(r.members))], r.members)))])
		}
		59 => [Paths.sessions_dir(Paths.dm_conv_dir(arg(0))), Paths.sessions_dir(Paths.channel_conv_dir(arg(1))), Paths.bytes(Paths.channel_path(valid_channel(arg(1)))), Paths.bytes(Paths.reactions_path(Dm, { key: arg(0), topic: arg(2) }))]
		60 => {
			# The ids asked, then the accounts (`accounts`): each id's exists
			# and its name (`ok, name`, or the failure `unreadable`), then the
			# authorized roster (`ok`, then `id, name` pairs; or its failure).
			n = u64(arg(0))
			ids = List.sublist(req.args, { start: 1, len: n })
			all = accounts(req.args, 1 + n, [])
			asked = List.join(
				List.map(
					ids,
					|id|
						match Accounts.name(all, id) {
							Ok(name) => [bool(Accounts.exists(all, id)), Str.to_utf8("ok"), name]
							Err(why) => List.concat([bool(Accounts.exists(all, id))], unreadable(why))
						},
				),
			)
			roster = match Accounts.authorized(all) {
				Ok(members) => List.concat([Str.to_utf8("ok")], List.join(List.map(members, |a| [a.id, a.name])))
				Err(why) => unreadable(why)
			}
			List.concat(asked, roster)
		}
		61 => [Reaction.line({ msg: u64(arg(0)), uid: arg(1), from: arg(2), emoji: arg(3), change: if arg(4) == [49] Added else Removed, at: arg(5) })]
		# The fan-out: member `arg(0)`'s five keys; conversation `arg(0)`'s
		# URL root, topic `arg(1)`'s page and message `arg(2)`'s link.
		62 => [Fanout.notify_key(arg(0)), Fanout.sidebar_key(arg(0)), Fanout.recent_key(arg(0)), Fanout.images_key(arg(0)), Fanout.code_key(arg(0))]
		63 => [Feeds.base_url(arg(0)), Fanout.topic_url({ key: arg(0), topic: arg(1) }), Feeds.source_url(arg(0), arg(2))]
		# A DM's (`d`) or a channel's notify event: from, key, topic.
		64 => {
			kind = if arg(0) == [100] Dm else Channel
			at = { key: arg(2), topic: arg(3) }
			[Fanout.notify_event(at, Fanout.notify_text(kind, arg(1), at))]
		}
		65 => [Fanout.topic_added({ key: arg(0), topic: arg(1) })]
		66 => [Recent.chat_event({ at: arg(0), url: arg(1), who: arg(2), label: arg(3), topic: arg(4), excerpt: arg(5), dm: if arg(6) == [49] Dm else Channel })]
		# An entry's header (source_id, from, conv, at), then its tags: the
		# images.md entry and the live event.
		67 => {
			h = { source_id: arg(0), from: arg(1), conv: arg(2), at: arg(3) }
			tags = List.drop_first(req.args, 4)
			[Feeds.images_entry(h, tags), Feeds.images_event(h, tags)]
		}
		# The same header, then `lang, body` pairs: the code.md entry and the
		# live event.
		68 => {
			h = { source_id: arg(0), from: arg(1), conv: arg(2), at: arg(3) }
			blocks = pairs(req.args, 4, [])
			[Feeds.code_entry(h, blocks), Feeds.code_event(h, blocks)]
		}
		# recentWhere for viewer `arg(1)` in a DM (`d`) or channel keyed
		# `arg(2)`: the members counted by `arg(3)`, then the accounts.
		69 => {
			n = u64(arg(3))
			members = List.sublist(req.args, { start: 4, len: n })
			all = accounts(req.args, 4 + n, [])
			kind = if arg(0) == [100] Dm else Channel
			[Fanout.recent_where({ kind, key: arg(2), members, topic: [], index: 0, id: [], from: [], at: [], uid: [], accounts: all }, arg(1))]
		}
		_ => crash "twin: no function ${U8.to_str(req.which)}"
	}
}

bool : Bool -> List(U8)
bool = |b| if b [49] else [48]

## A channel's name the test hands as valid; one that is not stops the twin.
valid_channel : List(U8) -> Paths.ChannelName
valid_channel = |name| match Paths.channel_name(name) {
	Ok(valid) => valid
	Err(Invalid) => crash "twin: an invalid channel name"
}

## A read as the test says it went: `F` found (`bytes` the file), `M`
## missing, anything else failed.
file : List(U8), List(U8) -> [Found(List(U8)), Missing, Failed]
file = |how, bytes| match how {
	[70] => Found(bytes)
	[77] => Missing
	_ => Failed
}

## A folder's entries as the test wrote them: `kind, name` pairs from
## argument `i`, the kind `d`, `f` or `o`.
entries : List(List(U8)), U64, List(Paths.Entry) -> List(Paths.Entry)
entries = |args, i, out|
	match (List.get(args, i), List.get(args, i + 1)) {
		(Ok(k), Ok(name)) => {
			kind = match k {
				[100] => Dir
				[102] => File
				_ => Other
			}
			entries(args, i + 2, List.append(out, { kind, name }))
		}
		_ => out
	}

## Accounts as the test wrote them: `id, kind, name_read, name` from
## argument `i`, the kind `a` (the agent), `m` (a member), `u` (its
## password's stat failed) or anything else (a guest); the name read `u`
## when it failed, anything else when it read.
accounts : List(List(U8)), U64, List(Accounts.Account) -> List(Accounts.Account)
accounts = |args, i, out|
	match (List.get(args, i), List.get(args, i + 1), List.get(args, i + 2), List.get(args, i + 3)) {
		(Ok(id), Ok(k), Ok(r), Ok(name)) => {
			kind = match k {
				[97] => Agent
				[109] => Member
				[117] => Unreadable
				_ => Guest
			}
			name_read = if r == [117] Unreadable else Found
			accounts(args, i + 4, List.append(out, { id, kind, name, name_read }))
		}
		_ => out
	}

## A lookup's failure, as the test reads it: `kind` or `name`, then whose.
unreadable : Accounts.Unreadable -> List(List(U8))
unreadable = |why|
	match why {
		KindUnreadable(id) => [Str.to_utf8("kind"), id]
		NameUnreadable(id) => [Str.to_utf8("name"), id]
	}

## Code blocks as the test wrote them, `lang, body` pairs from `i`.
pairs : List(List(U8)), U64, List(Feeds.Block) -> List(Feeds.Block)
pairs = |args, i, out|
	match (List.get(args, i), List.get(args, i + 1)) {
		(Ok(lang), Ok(body)) => pairs(args, i + 2, List.append(out, { lang, body }))
		_ => out
	}

## Reads as the test says they went (`file`), `how, bytes` pairs from `i`.
reads : List(List(U8)), U64, List([Found(List(U8)), Missing, Failed]) -> List([Found(List(U8)), Missing, Failed])
reads = |args, i, out|
	match (List.get(args, i), List.get(args, i + 1)) {
		(Ok(how), Ok(bytes)) => reads(args, i + 2, List.append(out, file(how, bytes)))
		_ => out
	}

## Rosters flat, `name, count, member...` each, from argument `i`.
flat_rosters : List(List(U8)), U64, List(Paths.Roster) -> List(Paths.Roster)
flat_rosters = |args, i, out|
	match List.get(args, i) {
		Err(_) => out
		Ok(name) => {
			n = u64(List.get(args, i + 1) ?? [])
			flat_rosters(args, i + 2 + n, List.append(out, { name, members: List.sublist(args, { start: i + 2, len: n }) }))
		}
	}

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
srcs = |args, from| Chrome.src_in(scripts(args, from, []))

scripts : List(List(U8)), U64, List({ name : List(U8), src : List(U8) }) -> List({ name : List(U8), src : List(U8) })
scripts = |args, i, out|
	match (List.get(args, i), List.get(args, i + 1)) {
		(Ok(name), Ok(src)) => scripts(args, i + 2, List.append(out, { name, src }))
		_ => out
	}

## The recent rows as the host writes them, nine arguments each from `i` on:
## doc, secs, uid, name, key, label, topic, markdown, dm (doc and dm "1"
## or "0").
written : List(List(U8)), U64, List(Recent.Written) -> List(Recent.Written)
written = |args, i, out|
	if i + 9 > List.len(args) {
		out
	} else {
		at = |k| List.get(args, i + k) ?? []
		written(args, i + 9, List.append(out, { kind: if at(0) == ['1'] Doc else Message, secs: at(1), uid: at(2), name: at(3), key: at(4), label: at(5), topic: at(6), markdown: at(7), dm: if at(8) == ['1'] Dm else Channel }))
	}
