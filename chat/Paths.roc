## THE CHAT'S NAMES AND PATHS (angry-gopher chat_paths.zig): which keys,
## topic ids, channel names and message ids are well formed, the DM pair's
## canonical key, and paths joined as Zig's `std.fs.path.join` joins them.
## Pure.
import Bytes
import ZigText

Paths := [].{
	## chatKeyParticipant: `key` is a canonical DM pair (two uids, digits
	## without a leading zero, the smaller first) and `user` is one of them.
	participant : List(U8), List(U8) -> Bool
	participant = |key, user|
		match cut_first(key, '_') {
			Err(None) => Bool.False
			Ok((x, y)) =>
				canonical_uid(x) and canonical_uid(y) and pair_key(x, y) == key and (user == x or user == y)
		}

	## chatPairKey: the smaller numeric id first, joined by `_` (a half that
	## is no number counts as 0, as Zig's `atoiOr0`).
	pair_key : List(U8), List(U8) -> List(U8)
	pair_key = |a, b|
		if atoi_or0(a) <= atoi_or0(b) {
			List.concat(List.append(a, '_'), b)
		} else {
			List.concat(List.append(b, '_'), a)
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
		Err(None) => 0
	}

	## validTopicID: letters and digits joined by single hyphens, none at
	## either end, 1 to 80 bytes.
	valid_topic_id : List(U8) -> Bool
	valid_topic_id = |sid| {
		n = List.len(sid)
		if n == 0 or n > 80 or List.first(sid) == Ok('-') or List.last(sid) == Ok('-') {
			Bool.False
		} else {
			(ok, _) = List.fold(sid, (Bool.True, Bool.False), |(good, prev_hyphen), c|
				if !good {
					(Bool.False, prev_hyphen)
				} else if c == '-' {
					(!prev_hyphen, Bool.True)
				} else {
					(is_alnum(c), Bool.False)
				})
			ok
		}
	}

	## validChannelName: a letter, then letters, digits and hyphens, 1 to 40
	## bytes.
	valid_channel_name : List(U8) -> Bool
	valid_channel_name = |name| match name {
		[first, .. as more] =>
			List.len(name) <= 40 and is_alpha(first) and List.all(more, |c| is_alnum(c) or c == '-')
		[] => Bool.False
	}

	## validMsgRefID: a topic slug (letters, digits, hyphens), `_`, and a
	## message's decimal number, cut at the last `_`.
	valid_msg_ref_id : List(U8) -> Bool
	valid_msg_ref_id = |id|
		match cut_last(id, '_') {
			Err(None) => Bool.False
			Ok((left, right)) =>
				left != [] and right != [] and List.all(left, |c| is_alnum(c) or c == '-') and List.all(right, |c| c >= '0' and c <= '9')
		}

	## firstOf: "ChitChat" when there, else the first (the list is sorted),
	## else none.
	first_of : List(List(U8)) -> List(U8)
	first_of = |topics|
		if List.contains(topics, Str.to_utf8("ChitChat")) {
			Str.to_utf8("ChitChat")
		} else {
			List.first(topics) ?? []
		}

	## listUserChannels's decision: the names of the channels `uid` is in,
	## sorted by bytes, from every roster (`rosters`'s).
	member_channels : List(Roster), List(U8) -> List(List(U8))
	member_channels = |all, uid| Bytes.sort(List.map(List.keep_if(all, |r| List.contains(r.members, uid)), |r| r.name))

	## A folder's entry, as Host.list! answers it.
	Entry : { kind : [Dir, File, Other], name : List(U8) }

	## A channel and its members, as its member file lists them.
	Roster : { name : List(U8), members : List(List(U8)) }

	## A DM's folder under the chat root (dmConvDir): its pair key.
	dm_conv_dir : List(U8) -> List(U8)
	dm_conv_dir = |key| join([key])

	## A channel's (channelConvDir): channels/<name>.
	channel_conv_dir : List(U8) -> List(U8)
	channel_conv_dir = |name| join([Str.to_utf8("channels"), name])

	## Where a conversation's topics are (listTopics's folder):
	## {conv_dir}/sessions.
	sessions_dir : List(U8) -> List(U8)
	sessions_dir = |conv_dir| join([conv_dir, Str.to_utf8("sessions")])

	## **A CONVERSATION'S TOPICS** (listTopics): of its sessions folder's
	## entries, every one that is not a folder (a file, or a link: only a
	## folder is passed over) whose name ends in `.md`, that cut off, sorted
	## by bytes. A folder named `x.md` is no topic; a file named `.md` is
	## topic "".
	topics : List(Entry) -> List(List(U8))
	topics = |entries|
		Bytes.sort(List.keep_oks(entries, |e| if e.kind == Dir Err(None) else cut_suffix(e.name, Str.to_utf8(".md"))))

	## A topic's reaction sidecar (reactionsPath):
	## {conv_dir}/sessions/<sid>.reactions.jsonl.
	reactions_path : List(U8), List(U8) -> List(U8)
	reactions_path = |conv_dir, sid| join([conv_dir, Str.to_utf8("sessions"), List.concat(sid, Str.to_utf8(".reactions.jsonl"))])

	## Channel `name`'s member file (channelMembers's): channels/<name>.channel.
	channel_path : List(U8) -> List(U8)
	channel_path = |name| join([Str.to_utf8("channels"), List.concat(name, Str.to_utf8(".channel"))])

	## **A CHANNEL'S MEMBERS** (channelMembers): one uid a line, each line
	## trimmed of spaces, tabs and CRs, blank lines and `#` lines skipped.
	## **A LINE IS A CANONICAL UID, ONCE, OR THE CHANNEL IS MALFORMED**
	## (metal-vmm QUEUE 156(d)): each member is a path the fan-out writes
	## under (`../../x` was one), a comment after a uid (`3 # Claude`)
	## dropped that member, and a duplicate notified twice. Never a guess at
	## what a line meant: whoever wrote the file fixes it.
	channel_members : List(U8) -> Try(List(List(U8)), [Malformed])
	channel_members = |file|
		List.fold(Bytes.split_byte(file, '\n'), Ok([]), |acc, raw|
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
			})

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
	channel_names : List(Entry) -> List(List(U8))
	channel_names = |entries| List.keep_oks(entries, |e| cut_suffix(e.name, Str.to_utf8(".channel")))

	## **ONE CHANNEL'S PART IN EVERY ROSTER** (channelRosters), from its
	## member file as read: its roster (`Listed`); `Malformed`, skipped, and
	## counted by the host (the operator's count), so one bad file is not
	## every member's chat down; `Gone` since the listing, skipped; or
	## `Failed`, and nothing past it (the request has failed).
	roster : List(U8), [Found(List(U8)), Missing, Failed] -> [Listed(Roster), Malformed, Gone, Failed]
	roster = |name, file|
		match file {
			Found(bytes) =>
				match channel_members(bytes) {
					Ok(members) => Listed({ name, members })
					Err(Malformed) => Malformed
				}
			Missing => Gone
			Failed => Failed
		}

	## Every roster, from the channels `channel_names` chose and their member
	## files as read, in that order, by `roster`: the rosters, and the
	## malformed channels' names, up to a read that failed.
	rosters : List(List(U8)), List([Found(List(U8)), Missing, Failed]) -> { rosters : List(Roster), malformed : List(List(U8)) }
	rosters = |names, files| rosters_from(names, files, 0, { rosters: [], malformed: [] })

	rosters_from : List(List(U8)), List([Found(List(U8)), Missing, Failed]), U64, { rosters : List(Roster), malformed : List(List(U8)) } -> { rosters : List(Roster), malformed : List(List(U8)) }
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
	cut_suffix : List(U8), List(U8) -> Try(List(U8), [None])
	cut_suffix = |name, suffix| {
		n = List.len(name)
		k = List.len(suffix)
		if n >= k and List.drop_first(name, n - k) == suffix Ok(List.take_first(name, n - k)) else Err(None)
	}

	## `std.fs.path.join` on POSIX: the non-empty parts joined by one `/`,
	## where a part ending in `/` meeting one starting with it keeps one.
	join : List(List(U8)) -> List(U8)
	join = |parts|
		List.fold(List.drop_if(parts, |p| p == []), [], |out, p|
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
			})

	## A topic's transcript: {conv_dir}/sessions/<sid>.md.
	transcript_path : List(U8), List(U8) -> List(U8)
	transcript_path = |conv_dir, sid| join([conv_dir, Str.to_utf8("sessions"), List.concat(sid, Str.to_utf8(".md"))])

	is_alpha : U8 -> Bool
	is_alpha = |c| (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')

	is_alnum : U8 -> Bool
	is_alnum = |c| is_alpha(c) or (c >= '0' and c <= '9')

	## The bytes before and after the first `sep`.
	cut_first : List(U8), U8 -> Try((List(U8), List(U8)), [None])
	cut_first = |s, sep| match index_of(s, sep, 0) {
		Ok(i) => Ok((List.take_first(s, i), List.drop_first(s, i + 1)))
		Err(None) => Err(None)
	}

	## The bytes before and after the last `sep`.
	cut_last : List(U8), U8 -> Try((List(U8), List(U8)), [None])
	cut_last = |s, sep| {
		(last, _) = List.fold(s, (Err(None), 0), |(found, i), c| (if c == sep Ok(i) else found, i + 1))
		match last {
			Ok(i) => Ok((List.take_first(s, i), List.drop_first(s, i + 1)))
			Err(None) => Err(None)
		}
	}

	index_of : List(U8), U8, U64 -> Try(U64, [None])
	index_of = |s, sep, i| match List.get(s, i) {
		Ok(c) => if c == sep Ok(i) else index_of(s, sep, i + 1)
		Err(_) => Err(None)
	}
}
