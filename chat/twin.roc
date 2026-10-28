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
import JsonOut
import Route
import Limits
import Saved
import Search
import BusKey
import ChatUrl

call : { which : U8, args : List(List(U8)) } -> List(List(U8))
call = |req| {
	arg = |i| List.get(req.args, i) ?? []
	match req.which {
		1 => [Str.to_utf8(Time.rfc3339(int(arg(0))))]
		2 => [Str.to_utf8(Time.date(int(arg(0))))]
		3 =>
			match Time.unix_from_rfc3339(arg(0)) {
				Ok(n) => [Str.to_utf8(I64.to_str(n))]
				Err(NotADate) => []
			}
		4 =>
			match ZigText.parse_u64(arg(0)) {
				Ok(n) => [Str.to_utf8(U64.to_str(n))]
				Err(NotANumber) | Err(TooBig) => []
			}
		5 =>
		# Text only: bytes that are not UTF-8 are refused, no answer.
			match Str.from_utf8(arg(0)) {
				Ok(t) => [ZigText.json_string(t)]
				Err(_) => []
			}
		6 => [ZigText.trim(arg(0))]
		# A key that is no canonical pair is no PairKey, so no participant.
		7 =>
			match pair_of(arg(0)) {
				Ok(pair) => [bool(Uid.from_utf8(arg(1)).map_ok(|u| pair.is_participant(u)) == Ok(Bool.True))]
				Err(_) => [bool(Bool.False)]
			}
		# Two uids that are canonical numbers make a key; any other half
		# is no Uid (the Zig's atoiOr0 read it as 0), and no answer.
		8 =>
			match (Uid.from_utf8(arg(0)), Uid.from_utf8(arg(1))) {
				(Ok(a), Ok(b)) => [Paths.pair_key(a, b).bytes()]
				_ => []
			}
		# Bytes that are not UTF-8 are no text, so neither a topic nor a name.
		9 => [bool(text(arg(0)).map_ok(Paths.is_topic_id) == Ok(Bool.True))]
		10 => [bool(text(arg(0)).map_ok(Paths.is_channel_name) == Ok(Bool.True))]
		11 => [bool(Paths.is_valid_msg_ref_id(arg(0)))]
		# A topic is text: a listing's names (Files.list!'s door skips one
		# that is not UTF-8).
		13 => [Paths.first_of(List.keep_oks(req.args, Str.from_utf8)).to_utf8()]
		# A conversation's key and a topic id; the door refuses any other.
		14 =>
			match topic_at(arg(0), arg(1)) {
				Ok(at) => [Paths.transcript_path(at).bytes()]
				Err(Invalid) => []
			}
		15 => {
			match Transcript.decode_file(arg(0)) {
				Ok(d) => List.fold(
					d.messages,
					[Str.to_utf8(U64.to_str(d.refused))],
					|out, m| List.concat(
						out,
						[
							m.id,
							m.from,
							m.at,
							author_bytes(m.uid),
							m.markdown,
						],
					),
				)
				Err(CorruptUid(_)) => []
			}
		}
		# An empty uid is nobody; any other that is no canonical uid is no
		# message, and no answer.
		16 =>
			match author_of(arg(4)) {
				Ok(uid) => [
					Transcript.stored_form(
						u64(arg(0)),
						{
							id: arg(1),
							from: arg(2),
							at: arg(3),
							uid,
							markdown: arg(5),
						},
					),
				]
				Err(NotAUid) => []
			}
		17 => [num(Count.count_blocks(arg(0)))]
		18 => maybe(Count.number_in(arg(0), arg(1)))
		19 => maybe(Count.index_of(arg(0), arg(1)))
		20 =>
			match Count.parse(arg(0)) {
				Ok(
					{
						count,
						size,
						last: Known(l),
					},
				) => [
					num(count),
					num(size),
					num(l.offset),
					l.uid,
				]
				Ok(
					{
						count,
						size,
						last: Unknown,
					},
				) => [num(count), num(size)]
				Err(Malformed) => []
			}
		21 => {
			last = if List.len(req.args) == 4 Known({
				offset: u64(arg(2)),
				uid: arg(3),
			}) else Unknown
			[
				Count.text(
					u64(arg(0)),
					u64(arg(1)),
					last,
				),
			]
		}
		22 => maybe(Count.believed(Count.parse(arg(0)), u64(arg(1))))
		23 =>
			match Count.recorded_author(
				Count.parse(arg(0)),
				u64(arg(1)),
				u64(arg(2)),
			) {
				Ok(uid) => [uid]
				Err(NotRecorded) => []
			}
		24 =>
			match Count.window_last(
				u64(arg(0)),
				arg(1),
				if arg(2) == [49] Full else Partial,
				arg(3),
			) {
				Ok(w) => [
					num(w.number),
					bool(w.record == Current),
					w.msg.id,
					w.msg.from,
					w.msg.at,
					author_bytes(w.msg.uid),
					w.msg.markdown,
				]
				Err(NotBelieved) => []
				Err(CorruptUid(_)) => [Str.to_utf8("CorruptUid")]
			}
		# Its author, stamp, html, markdown, id and cid are text.
		25 =>
			match (
				Uid.from_utf8(arg(2)),
				texts([
					arg(1),
					arg(3),
					arg(4),
					arg(5),
					arg(6),
					arg(7),
				]),
			) {
				(
					Ok(from_uid),
					Ok(
						[
							from,
							at,
							html,
							markdown,
							id,
							cid,
						],
					),
				) => [
					Frame.message({
						index: u64(arg(0)),
						from,
						from_uid,
						at,
						html,
						markdown,
						id,
						cid,
					}),
				]
				_ => []
			}
		26 => [Frame.reaction(arg(0))]
		27 =>
			match Str.from_utf8(arg(1)).map_ok(|name| Form.field(arg(0), name)) {
				Ok(Found(v)) => [[70], Str.to_utf8(v)]
				Ok(Missing) => []
				Ok(Malformed) | Err(_) => [[77]]
			}
		28 =>
			match Reaction.form(arg(0)) {
				Reacted(r) => [
					[82],
					num(r.msg),
					r.emoji.to_utf8(),
					bool(Reaction.is_added(r.change)),
				]
				Bad(why) => [[66], why]
				Malformed => [[77]]
			}
		# Bytes that are not UTF-8 are no glyph: the form refuses them first.
		29 => [bool(text(arg(0)).map_ok(Reaction.is_valid_emoji) == Ok(Bool.True))]
		# A heading's title, viewer and active item are text.
		30 =>
			match texts([
				arg(1),
				arg(2),
				arg(3),
			]) {
				Ok(
					[
						title,
						viewer,
						active,
					],
				) => [
					Html.bytes(
						Chrome.page(
							{
								tab: Html.host_markup(arg(0)),
								title,
								viewer,
								active,
								src: srcs(req.args, 5),
							},
							Html.host_markup(arg(4)),
						),
					),
				]
				_ => []
			}
		31 =>
			match texts([
				arg(0),
				arg(1),
				arg(2),
			]) {
				Ok(
					[
						viewer,
						what,
						back,
					],
				) => [
					Html.bytes(
						Pages.not_found(
							srcs(req.args, 3),
							{
								viewer,
								what,
								back,
							},
						),
					),
				]
				_ => []
			}
		32 =>
			match texts([
				arg(0),
				arg(1),
				arg(2),
			]) {
				Ok(
					[
						viewer,
						base,
						title,
					],
				) => [
					Html.bytes(
						Pages.no_topics(
							srcs(req.args, 3),
							{
								viewer,
								base,
								title,
							},
						),
					),
				]
				_ => []
			}
		33 =>
			match text(arg(0)) {
				Ok(viewer) => [Html.bytes(Pages.no_conversations(srcs(req.args, 1), viewer))]
				Err(Invalid) => []
			}
		34 =>
			match Pages.decode_sidebar(req.args) {
				Ok(sb) => [Html.script_json_bytes(Pages.sidebar_json(sb))]
				Err(NotAUid) | Err(NotUtf8) | Err(NotACount) => []
			}
		35 => {
			limits = {
				image_max: u64(arg(7)),
				video_max: u64(arg(8)),
				accept: arg(9),
				search_min: u64(arg(10)),
			}
			match (
				texts([
					arg(0),
					arg(1),
					arg(2),
					arg(3),
					arg(5),
				]),
				Uid.from_utf8(arg(4)),
			) {
				(
					Ok(
						[
							key,
							base,
							topic,
							title,
							viewer,
						],
					),
					Ok(uid),
				) => {
					view = {
						key,
						base,
						topic,
						title,
						uid,
						viewer,
						sidebar_json: Html.twin_script_json(arg(6)),
					}
					[
						Html.bytes(
							Pages.conversation(
								srcs(req.args, 11),
								limits,
								view,
							),
						),
					]
				}
				_ => []
			}
		}
		36 => [Html.bytes(Html.escape(arg(0)))]
		37 => [Html.script_json_bytes(Html.script_safe(arg(0)))]
		# A feed file is text (Files.read!'s door): the twin refuses any other.
		38 =>
			match text(arg(0)) {
				Ok(file) => [Feeds.images_json(Feeds.images(file), u64(arg(1)))]
				Err(Invalid) => []
			}
		39 =>
			match text(arg(0)) {
				Ok(file) => [Feeds.code_json(Feeds.code(file))]
				Err(Invalid) => []
			}
		40 =>
			match text(arg(0)) {
				Ok(md) => [Recent.excerpt(md).to_utf8()]
				Err(Invalid) => []
			}
		41 =>
			match (
				Uid.from_utf8(arg(0)),
				Recent.rows(
					written(
						req.args,
						1,
						[],
					),
				),
			) {
				(Ok(me), Ok(rows)) => [Recent.json(me, rows)]
				_ => []
			}
		# The topics are a listing's, text (Files.list!'s door skips the rest).
		42 => [
			ChatState.resume_topic(
				List.keep_oks(List.drop_first(req.args, 2), Str.from_utf8),
				valid_text(arg(0)),
				int(arg(1)),
			).to_utf8(),
		]
		43 =>
			match ChatState.pinned(
				valid_text(arg(0)),
				valid_text(arg(1)),
				if arg(2) == [49] Pin else Unpin,
			) {
				Write(bytes) => [bytes]
				Remove => []
			}
		44 =>
			match (pair_of(arg(0)), Uid.from_utf8(arg(1))) {
				(Ok(pair), Ok(me)) =>
					match Conversation.dm_other(pair, me) {
						Ok(other) => [other.to_str().to_utf8()]
						Err(NotAParticipant) => []
					}
				_ => []
			}
		45 => Conversation.dm_members(arg(0))
		# The partner is a Uid; the door refuses any other.
		46 =>
			match (text(arg(0)), Uid.from_utf8(arg(1))) {
				(Ok(name), Ok(other)) => [Conversation.dm_title(name, other).to_utf8()]
				_ => []
			}
		# A channel's title is made for a channel's name alone.
		47 =>
			match channel_of(arg(0)) {
				Ok(name) => [Conversation.channel_title(name).to_utf8()]
				Err(_) => []
			}
		# The topic is text (a TopicAt's); a topic that is not has no title.
		48 =>
			match texts([arg(0), arg(1)]) {
				Ok([title, topic]) => [Conversation.topic_title(title, topic).to_utf8()]
				_ => []
			}
		# The topics and the topic are text; a topic that is not is none.
		49 =>
			match Str.from_utf8(arg(0)) {
				Ok(topic) => [
					bool(
						Conversation.has_topic(
							List.keep_oks(List.drop_first(req.args, 1), Str.from_utf8),
							topic,
						),
					),
				]
				Err(_) => [bool(Bool.False)]
			}
		50 => [Conversation.dm_base(arg(0)), Conversation.channel_base(arg(0))]
		# A uid that is no Uid is in no roster: the door refuses it.
		51 =>
			match Uid.from_utf8(arg(0)) {
				Ok(uid) => List.map(
					Paths.member_channels(
						flat_rosters(
							req.args,
							1,
							[],
						),
						uid,
					),
					Str.to_utf8,
				)
				Err(NotAUid) => []
			}
		52 => [ChatState.bookmark(file(arg(0), arg(1))).to_utf8()]
		53 => [
			bool(ChatState.is_changed(file(arg(0), arg(1)), valid_text(arg(2)))),
			ChatState.bookmark_line(valid_text(arg(2))),
		]
		# A uid that is no Uid has no paths: the door refuses it.
		54 =>
			match (Uid.from_utf8(arg(0)), conv_of(arg(1))) {
				(Ok(u), Ok(key)) => List.map(
					[
						Paths.last_conv_path(u),
						Paths.last_session_path(u, key),
						Paths.pinned_path(u, key),
						Paths.feed_path(u, Images),
						Paths.feed_path(u, Code),
					],
					|p| p.bytes(),
				)
				_ => []
			}
		55 => List.map(
			Paths.topics(
				entries(
					req.args,
					0,
					[],
				),
			),
			Str.to_utf8,
		)
		56 =>
			match Paths.channel_members(valid_text(arg(0))) {
				Ok(members) => List.prepend(List.map(members, |u| u.to_str().to_utf8()), [79])
				Err(Malformed) => [[77]]
			}
		57 => List.map(
			Paths.channel_names(
				entries(
					req.args,
					0,
					[],
				),
			),
			Str.to_utf8,
		)
		58 => {
			# The names, then as many reads (how, bytes); the malformed
			# count and names, then each roster as `name, count, member...`.
			# The names are a listing's, text at Files.list!'s door.
			n = u64(arg(0))
			names = List.keep_oks(List.sublist(req.args, { start: 1, len: n }), Str.from_utf8)
			got = Paths.rosters(
				names,
				reads(
					req.args,
					1 + n,
					[],
				),
			)
			List.join([
				[num(List.len(got.malformed))],
				List.map(got.malformed, Str.to_utf8),
				List.join(
					List.map(
						got.rosters,
						|r| List.concat(
							[r.name.to_utf8(), num(List.len(r.members))],
							List.map(r.members, |u| u.to_str().to_utf8()),
						),
					),
				),
			])
		}
		59 => {
			dm = Dm(valid_pair(arg(0)))
			channel = valid_channel(arg(1))
			match topic_at(arg(0), arg(2)) {
				Ok(at) => List.map(
					[
						Paths.topics_folder(dm),
						Paths.topics_folder(Channel(channel)),
						Paths.channel_path(channel),
						Paths.reactions_path(at),
					],
					|p| p.bytes(),
				)
				Err(Invalid) => []
			}
		}
		60 => {
			# The ids asked, then the accounts (`accounts`): each id's exists
			# and its name (`ok, name`, or the failure `unreadable`), then the
			# authorized roster (`ok`, then `id, name` pairs; or its failure).
			n = u64(arg(0))
			# An id that is no Uid is asked nothing: the door refuses it.
			ids = List.keep_oks(List.sublist(req.args, { start: 1, len: n }), Uid.from_utf8)
			# Accounts that will not decode (an id that is no uid) are refused
			# whole, as main's load_accounts! door fails the request; a name
			# that is not UTF-8 is that account's, listed as unreadable.
			match List.map_try(
				accounts(
					req.args,
					1 + n,
					[],
				),
				Accounts.from_host,
			) {
				Ok(all) => account_answers(ids, all)
				Err(_) => []
			}
		}
		61 =>
			match (
				Uid.from_utf8(arg(1)),
				Str.from_utf8(arg(5)),
				texts([arg(2), arg(3)]),
			) {
				(
					Ok(uid),
					Ok(at),
					Ok([from, emoji]),
				) => [
					Reaction.line({
						msg: u64(arg(0)),
						uid,
						from,
						emoji,
						change: if arg(4) == [49] Added else Removed,
						at,
					}),
				]
				_ => []
			}
		# The fan-out: member `arg(0)`'s five keys; conversation `arg(0)`'s
		# URL root, topic `arg(1)`'s page and message `arg(2)`'s link.
		# A member that is no Uid has no keys: the door refuses it.
		62 =>
			match Uid.from_utf8(arg(0)) {
				Ok(u) => [
					BusKey.notify(u).bytes(),
					BusKey.sidebar(u).bytes(),
					BusKey.recent(u).bytes(),
					BusKey.images(u).bytes(),
					BusKey.code(u).bytes(),
				]
				Err(NotAUid) => []
			}
		# A conversation's key, a topic id and a message id (text); the door
		# refuses any other.
		63 =>
			match (topic_at(arg(0), arg(1)), texts([arg(0), arg(2)])) {
				(Ok(at), Ok([conv, id])) => [
					ChatUrl.feed_conv(conv).to_str().to_utf8(),
					ChatUrl.topic(at).to_str().to_utf8(),
					ChatUrl.source(conv, id).to_str().to_utf8(),
				]
				_ => []
			}
		# The notify event: from, key, topic (a DM's or a channel's, by its key).
		64 =>
			match (topic_at(arg(1), arg(2)), text(arg(0))) {
				(Ok(at), Ok(from)) => [Fanout.notify_event(at, Fanout.notify_text(from, at))]
				_ => []
			}
		65 =>
			match topic_at(arg(0), arg(1)) {
				Ok(at) => [Fanout.topic_added(at)]
				Err(Invalid) => []
			}
		# Every field of a row is text.
		66 =>
			match texts(List.take_first(req.args, 6)) {
				Ok(
					[
						at,
						url,
						who,
						label,
						topic,
						excerpt,
					],
				) => [
					Recent.chat_event({
						at,
						url,
						who,
						label,
						topic,
						excerpt,
						dm: if arg(6) == [49] Dm else Channel,
					}).bytes(),
				]
				_ => []
			}
		# An entry's header (source_id, from, conv, at), then its tags: the
		# images.md entry and the live event. All text, or no entry.
		67 =>
			match texts(req.args) {
				Ok(
					[
						source_id,
						from,
						conv,
						at,
						.. as tags,
					],
				) => {
					h = {
						source_id,
						from,
						conv,
						at,
					}
					[Feeds.images_entry(h, tags), Feeds.images_event(h, tags).bytes()]
				}
				_ => []
			}
		# The same header, then `lang, body` pairs: the code.md entry and the
		# live event. All text, or no entry.
		68 =>
			match texts(req.args) {
				Ok(
					[
						source_id,
						from,
						conv,
						at,
						.. as rest,
					],
				) => {
					h = {
						source_id,
						from,
						conv,
						at,
					}
					blocks = pairs(
						rest,
						0,
						[],
					)
					[Feeds.code_entry(h, blocks), Feeds.code_event(h, blocks).bytes()]
				}
				_ => []
			}
		# recentWhere for viewer `arg(1)` in a DM (`d`) or channel keyed
		# `arg(2)`: the members counted by `arg(3)`, then the accounts.
		# A viewer or member that is no Uid has no row: the door refuses it.
		69 => {
			n = u64(arg(3))
			given = List.sublist(req.args, { start: 4, len: n })
			members = List.keep_oks(given, Uid.from_utf8)
			decoded = List.map_try(
				accounts(
					req.args,
					4 + n,
					[],
				),
				Accounts.from_host,
			)
			key = if arg(0) == [100] Dm(valid_pair(arg(2))) else Channel(valid_channel(arg(2)))
			match (Uid.from_utf8(arg(1)), decoded) {
				(Ok(viewer), Ok(all)) if List.len(members) == n => [
					Fanout.recent_where(
						{
							key,
							members,
							topic: "",
							index: 0,
							id: "",
							from: "",
							at: "",
							uid: viewer,
							accounts: all,
						},
						viewer,
					).to_utf8(),
				]
				_ => []
			}
		}
		# JsonOut: the args, each text, as one object: their count, the
		# first, all of them, and whether the count is even. An arg that is
		# not UTF-8 is no case: the door refuses it.
		70 => {
			given_texts = List.keep_oks(req.args, Str.from_utf8)
			n = List.len(given_texts)
			if n != List.len(req.args) {
				[]
			} else {
				[
					JsonOut.object([
						("n", JsonOut.number(n)),
						("first", JsonOut.string(List.first(given_texts) ?? "")),
						("all", JsonOut.array(List.map(given_texts, JsonOut.string))),
						("even", JsonOut.bool(n % 2 == 0)),
					]).bytes(),
				]
			}
		}
		# ChatUrl.on_site: the path when it is on this site, else nothing.
		# Text only: the door refuses bytes that are not UTF-8.
		71 =>
			match Str.from_utf8(arg(0)) {
				Ok(path_text) =>
					match ChatUrl.on_site(path_text) {
						Ok(url) => [url.to_str().to_utf8()]
						Err(NotOnSite) => []
					}
				Err(_) => []
			}
		# The Roc router's parse of `arg(0)` under /chat, or /channel when
		# `arg(1)` is `c`, as what the pre-turn hooks must agree with: an
		# upload, an upload's file, a stream, a doc, or other.
		72 =>
			match Str.from_utf8(arg(0)) {
				Ok(sub) => {
					r = if arg(1) == ['c'] Route.under_channel(sub) else Route.under_chat(sub)
					kind =
						if r.family == Docs {
							"docs"
						} else if Route.is_stream(r) {
							"stream"
						} else if (r.family == Dm or r.family == Channel) and r.part == Topic and r.tail == Upload {
							"upload"
						} else if (r.family == Dm or r.family == Channel) and r.part == Topic and r.tail == Uploads {
							"uploads"
						} else {
							"other"
						}
					[kind.to_utf8()]
				}
				Err(_) => []
			}
		# The limits the conversation page tells its client, the Roc's
		# constants: image, video, accept, search's shortest word.
		73 => [
			Str.to_utf8(U64.to_str(Limits.image_max)),
			Str.to_utf8(U64.to_str(Limits.video_max)),
			Limits.accept.to_utf8(),
			Str.to_utf8(U64.to_str(Limits.search_min)),
		]
		# Saved.refs (parseRefs): each ref's conversation, topic and id, in
		# order.
		74 => List.join(
			List.map(
				Saved.refs(arg(0)),
				|r| [
					r.conv,
					r.topic,
					r.id,
				],
			),
		)
		# Search.excerpt over a hit's window: window, start, length, at,
		# found ("1"), the key's length.
		75 => {
			hit = {
				at: u64(arg(3)),
				length: u64(arg(2)),
				start: u64(arg(1)),
				base: [],
				date: [],
				from: [],
				id: [],
				sid: [],
				window: arg(0),
				found: if arg(4) == [49] Found else Missing,
				kind: Dm,
			}
			ex = Search.excerpt(hit, u64(arg(5)))
			[
				ex.before,
				ex.mark,
				ex.after,
			]
		}
		_ => crash "twin: no function ${U8.to_str(req.which)}"
	}
}

bool : Bool -> List(U8)
bool = |b| if b [49] else [48]

## A channel's name the test hands as valid; one that is not stops the twin.
valid_channel : List(U8) -> Paths.ChannelName
valid_channel = |name| match channel_of(name) {
	Ok(valid) => valid
	Err(_) => crash "twin: an invalid channel name"
}

## A DM's pair key the test hands as valid; one that is not stops the twin.
valid_pair : List(U8) -> Paths.PairKey
valid_pair = |key| match pair_of(key) {
	Ok(valid) => valid
	Err(_) => crash "twin: an invalid pair key"
}

## The test's bytes as text; bytes that are not UTF-8 are `Invalid`, as
## no validated type takes them.
text : List(U8) -> Try(Str, [Invalid])
text = |bytes| Str.from_utf8(bytes).map_err(|_| Invalid)

## The test's bytes as texts, when every one is.
texts : List(List(U8)) -> Try(List(Str), [Invalid])
texts = |all| List.map_try(all, text)

## Text the test hands as valid (a file's, past Files.read!'s door; a form's,
## past its 400); bytes that are not UTF-8 stop the twin.
valid_text : List(U8) -> Str
valid_text = |bytes| match Str.from_utf8(bytes) {
	Ok(t) => t
	Err(_) => crash "twin: text that is not UTF-8"
}

## The test's bytes as a conversation's key: a pair key, else a channel's
## name, when they are text and one.
conv_of : List(U8) -> Try(Paths.ConvKey, [Invalid])
conv_of = |bytes|
	match pair_of(bytes) {
		Ok(pair) => Ok(Dm(pair))
		Err(Invalid) => channel_of(bytes).map_ok(|name| Channel(name))
	}

## A topic's address from the test's key and topic, when the key is one
## (conv_of) and the topic a topic id. **THE DOOR REFUSES ANY OTHER**, so no
## twin feeds a path or an event hostile bytes; roc test covers the door.
topic_at : List(U8), List(U8) -> Try(Paths.TopicAt, [Invalid])
topic_at = |key, topic| {
	conv = conv_of(key)?
	t = text(topic)?
	if Paths.is_topic_id(t) Ok({ key: conv, topic: t }) else Err(Invalid)
}

## The test's bytes as a pair key, when they are text and one.
pair_of : List(U8) -> Try(Paths.PairKey, [Invalid])
pair_of = |bytes| Paths.pair_key_from_str(text(bytes)?)

## The test's bytes as a channel's name, when they are text and one.
channel_of : List(U8) -> Try(Paths.ChannelName, [Invalid])
channel_of = |bytes| Paths.channel_name_from_str(text(bytes)?)

## A read as the test says it went: `F` found (`bytes` the file, text as
## Files.read!'s door hands it), `M` missing, anything else failed.
file : List(U8), List(U8) -> Try(Str, [Missing, Failed])
file = |how, bytes| match how {
	[70] => Ok(valid_text(bytes))
	[77] => Err(Missing)
	_ => Err(Failed)
}

## A folder's entries as the test wrote them: `kind, name` pairs from
## argument `i`, the kind `d`, `f` or `o`. A name that is not UTF-8 is left
## out, as Files.list!'s door leaves it out.
entries : List(List(U8)), U64, List(Paths.Entry) -> List(Paths.Entry)
entries = |
	args,
	i,
	out,
|
	match (List.get(args, i), List.get(args, i + 1)) {
		(Ok(k), Ok(raw)) => {
			kind = match k {
				[100] => Dir
				[102] => File
				_ => Other
			}
			match Str.from_utf8(raw) {
				Ok(name) => entries(
					args,
					i + 2,
					List.append(out, { kind, name }),
				)
				Err(_) => entries(
					args,
					i + 2,
					out,
				)
			}
		}
		_ => out
	}

## Accounts as the test wrote them: `id, kind, name_read, name` from
## argument `i`, the kind `a` (the agent), `m` (a member), `u` (its
## password's stat failed) or anything else (a guest); the name read `u`
## when it failed, anything else when it read: as the host hands them,
## bytes, for Accounts.from_host to decode.
HostAccount : {
	id : List(U8),
	kind : [
		Agent,
		Guest,
		Member,
		Unreadable,
	],
	name : List(U8),
	name_read : [Found, Unreadable],
}

accounts : List(List(U8)), U64, List(HostAccount) -> List(HostAccount)
accounts = |
	args,
	i,
	out,
|
	match (
		List.get(args, i),
		List.get(args, i + 1),
		List.get(args, i + 2),
		List.get(args, i + 3),
	) {
		(
			Ok(id),
			Ok(k),
			Ok(r),
			Ok(name),
		) => {
			kind = match k {
				[97] => Agent
				[109] => Member
				[117] => Unreadable
				_ => Guest
			}
			name_read = if r == [117] Unreadable else Found
			accounts(
				args,
				i + 4,
				List.append(
					out,
					{
						id,
						kind,
						name,
						name_read,
					},
				),
			)
		}
		_ => out
	}

## A lookup's failure, as the test reads it: `kind` or `name`, then whose.
unreadable : Accounts.Unreadable -> List(List(U8))
unreadable = |why|
	match why {
		KindUnreadable(id) => [Str.to_utf8("kind"), id.to_str().to_utf8()]
		NameUnreadable(id) => [Str.to_utf8("name"), id.to_str().to_utf8()]
	}

## Code blocks as the test wrote them, `lang, body` pairs from `i`.
pairs : List(Str), U64, List(Feeds.Block) -> List(Feeds.Block)
pairs = |
	args,
	i,
	out,
|
	match (List.get(args, i), List.get(args, i + 1)) {
		(Ok(lang), Ok(body)) => pairs(
			args,
			i + 2,
			List.append(out, { lang, body }),
		)
		_ => out
	}

## Reads as the test says they went (`file`), `how, bytes` pairs from `i`.
reads : List(List(U8)), U64, List(Try(Str, [Missing, Failed])) -> List(Try(Str, [Missing, Failed]))
reads = |
	args,
	i,
	out,
|
	match (List.get(args, i), List.get(args, i + 1)) {
		(Ok(how), Ok(bytes)) => reads(
			args,
			i + 2,
			List.append(out, file(how, bytes)),
		)
		_ => out
	}

## Rosters flat, `name, count, member...` each, from argument `i`.
flat_rosters : List(List(U8)), U64, List(Paths.Roster) -> List(Paths.Roster)
flat_rosters = |
	args,
	i,
	out,
|
	match List.get(args, i) {
		Err(_) => out
		Ok(name) => {
			n = u64(List.get(args, i + 1) ?? [])
			# A roster's name is a listing's, text at Files.list!'s door.
			roster = Str.from_utf8(name).map_ok(
				|text_name| {
					name: text_name,
					members: List.map(List.sublist(args, { start: i + 2, len: n }), valid_uid),
				},
			)
			flat_rosters(
				args,
				i + 2 + n,
				List.concat(out, List.keep_oks([roster], |r| r)),
			)
		}
	}

## A signed decimal the test wrote.
int : List(U8) -> I64
int = |digits| match digits {
	[45, .. as rest] => 0 - List.fold(
		rest,
		0,
		|n, c| n * 10 + U8.to_i64(c - 48),
	)
	_ => List.fold(
		digits,
		0,
		|n, c| n * 10 + U8.to_i64(c - 48),
	)
}

num : U64 -> List(U8)
num = |n| Str.to_utf8(U64.to_str(n))

u64 : List(U8) -> U64
u64 = |digits| match ZigText.parse_u64(digits) {
	Ok(n) => n
	Err(_) => crash "twin: a numeric argument is no U64; the Zig twin test sent a malformed request"
}

## A number, or nothing whatever the error said.
maybe : Try(U64, _) -> List(List(U8))
maybe = |t| match t {
	Ok(n) => [num(n)]
	Err(_) => []
}

## The scripts' srcs, as `name, src` pairs from argument `from` on.
srcs : List(List(U8)), U64 -> (List(U8) -> Html)
srcs = |args, from| Chrome.src_in(
	scripts(
		args,
		from,
		[],
	),
)

scripts : List(List(U8)),
U64,
List(
	{
		name : List(U8),
		src : List(U8),
	},
) -> List({ name : List(U8), src : List(U8) })
scripts = |
	args,
	i,
	out,
|
	match (List.get(args, i), List.get(args, i + 1)) {
		(Ok(name), Ok(src)) => scripts(
			args,
			i + 2,
			List.append(out, { name, src }),
		)
		_ => out
	}

## The recent rows as the host writes them, nine arguments each from `i` on:
## doc, secs, uid, name, key, label, topic, markdown, dm (doc and dm "1"
## or "0").
written : List(List(U8)), U64, List(Recent.Written) -> List(Recent.Written)
written = |
	args,
	i,
	out,
|
	if i + 9 > List.len(args) {
		out
	} else {
		at = |k| List.get(args, i + k) ?? []
		written(
			args,
			i + 9,
			List.append(
				out,
				{
					kind: if at(0) == ['1'] Doc else Message,
					secs: at(1),
					uid: at(2),
					name: at(3),
					key: at(4),
					label: at(5),
					topic: at(6),
					markdown: at(7),
					dm: if at(8) == ['1'] Dm else Channel,
				},
			),
		)
	}

## Account answers for case 60: each id's exists and name, then the
## authorized roster.
account_answers : List(Uid), List(Accounts.Account) -> List(List(U8))
account_answers = |ids, all| {
	asked = List.join(
		List.map(
			ids,
			|id|
				match Accounts.name(all, id) {
					Ok(name) => [
						bool(Accounts.has_account(all, id)),
						Str.to_utf8("ok"),
						name.to_utf8(),
					]
					Err(why) => List.concat([bool(Accounts.has_account(all, id))], unreadable(why))
				},
		),
	)
	roster = match Accounts.authorized(all) {
		Ok(members) => List.concat(
			[Str.to_utf8("ok")],
			List.join(List.map(members, |a| [a.id.to_str().to_utf8(), a.name.to_utf8()])),
		)
		Err(why) => unreadable(why)
	}
	List.concat(asked, roster)
}

## A message's author as the Zig holds it: its digits, or empty for nobody.
author_bytes : Transcript.Author -> List(U8)
author_bytes = |author| match author {
	By(u) => u.to_str().to_utf8()
	Unattributed => []
}

## The test's author bytes: empty is nobody, else a canonical uid or none.
author_of : List(U8) -> Try(Transcript.Author, [NotAUid])
author_of = |bytes| if bytes == [] Ok(Unattributed) else Uid.from_utf8(bytes).map_ok(|u| By(u))

## A roster member the test hands as a canonical uid; one that is not
## stops the twin.
valid_uid : List(U8) -> Uid
valid_uid = |bytes| match Uid.from_utf8(bytes) {
	Ok(uid) => uid
	Err(NotAUid) => crash "twin: an invalid uid"
}
