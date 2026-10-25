## WHERE A CHAT PATH GOES, BY ZIG'S RULES (angry-gopher chat.zig's dispatch
## as it was: `handle`, `handleChannel`, `convRoute`, `topicRoute`). Pure:
## the decisions that need the disk or the viewer (whether they are in the
## DM, whether the account or the topic exists) stay in the Zig that serves
## the route, so this says only what the path says.
##
## A path is bytes (Chat.roc): every comparison is on bytes.
Route := [].{
	## The route for `sub`, the path under /chat.
	under_chat : List(U8) -> R
	under_chat = |sub|
		if sub == [] or sub == slash {
			family(f_default)
		} else {
			match family_under(sub) {
				Ok(r) => r
				Err(None) =>
					if starts_with(sub, Str.to_utf8("/search")) {
						with_rest(f_search, drop(sub, 7))
					} else if sub == Str.to_utf8("/default") {
						family(f_default)
					} else if sub == Str.to_utf8("/conversations") {
						family(f_conversations)
					} else if starts_with(sub, Str.to_utf8("/msg/")) {
						with_rest(f_msg, drop(sub, 5))
					} else if starts_with(sub, Str.to_utf8("/c/")) {
						conversation(f_dm, segments(drop(sub, 3)))
					} else if sub == Str.to_utf8("/notifications") {
						family(f_notifications)
					} else if sub == Str.to_utf8("/sidebar/stream") {
						family(f_sidebar_stream)
					} else {
						family(f_not_found)
					}
			}
		}

	## The route for `sub`, the path under /channel.
	under_channel : List(U8) -> R
	under_channel = |sub| conversation(f_channel, segments(sub))

	## A static script: `/<name>.js` under /chat, `rest` the name.
	asset : List(U8) -> Try(R, [None])
	asset = |sub|
		if List.len(sub) > 1 and ends_with(sub, Str.to_utf8(".js")) {
			Ok(with_rest(f_asset, drop(sub, 1)))
		} else {
			Err(None)
		}

	## A live stream, which presence does not count: a topic's, the two
	## cross-page ones, and the feeds'. From the route, not the path's
	## spelling: `.../stream/` is a topic's stream, and a topic named
	## `stream` is a page.
	is_stream : R -> Bool
	is_stream = |r|
		r.tail == 2
		or r.family == f_notifications
		or r.family == f_sidebar_stream
		or ((r.family == f_recent or r.family == f_images or r.family == f_code) and r.rest == Str.to_utf8("/stream"))

	## A route, as Chat.roc's `Route` (records are structural: the same
	## type).
	R : { family : U8, key : List(U8), rest : List(U8), sid : List(U8), part : U8, tail : U8 }

	## A route of `family` with nothing else.
	family : U8 -> R
	family = |f| { family: f, key: [], rest: [], sid: [], part: 0, tail: 0 }

	## Chat.roc's numbers, which roc-webbox src/chat_route.zig says too.
	f_not_found = 0
	f_asset = 1
	f_default = 2
	f_docs = 3
	f_recent = 4
	f_images = 5
	f_code = 6
	f_links = 7
	f_search = 8
	f_conversations = 9
	f_msg = 10
	f_dm = 11
	f_channel = 12
	f_notifications = 13
	f_sidebar_stream = 14

	slash = [47]

	## The five families under a prefix of their own, at a segment's
	## boundary (`/docsX` is none of them).
	family_under : List(U8) -> Try(R, [None])
	family_under = |sub| {
		named = [("/docs", f_docs), ("/recent", f_recent), ("/images", f_images), ("/code", f_code), ("/links", f_links)]
		List.fold(named, Err(None), |found, (prefix, f)|
			match found {
				Ok(r) => Ok(r)
				Err(None) => {
					p = Str.to_utf8(prefix)
					if starts_with(sub, p) {
						rest = drop(sub, List.len(p))
						if rest == [] or starts_with(rest, slash) {
							Ok(with_rest(f, rest))
						} else {
							Err(None)
						}
					} else {
						Err(None)
					}
				}
			})
	}

	## A DM's or a channel's route from its path's segments.
	conversation : U8, List(List(U8)) -> R
	conversation = |f, segs| match segs {
		[] => family(f_not_found)
		[key, .. as more] =>
			if f == f_channel and !valid_channel_name(key) {
				family(f_not_found)
			} else {
				base = { ..family(f), key }
				match more {
					[] => base
					[first, .. as after] =>
						if first == Str.to_utf8("new") {
							{ ..base, part: 1 }
						} else if !valid_topic_id(first) {
							{ ..base, part: 2 }
						} else {
							tail_of({ ..base, part: 3, sid: first }, after)
						}
				}
			}
	}

	## A topic's tail (chat.zig `topicRoute`).
	tail_of : R, List(List(U8)) -> R
	tail_of = |r, segs| {
		tails = ["", "uploads", "stream", "send", "upload", "pin", "unpin", "raw", "download", "saved", "reactions", "react"]
		match segs {
			[] => r
			[first, ..] if first == Str.to_utf8("uploads") =>
				match segs {
					[_, file] => { ..r, tail: 1, rest: file }
					_ => { ..r, tail: 12 }
				}
			[first] =>
				match index_of(tails, first, 1) {
					Ok(i) => { ..r, tail: i }
					Err(None) => { ..r, tail: 12 }
				}
			[first, ..] => { ..r, tail: if first == Str.to_utf8("send") 13 else 12 }
		}
	}

	index_of : List(Str), List(U8), U8 -> Try(U8, [None])
	index_of = |names, seg, i|
		if U8.to_u64(i) >= List.len(names) {
			Err(None)
		} else {
			match List.get(names, U8.to_u64(i)) {
				Ok(n) => if Str.to_utf8(n) == seg Ok(i) else index_of(names, seg, i + 1)
				Err(_) => Err(None)
			}
		}

	with_rest : U8, List(U8) -> R
	with_rest = |f, rest| { ..family(f), rest }

	## The path's segments, empty ones skipped (chat.zig's SegIter).
	segments : List(U8) -> List(List(U8))
	segments = |path| {
		(done, last) = List.fold(path, ([], []), |(segs, cur), b|
			if b == 47 {
				(if cur == [] segs else List.append(segs, cur), [])
			} else {
				(segs, List.append(cur, b))
			})
		if last == [] done else List.append(done, last)
	}

	starts_with : List(U8), List(U8) -> Bool
	starts_with = |l, p| List.len(l) >= List.len(p) and List.take_first(l, List.len(p)) == p

	ends_with : List(U8), List(U8) -> Bool
	ends_with = |l, p| List.len(l) >= List.len(p) and List.take_last(l, List.len(p)) == p

	drop : List(U8), U64 -> List(U8)
	drop = |l, n| List.drop_first(l, n)

	is_alpha : U8 -> Bool
	is_alpha = |c| (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

	is_alnum : U8 -> Bool
	is_alnum = |c| is_alpha(c) or (c >= 48 and c <= 57)

	## chat_paths.zig `validChannelName`: a letter, then letters, digits
	## and hyphens, 1 to 40 bytes.
	valid_channel_name : List(U8) -> Bool
	valid_channel_name = |name| match name {
		[first, .. as more] =>
			List.len(name) <= 40 and is_alpha(first) and List.all(more, |c| is_alnum(c) or c == 45)
		[] => Bool.False
	}

	## chat_paths.zig `validTopicID`: letters and digits joined by single
	## hyphens, none at either end, 1 to 80 bytes.
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
}
