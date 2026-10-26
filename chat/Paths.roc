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
		match cut_first(key, 95) {
			Err(None) => Bool.False
			Ok((x, y)) =>
				canonical_uid(x) and canonical_uid(y) and pair_key(x, y) == key and (user == x or user == y)
		}

	## chatPairKey: the smaller numeric id first, joined by `_` (a half that
	## is no number counts as 0, as Zig's `atoiOr0`).
	pair_key : List(U8), List(U8) -> List(U8)
	pair_key = |a, b|
		if atoi_or0(a) <= atoi_or0(b) {
			List.concat(List.append(a, 95), b)
		} else {
			List.concat(List.append(b, 95), a)
		}

	## A uid as allocateUser writes one: digits, the first not zero.
	canonical_uid : List(U8) -> Bool
	canonical_uid = |s| match s {
		[first, ..] => first != 48 and List.all(s, |c| c >= 48 and c <= 57)
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
		if n == 0 or n > 80 or List.first(sid) == Ok(45) or List.last(sid) == Ok(45) {
			Bool.False
		} else {
			(ok, _) = List.fold(sid, (Bool.True, Bool.False), |(good, prev_hyphen), c|
				if !good {
					(Bool.False, prev_hyphen)
				} else if c == 45 {
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
			List.len(name) <= 40 and is_alpha(first) and List.all(more, |c| is_alnum(c) or c == 45)
		[] => Bool.False
	}

	## validMsgRefID: a topic slug (letters, digits, hyphens), `_`, and a
	## message's decimal number, cut at the last `_`.
	valid_msg_ref_id : List(U8) -> Bool
	valid_msg_ref_id = |id|
		match cut_last(id, 95) {
			Err(None) => Bool.False
			Ok((left, right)) =>
				left != [] and right != [] and List.all(left, |c| is_alnum(c) or c == 45) and List.all(right, |c| c >= 48 and c <= 57)
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
	## sorted by bytes, from every roster as Host.channel_rosters! hands them
	## over (`name, count, member...` each, in the listing's order).
	member_channels : List(List(U8)), List(U8) -> List(List(U8))
	member_channels = |rosters, uid| Bytes.sort(members_of(rosters, uid, 0, []))

	members_of : List(List(U8)), List(U8), U64, List(List(U8)) -> List(List(U8))
	members_of = |rosters, uid, i, out|
		match List.get(rosters, i) {
			Err(_) => out
			Ok(name) => {
				n = ZigText.parse_u64(List.get(rosters, i + 1) ?? []) ?? 0
				members = List.sublist(rosters, { start: i + 2, len: n })
				members_of(rosters, uid, i + 2 + n, if List.contains(members, uid) List.append(out, name) else out)
			}
		}

	## `std.fs.path.join` on POSIX: the non-empty parts joined by one `/`,
	## where a part ending in `/` meeting one starting with it keeps one.
	join : List(List(U8)) -> List(U8)
	join = |parts|
		List.fold(List.drop_if(parts, |p| p == []), [], |out, p|
			if out == [] {
				p
			} else {
				end = List.last(out) == Ok(47)
				start = List.first(p) == Ok(47)
				if end and start {
					List.concat(out, List.drop_first(p, 1))
				} else if end or start {
					List.concat(out, p)
				} else {
					List.concat(List.append(out, 47), p)
				}
			})

	## A topic's transcript: {conv_dir}/sessions/<sid>.md.
	transcript_path : List(U8), List(U8) -> List(U8)
	transcript_path = |conv_dir, sid| join([conv_dir, Str.to_utf8("sessions"), List.concat(sid, Str.to_utf8(".md"))])

	is_alpha : U8 -> Bool
	is_alpha = |c| (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

	is_alnum : U8 -> Bool
	is_alnum = |c| is_alpha(c) or (c >= 48 and c <= 57)

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
