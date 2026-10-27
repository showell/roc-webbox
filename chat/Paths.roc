## THE CHAT'S NAMES AND PATHS (angry-gopher chat_paths.zig): which keys,
## topic ids, channel names and message ids are well formed, the DM pair's
## canonical key, and paths joined as Zig's `std.fs.path.join` joins them.
## Pure.
import Bytes
import Uid
import ZigText

Paths := [].{

	## chatKeyParticipant: `user` is one of the pair's two uids (the key is
	## canonical: only pair_key and pair_key_from_str make one).
	is_participant : PairKey, Uid -> Bool
	is_participant = |PairKey.(key), user|
		match key.split_first("_") {
			Err(_) => Bool.False
			Ok({ before, after }) => Uid.to_bytes(user) == before.to_utf8() or Uid.to_bytes(user) == after.to_utf8()
		}

	## **A DM'S KEY**: opaque (`::`), so only `pair_key` (from two uids) and
	## `pair_key_from_str` (from text, validated) make one.
	PairKey :: Str

	## chatPairKey: the smaller numeric id first, joined by `_` (a number
	## past i64's counts as 0, as Zig's `atoiOr0`). **A UID IS DIGITS, THE
	## FIRST NOT ZERO** (allocateUser's), or there is no key: the Zig's
	## `atoiOr0` read any other half as 0 too, and no account has such an
	## id. Uid stays bytes (the host's me! and the accounts hand it so); its
	## digits are ASCII, so they are text.
	pair_key : Uid, Uid -> Try(PairKey, [Invalid])
	pair_key = |ua, ub| {
		a = uid_text(ua)?
		b = uid_text(ub)?
		(small, large) = if atoi_or0(a.to_utf8()) <= atoi_or0(b.to_utf8()) (a, b) else (b, a)
		Ok(PairKey.("${small}_${large}"))
	}

	## A canonical uid's digits, as text.
	uid_text : Uid -> Try(Str, [Invalid])
	uid_text = |uid| {
		digits = Uid.to_bytes(uid)
		if canonical_uid(digits) Str.from_utf8(digits).map_err(|_| Invalid) else Err(Invalid)
	}

	## The key, when it is exactly the canonical `<small>_<large>` of two
	## valid uids, or `<uid>_<uid>`: the DM with yourself (`1_1`) is one.
	pair_key_from_str : Str -> Try(PairKey, [Invalid])
	pair_key_from_str = |key|
		match key.split_first("_") {
			Ok({ before, after }) =>
				match pair_key(Uid.from_bytes(before.to_utf8()), Uid.from_bytes(after.to_utf8())) {
					Ok(PairKey.(made)) if made == key => Ok(PairKey.(key))
					_ => Err(Invalid)
				}
			Err(_) => Err(Invalid)
		}

	## The key's text.
	pair_key_to_str : PairKey -> Str
	pair_key_to_str = |PairKey.(s)| s

	## The key's bytes, where they go back out.
	pair_key_bytes : PairKey -> List(U8)
	pair_key_bytes = |PairKey.(s)| s.to_utf8()

	## **WHICH CONVERSATION**: a DM, by its canonical pair key, two uids
	## joined by `_`, the smaller first (`3_7`; pair_key); or a channel, by
	## its name, a letter then letters, digits and hyphens (`general`;
	## channel_name).
	ConvKey : [Dm(PairKey), Channel(ChannelName)]

	## The key's bytes, where it goes back out (a URL, a bus key, a JSON
	## field, a host call): the pair key or the channel's name.
	conv_key_bytes : ConvKey -> List(U8)
	conv_key_bytes = |key|
		match key {
			Dm(pair) => pair_key_bytes(pair)
			Channel(name) => channel_name_bytes(name)
		}

	## The key's family: a DM's or a channel's.
	conv_kind : ConvKey -> [Dm, Channel]
	conv_kind = |key|
		match key {
			Dm(_) => Dm
			Channel(_) => Channel
		}

	## A uid as allocateUser writes one: digits, the first not zero.
	canonical_uid : List(U8) -> Bool
	canonical_uid = |s| match s {
		[first, ..] => first != '0' and List.all(s, |c| c >= '0' and c <= '9')
		[] => Bool.False
	}

	## decimal.parseInt at i64, or 0.
	atoi_or0 : List(U8) -> U64
	atoi_or0 = |s| match ZigText.parse_u64(s) {
		Ok(n) => if n <= 9223372036854775807 n else 0
		Err(NotANumber) | Err(TooBig) => 0
	}

	## **WHERE A TOPIC IS**: its conversation, then the topic within it. The
	## pair is the topic's whole address: `<key>/<topic>` is its live bus
	## key, and its page is the conversation's URL root then `/<topic>`
	## (/chat/c/<key>/<topic> for a DM, /channel/<key>/<topic> for a channel).
	TopicAt : {
		## The conversation (ConvKey): a DM's pair key or a channel's name,
		## each validated where the request came in. Its bytes (`3_7`,
		## `general`; conv_key_bytes) are the bus key's and URL's; on disk,
		## the conversation's folder is `<key>` or `channels/<key>`
		## (conv_dir).
		key : ConvKey,

		## The topic's id, which is also its name as shown: letters and
		## digits joined by single hyphens (`ChitChat`, `road-trip`;
		## valid_topic_id). On disk it is the transcript's stem,
		## `<conv folder>/sessions/<topic>.md`.
		topic : List(U8),
	}

	## validTopicID: letters and digits joined by single hyphens, none at
	## either end, 1 to 80 bytes.
	is_topic_id : Str -> Bool
	is_topic_id = |text| {
		topic = text.to_utf8()
		n = List.len(topic)
		if n == 0 or n > 80 or List.first(topic) == Ok('-') or List.last(topic) == Ok('-') {
			Bool.False
		} else {
			(ok, _) = List.fold(
				topic,
				(Bool.True, Bool.False),
				|(good, prev_hyphen), c|
					if !good {
						(Bool.False, prev_hyphen)
					} else if c == '-' {
						(!prev_hyphen, Bool.True)
					} else {
						(is_alnum(c), Bool.False)
					},
			)
			ok
		}
	}

	## validChannelName: a letter, then letters, digits and hyphens, 1 to 40
	## bytes.
	is_channel_name : Str -> Bool
	is_channel_name = |text| match text.to_utf8() {
		[first, .. as more] =>
			text.count_utf8_bytes() <= 40 and is_alpha(first) and List.all(more, |c| is_alnum(c) or c == '-')
		[] => Bool.False
	}

	## **A CHANNEL'S NAME, VALIDATED**: opaque (`::`), so only
	## `channel_name_from_str` makes one, and a channel's path is built from
	## nothing else.
	ChannelName :: Str

	## The name, when is_channel_name passes it.
	channel_name_from_str : Str -> Try(ChannelName, [Invalid])
	channel_name_from_str = |name| if is_channel_name(name) Ok(ChannelName.(name)) else Err(Invalid)

	## The name's text.
	channel_name_to_str : ChannelName -> Str
	channel_name_to_str = |ChannelName.(s)| s

	## The name's bytes, where they go back out.
	channel_name_bytes : ChannelName -> List(U8)
	channel_name_bytes = |ChannelName.(s)| s.to_utf8()

	## validMsgRefID: a topic slug (letters, digits, hyphens), `_`, and a
	## message's decimal number, cut at the last `_`.
	valid_msg_ref_id : List(U8) -> Bool
	valid_msg_ref_id = |id|
		match cut_last(id, '_') {
			Err(NoSeparator) => Bool.False
			Ok((left, right)) =>
				left != [] and right != [] and List.all(left, |c| is_alnum(c) or c == '-') and List.all(right, |c| c >= '0' and c <= '9')
		}

	## firstOf: "ChitChat" when there, else the first (the list is sorted),
	## else none.
	first_of : List(Str) -> Str
	first_of = |topics|
		if List.contains(topics, "ChitChat") {
			"ChitChat"
		} else {
			List.first(topics) ?? ""
		}

	## listUserChannels's decision: the names of the channels `uid` is in,
	## sorted by bytes, from every roster (`rosters`'s).
	member_channels : List(Roster), List(U8) -> List(Str)
	member_channels = |all, uid| sort_by_bytes(List.map(List.keep_if(all, |r| List.contains(r.members, uid)), |r| r.name))

	## Texts sorted by their bytes, as the Zig's sorts compare.
	sort_by_bytes : List(Str) -> List(Str)
	sort_by_bytes = |texts|
		List.sort_with(
			texts,
			|a, b|
				if Bytes.less(a.to_utf8(), b.to_utf8()) {
					Before
				} else if Bytes.less(b.to_utf8(), a.to_utf8()) {
					After
				} else {
					Same
				},
		)

	## A folder's entry, as Files.list! answers it: its name is text.
	Entry : { kind : [Dir, File, Other], name : Str }

	## A channel and its members, as its member file lists them.
	Roster : { name : Str, members : List(List(U8)) }

	## A DM's folder under the chat root (dmConvDir): its pair key.
	dm_conv_dir : List(U8) -> List(U8)
	dm_conv_dir = |key| join([key])

	## A channel's (channelConvDir): channels/<name>.
	channel_conv_dir : List(U8) -> List(U8)
	channel_conv_dir = |name| join([Str.to_utf8("channels"), name])

	## A DM's or a channel's folder under the chat root: dm_conv_dir or
	## channel_conv_dir of its key.
	conv_dir : ConvKey -> List(U8)
	conv_dir = |key|
		match key {
			Dm(pair) => dm_conv_dir(pair_key_bytes(pair))
			Channel(name) => channel_conv_dir(channel_name_bytes(name))
		}

	## Where a conversation's topics are (listTopics's folder):
	## {conv_dir}/sessions.
	sessions_dir : List(U8) -> List(U8)
	sessions_dir = |dir| join([dir, Str.to_utf8("sessions")])

	## **A CONVERSATION'S TOPICS** (listTopics): of its sessions folder's
	## entries, every one that is not a folder (a file, or a link: only a
	## folder is passed over) whose name ends in `.md`, that cut off, sorted
	## by bytes. A folder named `x.md` is no topic; a file named `.md` is
	## topic "".
	topics : List(Entry) -> List(Str)
	topics = |entries| sort_by_bytes(List.keep_oks(entries, |e| if e.kind == Dir Err(NoSuffix) else str_suffix(e.name, ".md")))

	## `name` without `suffix`, when it ends in it.
	str_suffix : Str, Str -> Try(Str, [NoSuffix])
	str_suffix = |name, suffix| if name.ends_with(suffix) Ok(name.drop_suffix(suffix)) else Err(NoSuffix)

	## **A FILE UNDER THE CHAT ROOT, NAMED HERE**: opaque (`::`), so only
	## this module makes one, and Files.roc, the one module that reaches the
	## disk, takes nothing else.
	ChatPath :: List(U8)

	## The path's bytes, as the host takes them.
	bytes : ChatPath -> List(U8)
	bytes = |ChatPath.(b)| b

	## A topic's reaction sidecar (reactionsPath):
	## {conv_dir}/sessions/<topic>.reactions.jsonl.
	reactions_path : TopicAt -> ChatPath
	reactions_path = |at| reactions_path_bytes({ dir: conv_dir(at.key), topic: at.topic })

	## reactions_path's core, from the conversation's folder as bytes: the
	## twins feed it any (production: reactions_path).
	reactions_path_bytes : { dir : List(U8), topic : List(U8) } -> ChatPath
	reactions_path_bytes = |{ dir, topic }| ChatPath.(join([dir, Str.to_utf8("sessions"), List.concat(topic, Str.to_utf8(".reactions.jsonl"))]))

	## Channel `name`'s member file (channelMembers's): channels/<name>.channel.
	channel_path : ChannelName -> ChatPath
	channel_path = |ChannelName.(name)| ChatPath.(join([Str.to_utf8("channels"), "${name}.channel".to_utf8()]))

	## The folder of every channel's member file (channelRosters's listing):
	## channels.
	channels_folder : ChatPath
	channels_folder = ChatPath.(Str.to_utf8("channels"))

	## A conversation's topics folder (listTopics's listing): sessions_dir
	## of its folder.
	topics_folder : ConvKey -> ChatPath
	topics_folder = |key| ChatPath.(sessions_dir(conv_dir(key)))

	## The member's DM last in (lastUserConv's file): users/<uid>/last-conv.
	last_conv_path : List(U8) -> ChatPath
	last_conv_path = |uid| ChatPath.(join([Str.to_utf8("users"), uid, Str.to_utf8("last-conv")]))

	## The topic the member last viewed in DM `key` (lastViewedTopic's
	## file): users/<uid>/last-sessions/<conv>.
	last_session_path : Uid, ConvKey -> ChatPath
	last_session_path = |uid, key| last_session_path_bytes({ uid: Uid.to_bytes(uid), conv: conv_key_bytes(key) })

	## last_session_path's core, from the uid and key as bytes: the twins
	## feed it any (production: last_session_path).
	last_session_path_bytes : { uid : List(U8), conv : List(U8) } -> ChatPath
	last_session_path_bytes = |{ uid, conv }| ChatPath.(join([Str.to_utf8("users"), uid, Str.to_utf8("last-sessions"), conv]))

	## The member's pins in `key` (pinnedTopics's file):
	## users/<uid>/pinned-sessions/<conv>.
	pinned_path : Uid, ConvKey -> ChatPath
	pinned_path = |uid, key| pinned_path_bytes({ uid: Uid.to_bytes(uid), conv: conv_key_bytes(key) })

	## pinned_path's core, from the uid and key as bytes: the twins feed it
	## any (production: pinned_path).
	pinned_path_bytes : { uid : List(U8), conv : List(U8) } -> ChatPath
	pinned_path_bytes = |{ uid, conv }| ChatPath.(join([Str.to_utf8("users"), uid, Str.to_utf8("pinned-sessions"), conv]))

	## The member's feed file: users/<uid>/images.md or code.md, where
	## images_store and code_store keep them.
	feed_path : List(U8), [Images, Code] -> ChatPath
	feed_path = |uid, which| {
		name = match which {
			Images => "images.md"
			Code => "code.md"
		}
		ChatPath.(join([Str.to_utf8("users"), uid, Str.to_utf8(name)]))
	}

	## **A CHANNEL'S MEMBERS** (channelMembers): one uid a line, each line
	## trimmed of spaces, tabs and CRs, blank lines and `#` lines skipped.
	## **A LINE IS A CANONICAL UID, ONCE, OR THE CHANNEL IS MALFORMED**
	## (metal-vmm QUEUE 156(d)): each member is a path the fan-out writes
	## under (`../../x` was one), a comment after a uid (`3 # Claude`)
	## dropped that member, and a duplicate notified twice. Never a guess at
	## what a line meant: whoever wrote the file fixes it.
	channel_members : List(U8) -> Try(List(List(U8)), [Malformed])
	channel_members = |file|
		List.fold(
			Bytes.split_byte(file, '\n'),
			Ok([]),
			|acc, raw|
				match acc {
					Err(Malformed) => acc
					Ok(out) => {
						line = trim_line(raw)
						if line == [] or List.first(line) == Ok('#') {
							acc
						} else if !canonical_uid(line) or List.contains(out, line) {
							Err(Malformed)
						} else {
							Ok(List.append(out, line))
						}
					}
				},
		)

	## channelMembers's trim: spaces, tabs and CRs (a line split on newlines
	## has none of those).
	trim_line : List(U8) -> List(U8)
	trim_line = |s| {
		ws = |c| c == ' ' or c == '\t' or c == '\r'
		front = List.drop_first(s, ZigText.count_while(s, ws, 0))
		List.drop_last(front, ZigText.count_back_while(front, ws, 0))
	}

	## channelRosters's choice from channels/'s entries: the name of each one
	## whose name ends in `.channel`, of any kind (one that is a folder will
	## not read, and fails the listing, as the Zig's did), that cut off, in
	## the listing's order. A file named `.channel` is channel "".
	channel_names : List(Entry) -> List(Str)
	channel_names = |entries| List.keep_oks(entries, |e| str_suffix(e.name, ".channel"))

	## Of a listing's names that are not UTF-8 (Files.list!'s `not_utf8`),
	## those channel_names would have chosen: each is a channel the listing
	## skipped, and counted as malformed.
	channel_names_not_utf8 : List(List(U8)) -> List(List(U8))
	channel_names_not_utf8 = |names| List.keep_oks(names, |n| cut_suffix(n, Str.to_utf8(".channel")))

	## **ONE CHANNEL'S PART IN EVERY ROSTER** (channelRosters), from its
	## member file as read: its roster (`Listed`); `Malformed`, skipped, and
	## counted by the host (the operator's count), so one bad file is not
	## every member's chat down; `Gone` since the listing, skipped; or
	## `Failed`, and nothing past it (the request has failed).
	roster : Str, Try(List(U8), [Missing, Failed]) -> [Listed(Roster), Malformed, Gone, Failed]
	roster = |name, file|
		match file {
			Ok(stored) =>
				match channel_members(stored) {
					Ok(members) => Listed({ name, members })
					Err(Malformed) => Malformed
				}
			Err(Missing) => Gone
			Err(Failed) => Failed
		}

	## Every roster, from the channels `channel_names` chose and their member
	## files as read, in that order, by `roster`: the rosters, and the
	## malformed channels' names, up to a read that failed.
	rosters : List(Str), List(Try(List(U8), [Missing, Failed])) -> { rosters : List(Roster), malformed : List(Str) }
	rosters = |names, files| rosters_from(names, files, 0, { rosters: [], malformed: [] })

	rosters_from : List(Str), List(Try(List(U8), [Missing, Failed])), U64, { rosters : List(Roster), malformed : List(Str) } -> { rosters : List(Roster), malformed : List(Str) }
	rosters_from = |names, files, i, got|
		match (List.get(names, i), List.get(files, i)) {
			(Ok(name), Ok(file)) =>
				match roster(name, file) {
					Listed(r) => rosters_from(names, files, i + 1, { rosters: List.append(got.rosters, r), malformed: got.malformed })
					Malformed => rosters_from(names, files, i + 1, { rosters: got.rosters, malformed: List.append(got.malformed, name) })
					Gone => rosters_from(names, files, i + 1, got)
					Failed => got
				}
			_ => got
		}

	## `name` without `suffix`, when it ends in it.
	cut_suffix : List(U8), List(U8) -> Try(List(U8), [NoSuffix])
	cut_suffix = |name, suffix| {
		n = List.len(name)
		k = List.len(suffix)
		if n >= k and List.drop_first(name, n - k) == suffix Ok(List.take_first(name, n - k)) else Err(NoSuffix)
	}

	## `std.fs.path.join` on POSIX: the non-empty parts joined by one `/`,
	## where a part ending in `/` meeting one starting with it keeps one.
	join : List(List(U8)) -> List(U8)
	join = |parts|
		List.fold(
			List.drop_if(parts, |p| p == []),
			[],
			|out, p|
				if out == [] {
					p
				} else {
					end = List.last(out) == Ok('/')
					start = List.first(p) == Ok('/')
					if end and start {
						List.concat(out, List.drop_first(p, 1))
					} else if end or start {
						List.concat(out, p)
					} else {
						List.concat(List.append(out, '/'), p)
					}
				},
		)

	## A topic's transcript: {conv_dir}/sessions/<topic>.md.
	transcript_path : TopicAt -> ChatPath
	transcript_path = |at| ChatPath.(transcript_path_bytes({ dir: conv_dir(at.key), topic: at.topic }))

	## The member's links page (the links route's file): users/<uid>/links.md.
	links_path : List(U8) -> ChatPath
	links_path = |uid| ChatPath.(join([Str.to_utf8("users"), uid, Str.to_utf8("links.md")]))

	## transcript_path's core, from the conversation's folder as bytes: the
	## twins feed it any (production: transcript_path).
	transcript_path_bytes : { dir : List(U8), topic : List(U8) } -> List(U8)
	transcript_path_bytes = |{ dir, topic }| join([dir, Str.to_utf8("sessions"), List.concat(topic, Str.to_utf8(".md"))])

	is_alpha : U8 -> Bool
	is_alpha = |c| (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')

	is_alnum : U8 -> Bool
	is_alnum = |c| is_alpha(c) or (c >= '0' and c <= '9')

	## The bytes before and after the first `sep`.
	cut_first : List(U8), U8 -> Try((List(U8), List(U8)), [NoSeparator])
	cut_first = |s, sep| {
		i = index_of(s, sep, 0)?
		Ok((List.take_first(s, i), List.drop_first(s, i + 1)))
	}

	## The bytes before and after the last `sep`.
	cut_last : List(U8), U8 -> Try((List(U8), List(U8)), [NoSeparator])
	cut_last = |s, sep| {
		(last, _) = List.fold(s, (Err(NoSeparator), 0), |(found, i), c| (if c == sep Ok(i) else found, i + 1))
		i = last?
		Ok((List.take_first(s, i), List.drop_first(s, i + 1)))
	}

	index_of : List(U8), U8, U64 -> Try(U64, [NoSeparator])
	index_of = |s, sep, i| match List.get(s, i) {
		Ok(c) => if c == sep Ok(i) else index_of(s, sep, i + 1)
		Err(_) => Err(NoSeparator)
	}
}

# The builders' exact bytes, for a DM (`3_7`) and a channel (`general`).
expect match (Paths.pair_key_from_str("3_7"), Paths.channel_name_from_str("general")) {
	(Ok(pair), Ok(name)) => {
		dm = Dm(pair)
		channel = Channel(name)
		(Paths.bytes(Paths.topics_folder(dm)) == Str.to_utf8("3_7/sessions"))
			and (Paths.bytes(Paths.topics_folder(channel)) == Str.to_utf8("channels/general/sessions"))
				and (Paths.bytes(Paths.reactions_path({ key: dm, topic: Str.to_utf8("ChitChat") })) == Str.to_utf8("3_7/sessions/ChitChat.reactions.jsonl"))
					and (Paths.bytes(Paths.reactions_path({ key: channel, topic: Str.to_utf8("road-trip") })) == Str.to_utf8("channels/general/sessions/road-trip.reactions.jsonl"))
						and (Paths.bytes(Paths.transcript_path({ key: dm, topic: Str.to_utf8("ChitChat") })) == Str.to_utf8("3_7/sessions/ChitChat.md"))
							and (Paths.bytes(Paths.transcript_path({ key: channel, topic: Str.to_utf8("road-trip") })) == Str.to_utf8("channels/general/sessions/road-trip.md"))
								and (Paths.conv_dir(dm) == Str.to_utf8("3_7"))
									and (Paths.conv_dir(channel) == Str.to_utf8("channels/general"))
	}
	_ => Bool.False
}
expect Paths.bytes(Paths.channels_folder) == Str.to_utf8("channels")
expect match Paths.channel_name_from_str("general") {
	Ok(name) => Paths.bytes(Paths.channel_path(name)) == Str.to_utf8("channels/general.channel")
	Err(Invalid) => Bool.False
}
expect Paths.bytes(Paths.last_conv_path(Str.to_utf8("3"))) == Str.to_utf8("users/3/last-conv")
expect match Paths.pair_key(Uid.from_bytes(Str.to_utf8("3")), Uid.from_bytes(Str.to_utf8("7"))) {
	Ok(pair) => Paths.bytes(Paths.last_session_path(Uid.from_bytes(Str.to_utf8("3")), Dm(pair))) == Str.to_utf8("users/3/last-sessions/3_7")
	Err(Invalid) => Bool.False
}
expect match Paths.pair_key(Uid.from_bytes(Str.to_utf8("7")), Uid.from_bytes(Str.to_utf8("3"))) {
	Ok(pair) => Paths.bytes(Paths.pinned_path(Uid.from_bytes(Str.to_utf8("3")), Dm(pair))) == Str.to_utf8("users/3/pinned-sessions/3_7")
	Err(Invalid) => Bool.False
}
expect match Paths.channel_name_from_str("general") {
	Ok(name) => Paths.bytes(Paths.pinned_path(Uid.from_bytes(Str.to_utf8("3")), Channel(name))) == Str.to_utf8("users/3/pinned-sessions/general")
	Err(Invalid) => Bool.False
}
expect Paths.bytes(Paths.feed_path(Str.to_utf8("3"), Images)) == Str.to_utf8("users/3/images.md")
expect Paths.bytes(Paths.feed_path(Str.to_utf8("3"), Code)) == Str.to_utf8("users/3/code.md")

# pair_key: the smaller uid first, by number, not by bytes; a half that is
# no canonical number makes no key.
expect Paths.pair_key(Uid.from_bytes(Str.to_utf8("7")), Uid.from_bytes(Str.to_utf8("3"))).map_ok(Paths.pair_key_to_str) == Ok("3_7")
expect Paths.pair_key(Uid.from_bytes(Str.to_utf8("3")), Uid.from_bytes(Str.to_utf8("7"))).map_ok(Paths.pair_key_to_str) == Ok("3_7")
expect Paths.pair_key(Uid.from_bytes(Str.to_utf8("10")), Uid.from_bytes(Str.to_utf8("9"))).map_ok(Paths.pair_key_to_str) == Ok("9_10")
expect Paths.pair_key(Uid.from_bytes(Str.to_utf8("5")), Uid.from_bytes(Str.to_utf8("5"))).map_ok(Paths.pair_key_to_str) == Ok("5_5")
expect Paths.pair_key(Uid.from_bytes(Str.to_utf8("a")), Uid.from_bytes(Str.to_utf8("5"))).is_err()
expect Paths.pair_key(Uid.from_bytes(Str.to_utf8("05")), Uid.from_bytes(Str.to_utf8("5"))).is_err()
expect Paths.pair_key(Uid.from_bytes(Str.to_utf8("9223372036854775808")), Uid.from_bytes(Str.to_utf8("5"))).map_ok(Paths.pair_key_to_str) == Ok("9223372036854775808_5")

# pair_key_from_str: only the canonical `<small>_<large>` of two uids, or a
# uid twice (the DM with yourself).
expect Paths.pair_key_from_str("3_7").map_ok(Paths.pair_key_to_str) == Ok("3_7")
expect Paths.pair_key_from_str("3_3").map_ok(Paths.pair_key_to_str) == Ok("3_3")
expect Paths.pair_key_from_str("7_3").is_err()
expect Paths.pair_key_from_str("3_").is_err()
expect Paths.pair_key_from_str("_7").is_err()
expect Paths.pair_key_from_str("a_b").is_err()
expect Paths.pair_key_from_str("..").is_err()
expect Paths.pair_key_from_str("3_7_9").is_err()
expect Paths.pair_key_from_str("03_7").is_err()
expect Paths.pair_key_from_str("3_../7").is_err()
expect Paths.pair_key_from_str("").is_err()

# is_participant: only the pair's two members.
expect match Paths.pair_key_from_str("3_7") {
	Ok(pair) =>
		Paths.is_participant(pair, Uid.from_bytes(Str.to_utf8("3")))
			and Paths.is_participant(pair, Uid.from_bytes(Str.to_utf8("7")))
				and !Paths.is_participant(pair, Uid.from_bytes(Str.to_utf8("9")))
					and !Paths.is_participant(pair, Uid.from_bytes(Str.to_utf8("37")))
						and !Paths.is_participant(pair, Uid.from_bytes([]))
	Err(Invalid) => Bool.False
}

# is_topic_id: letters and digits joined by single hyphens, 1 to 80 bytes.
expect Paths.is_topic_id("ChitChat")
expect Paths.is_topic_id("road-trip-2")
expect Paths.is_topic_id("9")
expect Paths.is_topic_id(Str.repeat("a", 80))
expect !Paths.is_topic_id(Str.repeat("a", 81))
expect !Paths.is_topic_id("")
expect !Paths.is_topic_id("..")
expect !Paths.is_topic_id("a/b")
expect !Paths.is_topic_id("../x")
expect !Paths.is_topic_id("-a")
expect !Paths.is_topic_id("a-")
expect !Paths.is_topic_id("a--b")
expect !Paths.is_topic_id("a_b")
expect !Paths.is_topic_id("a b")
expect !Paths.is_topic_id("a.md")
expect !Paths.is_topic_id("caf\u(e9)")

# is_channel_name: a letter, then letters, digits and hyphens, 1 to 40
# bytes.
expect Paths.is_channel_name("general")
# Production's two channels, made by hand (Steve, 2026-10-27): a stricter
# rule must still take them, or they vanish from the chat.
expect Paths.is_channel_name("Cobblestone")
expect Paths.is_channel_name("General")
expect Paths.is_channel_name("a-1-")
expect Paths.is_channel_name(Str.repeat("a", 40))
expect !Paths.is_channel_name(Str.repeat("a", 41))
expect !Paths.is_channel_name("")
expect !Paths.is_channel_name("1abc")
expect !Paths.is_channel_name("-abc")
expect !Paths.is_channel_name("..")
expect !Paths.is_channel_name("a/b")
expect !Paths.is_channel_name("a_b")
expect !Paths.is_channel_name("a.channel")
expect !Paths.is_channel_name("caf\u(e9)")

# channel_name_from_str: a valid name round-trips; nothing else is a
# ChannelName, so no channel path is built from it.
expect Paths.channel_name_from_str("a-1-").map_ok(Paths.channel_name_to_str) == Ok("a-1-")
expect Paths.channel_name_from_str("../x").is_err()
expect Paths.channel_name_from_str("").is_err()

# **A CONVERSATION'S PATHS ARE BUILT FROM A ConvKey ALONE**, which only
# pair_key_from_str (or pair_key) and channel_name_from_str make; the
# `_bytes` cores join what they are handed, so a hostile folder or topic
# makes a path out of the chat root, and only the twins call them (the hunt
# bytes_core_outside_twin). The rest is upstream: Route.conversation
# passes a topic only through is_topic_id, make! checks a new topic's
# id, and a uid is the host's (Host.me!) or a canonical pair's half.
expect Paths.bytes(Paths.reactions_path_bytes({ dir: Str.to_utf8("channels/../.."), topic: Str.to_utf8("../x") })) == Str.to_utf8("channels/../../sessions/../x.reactions.jsonl")
expect Paths.transcript_path_bytes({ dir: [], topic: [] }) == Str.to_utf8("sessions/.md")
expect Paths.bytes(Paths.last_session_path_bytes({ uid: Str.to_utf8("3"), conv: Str.to_utf8("../../x") })) == Str.to_utf8("users/3/last-sessions/../../x")
expect Paths.bytes(Paths.feed_path(Str.to_utf8("/etc"), Code)) == Str.to_utf8("users/etc/code.md")
expect Paths.bytes(Paths.links_path(Str.to_utf8("3"))) == Str.to_utf8("users/3/links.md")
