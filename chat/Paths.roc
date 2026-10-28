## THE CHAT'S NAMES AND PATHS (angry-gopher chat_paths.zig): which keys,
## topic ids, channel names and message ids are well formed, the DM pair's
## canonical key, and paths joined as Zig's `std.fs.path.join` joins them.
## Pure.
import Bytes
import Uid
import ZigText

Paths := [].{

	## **A DM'S KEY**: its two uids, the smaller first. Opaque (`::`), so
	## only `pair_key` (from two uids) and `pair_key_from_str` (from text,
	## validated) make one.
	PairKey :: { small : Uid, large : Uid }.{

		## chatKeyParticipant: `user` is one of the pair's two uids (the key
		## is canonical: only pair_key and pair_key_from_str make one).
		is_participant : PairKey, Uid -> Bool
		is_participant = |PairKey.(pair), user| pair.small == user or pair.large == user

		## partnerName's half: the pair's first uid, unless it is `me` (then
		## the second, so `1_1`'s partner is `1`).
		partner : PairKey, Uid -> Uid
		partner = |PairKey.(pair), me| if pair.small == me pair.large else pair.small

		## The key's text: `<small>_<large>`.
		to_str : PairKey -> Str
		to_str = |PairKey.(pair)| "${pair.small.to_str()}_${pair.large.to_str()}"

		## The key's bytes, where they go back out.
		bytes : PairKey -> List(U8)
		bytes = |pair| pair.to_str().to_utf8()
	}

	## chatPairKey: the smaller numeric id first, joined by `_` (a number
	## past i64's counts as 0, as Zig's `atoiOr0`). A Uid is canonical by
	## its type (Uid.from_str), so every two make a key.
	pair_key : Uid, Uid -> PairKey
	pair_key = |a, b|
		if atoi_or0(a.to_str().to_utf8()) <= atoi_or0(b.to_str().to_utf8()) {
			PairKey.({ small: a, large: b })
		} else {
			PairKey.({ small: b, large: a })
		}

	## The key, when it is exactly the canonical `<small>_<large>` of two
	## valid uids, or `<uid>_<uid>`: the DM with yourself (`1_1`) is one.
	pair_key_from_str : Str -> Try(PairKey, [Invalid])
	pair_key_from_str = |key|
		match key.split_first("_") {
			Ok({ before, after }) =>
				match (Uid.from_str(before), Uid.from_str(after)) {
					(Ok(a), Ok(b)) => {
						made = pair_key(a, b)
						if made.to_str() == key Ok(made) else Err(Invalid)
					}
					_ => Err(Invalid)
				}
			Err(_) => Err(Invalid)
		}

	## **WHICH CONVERSATION**: a DM, by its canonical pair key, two uids
	## joined by `_`, the smaller first (`3_7`; pair_key); or a channel, by
	## its name, a letter then letters, digits and hyphens (`general`;
	## channel_name).
	ConvKey := [Dm(PairKey), Channel(ChannelName)].{

		## The key's bytes, where it goes back out (a URL, a bus key, a JSON
		## field, a host call): the pair key or the channel's name.
		bytes : ConvKey -> List(U8)
		bytes = |key|
			match key {
				Dm(pair) => pair.bytes()
				Channel(name) => name.bytes()
			}

		## The key's text: the pair key or the channel's name.
		to_str : ConvKey -> Str
		to_str = |key|
			match key {
				Dm(pair) => pair.to_str()
				Channel(name) => name.to_str()
			}

		## The conversation's URL base: `/chat/c/` and a DM's pair key, or
		## `/channel/` and a channel's name (the host's Conv.base).
		base : ConvKey -> Str
		base = |key|
			match key {
				Dm(pair) => "/chat/c/${pair.to_str()}"
				Channel(name) => "/channel/${name.to_str()}"
			}

		## The key's family: a DM's or a channel's.
		kind : ConvKey -> [Dm, Channel]
		kind = |key|
			match key {
				Dm(_) => Dm
				Channel(_) => Channel
			}

		is_eq : _
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
		## `general`; ConvKey.bytes) are the bus key's and URL's; on disk,
		## the conversation's folder is `<key>` or `channels/<key>`
		## (conv_dir).
		key : ConvKey,

		## The topic's id, which is also its name as shown: letters and
		## digits joined by single hyphens (`ChitChat`, `road-trip`;
		## valid_topic_id). On disk it is the transcript's stem,
		## `<conv folder>/sessions/<topic>.md`.
		topic : Str,
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
	ChannelName :: Str.{

		## The name's text.
		to_str : ChannelName -> Str
		to_str = |ChannelName.(n)| n

		## The name's bytes, where they go back out.
		bytes : ChannelName -> List(U8)
		bytes = |ChannelName.(n)| n.to_utf8()

		is_eq : _
	}

	## The name, when is_channel_name passes it.
	channel_name_from_str : Str -> Try(ChannelName, [Invalid])
	channel_name_from_str = |name| if is_channel_name(name) Ok(ChannelName.(name)) else Err(Invalid)

	## validMsgRefID: a topic slug (letters, digits, hyphens), `_`, and a
	## message's decimal number, cut at the last `_`.
	is_valid_msg_ref_id : List(U8) -> Bool
	is_valid_msg_ref_id = |id|
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
	member_channels : List(Roster), Uid -> List(Str)
	member_channels = |all, uid| sort_by_bytes(List.map(List.keep_if(all, |r| List.contains(r.members, uid)), |r| r.name))

	## Texts sorted by their bytes, as the Zig's sorts compare.
	sort_by_bytes : List(Str) -> List(Str)
	sort_by_bytes = |texts| List.sort_with(texts, |a, b| Bytes.compare(a.to_utf8(), b.to_utf8()))

	## A folder's entry, as Files.list! answers it: its name is text.
	Entry : { kind : [Dir, File, Other], name : Str }

	## A channel and its members, as its member file lists them.
	Roster : { name : Str, members : List(Uid) }

	## **A CONVERSATION'S TOPICS** (listTopics): of its sessions folder's
	## entries, every one that is not a folder (a file, or a link: only a
	## folder is passed over) whose name ends in `.md`, that cut off, sorted
	## by bytes. A folder named `x.md` is no topic; a file named `.md` is
	## topic "".
	topics : List(Entry) -> List(Str)
	topics = |entries| sort_by_bytes(List.keep_oks(entries, |e| if e.kind == Dir Err(NoSuffix) else str_suffix(e.name, ".md")))

	## **A FILE UNDER THE CHAT ROOT, NAMED HERE**: opaque (`::`), so only
	## this module makes one, and Files.roc, the one module that reaches the
	## disk, takes nothing else. **ITS PARTS ARE A ConvKey, A Uid, A TOPIC
	## AND LITERALS**: none empty, none with a `/`, so joined by one `/` they
	## are std.fs.path.join's path.
	ChatPath :: Str.{

		## The path's bytes, as the host takes them.
		bytes : ChatPath -> List(U8)
		bytes = |ChatPath.(p)| p.to_utf8()
	}

	## A topic's reaction sidecar (reactionsPath):
	## {conv_dir}/sessions/<topic>.reactions.jsonl.
	reactions_path : TopicAt -> ChatPath
	reactions_path = |at| ChatPath.("${conv_dir(at.key)}/sessions/${at.topic}.reactions.jsonl")

	## Channel `name`'s member file (channelMembers's): channels/<name>.channel.
	channel_path : ChannelName -> ChatPath
	channel_path = |ChannelName.(name)| ChatPath.("channels/${name}.channel")

	## The folder of every channel's member file (channelRosters's listing):
	## channels.
	channels_folder : ChatPath
	channels_folder = ChatPath.("channels")

	## A conversation's topics folder (listTopics's listing):
	## {conv_dir}/sessions.
	topics_folder : ConvKey -> ChatPath
	topics_folder = |key| ChatPath.("${conv_dir(key)}/sessions")

	## The member's DM last in (lastUserConv's file): users/<uid>/last-conv.
	last_conv_path : Uid -> ChatPath
	last_conv_path = |uid| ChatPath.("users/${uid.to_str()}/last-conv")

	## The topic the member last viewed in DM `key` (lastViewedTopic's
	## file): users/<uid>/last-sessions/<conv>.
	last_session_path : Uid, ConvKey -> ChatPath
	last_session_path = |uid, key| ChatPath.("users/${uid.to_str()}/last-sessions/${key.to_str()}")

	## The member's pins in `key` (pinnedTopics's file):
	## users/<uid>/pinned-sessions/<conv>.
	pinned_path : Uid, ConvKey -> ChatPath
	pinned_path = |uid, key| ChatPath.("users/${uid.to_str()}/pinned-sessions/${key.to_str()}")

	## The member's feed file: users/<uid>/images.md or code.md, where
	## images_store and code_store keep them.
	feed_path : Uid, [Images, Code] -> ChatPath
	feed_path = |uid, which| {
		name = match which {
			Images => "images.md"
			Code => "code.md"
		}
		ChatPath.("users/${uid.to_str()}/${name}")
	}

	## **A CHANNEL'S MEMBERS** (channelMembers): one uid a line, each line
	## trimmed of spaces, tabs and CRs, blank lines and `#` lines skipped.
	## **A LINE IS A CANONICAL UID, ONCE, OR THE CHANNEL IS MALFORMED**
	## (metal-vmm QUEUE 156(d)): each member is a path the fan-out writes
	## under (`../../x` was one), a comment after a uid (`3 # Claude`)
	## dropped that member, and a duplicate notified twice. Never a guess at
	## what a line meant: whoever wrote the file fixes it.
	channel_members : Str -> Try(List(Uid), [Malformed])
	channel_members = |file|
		List.fold(
			Bytes.split_byte(file.to_utf8(), '\n'),
			Ok([]),
			|acc, raw|
				match acc {
					Err(Malformed) => acc
					Ok(out) => {
						line = trim_line(raw)
						if line == [] or List.first(line) == Ok('#') {
							acc
						} else {
							match Uid.from_utf8(line) {
								Ok(uid) if !List.contains(out, uid) => Ok(List.append(out, uid))
								_ => Err(Malformed)
							}
						}
					}
				},
		)

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
	roster : Str, Try(Str, [Missing, Failed]) -> [Listed(Roster), Malformed, Gone, Failed]
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
	rosters : List(Str), List(Try(Str, [Missing, Failed])) -> { rosters : List(Roster), malformed : List(Str) }
	rosters = |names, files| rosters_from(names, files, 0, { rosters: [], malformed: [] })

	## A topic's transcript: {conv_dir}/sessions/<topic>.md.
	transcript_path : TopicAt -> ChatPath
	transcript_path = |at| ChatPath.("${conv_dir(at.key)}/sessions/${at.topic}.md")

	## The member's reading list, the doc a save appends to (docs_store's
	## `reading-list`): users/<uid>/docs/reading-list.md.
	reading_list_path : Uid -> ChatPath
	reading_list_path = |uid| ChatPath.("users/${uid.to_str()}/docs/reading-list.md")

	## The member's docs folder (docs_store `userDocsDir`): users/<uid>/docs.
	docs_folder : Uid -> ChatPath
	docs_folder = |uid| ChatPath.("users/${uid.to_str()}/docs")

	## **THE MEMBER'S DOCS** (docs_store `listUserDocs`): of their docs
	## folder's entries, every one that is not a folder whose name is a
	## slug (is_doc_slug) and `.md`, sorted by slug, beside its file.
	docs : Uid, List(Entry) -> List({ slug : Str, path : ChatPath })
	docs = |uid, entries|
		sort_by_bytes(List.keep_oks(entries, |e| if e.kind == Dir Err(NoSuffix) else str_suffix(e.name, ".md")))
			|> List.keep_if(is_doc_slug)
			|> List.map(|slug| { slug, path: ChatPath.("users/${uid.to_str()}/docs/${slug}.md") })

	## The member's doc `slug` (docs_store `docPath`), or `NotASlug` for a
	## slug no slugifyTitle made (validDocSlug, its path-traversal check).
	doc_path : Uid, Str -> Try(ChatPath, [NotASlug])
	doc_path = |uid, slug| if is_doc_slug(slug) Ok(ChatPath.("users/${uid.to_str()}/docs/${slug}.md")) else Err(NotASlug)

	## A topic's message count sidecar (countPath, chat_count.zig):
	## {conv_dir}/sessions/<topic>.count.
	count_path : TopicAt -> ChatPath
	count_path = |at| ChatPath.("${conv_dir(at.key)}/sessions/${at.topic}.count")

	## The member's links page (the links route's file): users/<uid>/links.md.
	links_path : Uid -> ChatPath
	links_path = |uid| ChatPath.("users/${uid.to_str()}/links.md")

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

## A DM's or a channel's folder under the chat root: a DM's pair key
## (dmConvDir), a channel's channels/<name> (channelConvDir).
conv_dir : ConvKey -> Str
conv_dir = |key|
	match key {
		Dm(pair) => pair.to_str()
		Channel(ChannelName.(name)) => "channels/${name}"
	}

## `name` without `suffix`, when it ends in it.
str_suffix : Str, Str -> Try(Str, [NoSuffix])
str_suffix = |name, suffix| if name.ends_with(suffix) Ok(name.drop_suffix(suffix)) else Err(NoSuffix)

## validDocSlug: 1 to 80 lowercase letters and digits, joined by single
## hyphens, none first or last; anything else no slugifyTitle made.
is_doc_slug : Str -> Bool
is_doc_slug = |slug| {
	b = slug.to_utf8()
	n = List.len(b)
	in_set = List.all(b, |c| c == '-' or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9'))
	doubled = List.fold(b, { found: Bool.False, prev: 0 }, |s, c| { found: s.found or (c == '-' and s.prev == '-'), prev: c }).found
	n > 0 and n <= 80 and in_set and !doubled and List.first(b) != Ok('-') and List.last(b) != Ok('-')
}

## channelMembers's trim: spaces, tabs and CRs (a line split on newlines
## has none of those).
trim_line : List(U8) -> List(U8)
trim_line = |s| {
	ws = |c| c == ' ' or c == '\t' or c == '\r'
	front = List.drop_first(s, ZigText.count_while(s, ws, 0))
	List.drop_last(front, ZigText.count_back_while(front, ws, 0))
}

rosters_from : List(Str), List(Try(Str, [Missing, Failed])), U64, { rosters : List(Roster), malformed : List(Str) } -> { rosters : List(Roster), malformed : List(Str) }
rosters_from = |names, files, i, got|
	match (List.get(names, i), List.get(files, i)) {
		(Ok(name), Ok(file)) =>
			match Paths.roster(name, file) {
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

is_alpha : U8 -> Bool
is_alpha = |c| (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')

is_alnum : U8 -> Bool
is_alnum = |c| is_alpha(c) or (c >= '0' and c <= '9')

# The builders' exact bytes, for a DM (`3_7`) and a channel (`general`).
expect match (Paths.pair_key_from_str("3_7"), Paths.channel_name_from_str("general")) {
	(Ok(pair), Ok(name)) => {
		dm = Dm(pair)
		channel = Channel(name)
		(Paths.topics_folder(dm).bytes() == Str.to_utf8("3_7/sessions"))
			and (Paths.topics_folder(channel).bytes() == Str.to_utf8("channels/general/sessions"))
				and (Paths.reactions_path({ key: dm, topic: "ChitChat" }).bytes() == Str.to_utf8("3_7/sessions/ChitChat.reactions.jsonl"))
					and (Paths.reactions_path({ key: channel, topic: "road-trip" }).bytes() == Str.to_utf8("channels/general/sessions/road-trip.reactions.jsonl"))
						and (Paths.transcript_path({ key: dm, topic: "ChitChat" }).bytes() == Str.to_utf8("3_7/sessions/ChitChat.md"))
							and (Paths.transcript_path({ key: channel, topic: "road-trip" }).bytes() == Str.to_utf8("channels/general/sessions/road-trip.md"))
								and (conv_dir(dm) == "3_7")
									and (conv_dir(channel) == "channels/general")
	}
	_ => Bool.False
}
expect Paths.channels_folder.bytes() == Str.to_utf8("channels")
expect match Paths.channel_name_from_str("general") {
	Ok(name) => Paths.channel_path(name).bytes() == Str.to_utf8("channels/general.channel")
	Err(Invalid) => Bool.False
}
expect match (Uid.from_str("3"), Uid.from_str("7")) {
	(Ok(three), Ok(seven)) => {
		pair = Paths.pair_key(seven, three)
		(Paths.last_conv_path(three).bytes() == Str.to_utf8("users/3/last-conv"))
			and (Paths.last_session_path(three, Dm(pair)).bytes() == Str.to_utf8("users/3/last-sessions/3_7"))
				and (Paths.pinned_path(three, Dm(pair)).bytes() == Str.to_utf8("users/3/pinned-sessions/3_7"))
					and (Paths.feed_path(three, Images).bytes() == Str.to_utf8("users/3/images.md"))
						and (Paths.feed_path(three, Code).bytes() == Str.to_utf8("users/3/code.md"))
							and (Paths.links_path(three).bytes() == Str.to_utf8("users/3/links.md"))
	}
	_ => Bool.False
}
expect match (Paths.channel_name_from_str("general"), Uid.from_str("3")) {
	(Ok(name), Ok(three)) => Paths.pinned_path(three, Channel(name)).bytes() == Str.to_utf8("users/3/pinned-sessions/general")
	_ => Bool.False
}

# pair_key: the smaller uid first, by number, not by bytes.
expect match (Uid.from_str("7"), Uid.from_str("3")) {
	(Ok(seven), Ok(three)) => Paths.pair_key(seven, three).to_str() == "3_7" and Paths.pair_key(three, seven).to_str() == "3_7" and Paths.pair_key(three, three).to_str() == "3_3"
	_ => Bool.False
}
expect match (Uid.from_str("10"), Uid.from_str("9")) {
	(Ok(ten), Ok(nine)) => Paths.pair_key(ten, nine).to_str() == "9_10"
	_ => Bool.False
}
expect match (Uid.from_str("9223372036854775808"), Uid.from_str("5")) {
	(Ok(big), Ok(five)) => Paths.pair_key(big, five).to_str() == "9223372036854775808_5"
	_ => Bool.False
}

# pair_key_from_str: only the canonical `<small>_<large>` of two uids, or a
# uid twice (the DM with yourself).
expect Paths.pair_key_from_str("3_7").map_ok(|k| k.to_str()) == Ok("3_7")
expect Paths.pair_key_from_str("3_3").map_ok(|k| k.to_str()) == Ok("3_3")
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
	Ok(pair) => {
		is_in = |text| Uid.from_str(text).map_ok(|uid| pair.is_participant(uid)) == Ok(Bool.True)
		is_in("3") and is_in("7") and !is_in("9") and !is_in("37")
	}
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
expect Paths.channel_name_from_str("a-1-").map_ok(|k| k.to_str()) == Ok("a-1-")
expect Paths.channel_name_from_str("../x").is_err()
expect Paths.channel_name_from_str("").is_err()

# **A CONVERSATION'S PATHS ARE BUILT FROM A ConvKey AND A Uid ALONE**,
# which only pair_key_from_str (or pair_key), channel_name_from_str and
# Uid.from_str make, so no path leaves the chat root. The topic is
# upstream's: Route.conversation passes one only through is_topic_id, and
# make_topic! checks a new topic's id.

# ConvKey.base: the host's Conv.base (Conversation.dm_base, channel_base).
expect match (Paths.pair_key_from_str("3_7"), Paths.channel_name_from_str("general")) {
	(Ok(pair), Ok(name)) => (Paths.ConvKey.Dm(pair).base() == "/chat/c/3_7") and (Paths.ConvKey.Channel(name).base() == "/channel/general")
	_ => Bool.False
}

# docs: a folder, a name that is no slug and a file not `.md` are no docs; the rest sorted by slug.
expect match Uid.from_str("3") {
	Ok(three) => {
		e = |kind, name| { kind, name }
		got = Paths.docs(three, [e(File, "zeta.md"), e(Dir, "folder.md"), e(File, "Bad_Slug.md"), e(File, "plain.txt"), e(Other, "a-b.md"), e(File, "-x.md"), e(File, "a--b.md"), e(File, ".md")])
		List.map(got, |d| d.slug) == ["a-b", "zeta"] and List.map(got, |d| d.path.bytes()) == [Str.to_utf8("users/3/docs/a-b.md"), Str.to_utf8("users/3/docs/zeta.md")]
	}
	Err(_) => Bool.False
}
