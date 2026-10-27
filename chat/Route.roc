## WHERE A CHAT PATH GOES, BY ZIG'S RULES (angry-gopher chat.zig's dispatch
## as it was: `handle`, `handleChannel`, `convRoute`, `topicRoute`). Pure:
## the decisions that need the disk or the viewer (whether they are in the
## DM, whether the account or the topic exists) stay in the Zig that serves
## the route, so this says only what the path says.
##
## A path is bytes (Chat.roc): every comparison is on bytes.
import Bytes
import Paths

Route := [].{

	## The route for `sub`, the path under /chat.
	under_chat : List(U8) -> R
	under_chat = |sub|
		if sub == [] or sub == slash {
			family(Default)
		} else {
			match family_under(sub) {
				Ok(r) => r
				Err(None) =>
					match Bytes.strip_prefix(sub, Str.to_utf8("/search")) {
						Ok(rest) => with_rest(Search, rest)
						Err(NoMatch) =>
							if sub == Str.to_utf8("/default") {
								family(Default)
							} else if sub == Str.to_utf8("/conversations") {
								family(Conversations)
							} else {
								match Bytes.strip_prefix(sub, Str.to_utf8("/msg/")) {
									Ok(rest) => with_rest(Msg, rest)
									Err(NoMatch) =>
										match Bytes.strip_prefix(sub, Str.to_utf8("/c/")) {
											Ok(rest) => conversation(Dm, segments(rest))
											Err(NoMatch) =>
												if sub == Str.to_utf8("/notifications") {
													family(Notifications)
												} else if sub == Str.to_utf8("/sidebar/stream") {
													family(SidebarStream)
												} else {
													family(NotFound)
												}
										}
								}
							}
					}
			}
		}

	## The route for `sub`, the path under /channel.
	under_channel : List(U8) -> R
	under_channel = |sub| conversation(Channel, segments(sub))

	## A static script: `/<name>.js` under /chat, `rest` the name.
	asset : List(U8) -> Try(R, [None])
	asset = |sub|
		if List.len(sub) > 1 and ends_with(sub, Str.to_utf8(".js")) {
			Ok(with_rest(Asset, List.drop_first(sub, 1)))
		} else {
			Err(None)
		}

	## A live stream, which presence does not count: a topic's, the two
	## cross-page ones, and the feeds'. From the route, not the path's
	## spelling: `.../stream/` is a topic's stream, and a topic named
	## `stream` is a page.
	is_stream : R -> Bool
	is_stream = |r|
		match r.family {
			Notifications | SidebarStream => Bool.True
			Recent | Images | Code => r.rest == Str.to_utf8("/stream")
			_ => r.tail == Stream
		}

	## A route, as Chat.roc's `Route` (records are structural: the same
	## type).
	R : { family : Family, key : List(U8), rest : List(U8), topic : List(U8), part : Part, tail : Tail }

	## Chat.roc's, spelled again (aliases are structural: the same types).
	Family : [NotFound, Asset, Default, Docs, Recent, Images, Code, Links, Search, Conversations, Msg, Dm, Channel, Notifications, SidebarStream]
	Part : [Landing, New, Invalid, Topic]
	Tail : [Page, Uploads, Stream, Send, Upload, Pin, Unpin, Raw, Download, Saved, Reactions, React, Invalid, InvalidSend]

	## A route of `family` with nothing else.
	family : Family -> R
	family = |f| { family: f, key: [], rest: [], topic: [], part: Landing, tail: Page }

	slash = ['/']

	## The five families under a prefix of their own, at a segment's
	## boundary (`/docsX` is none of them).
	family_under : List(U8) -> Try(R, [None])
	family_under = |sub| {
		named = [("/docs", Docs), ("/recent", Recent), ("/images", Images), ("/code", Code), ("/links", Links)]
		List.fold(
			named,
			Err(None),
			|found, (prefix, f)|
				match found {
					Ok(r) => Ok(r)
					Err(None) =>
						match Bytes.strip_prefix(sub, Str.to_utf8(prefix)) {
							Ok(rest) if rest == [] or Bytes.starts_with(rest, slash) => Ok(with_rest(f, rest))
							_ => Err(None)
						}
				},
		)
	}

	## A DM's or a channel's route from its path's segments.
	conversation : Family, List(List(U8)) -> R
	conversation = |f, segs| match segs {
		[] => family(NotFound)
		[key, .. as more] =>
			if f == Channel and !valid_channel_name(key) {
				family(NotFound)
			} else {
				base = { ..family(f), key }
				match more {
					[] => base
					[first, .. as after] =>
						if first == Str.to_utf8("new") {
							{ ..base, part: New }
						} else if !valid_topic_id(first) {
							{ ..base, part: Invalid }
						} else {
							tail_of({ ..base, part: Topic, topic: first }, after)
						}
				}
			}
	}

	## A topic's tail (chat.zig `topicRoute`): one segment naming it, or
	## `uploads/<file>`.
	tail_of : R, List(List(U8)) -> R
	tail_of = |r, segs|
		match segs {
			[] => r
			[first, ..] if first == Str.to_utf8("uploads") =>
				match segs {
					[_, file] => { ..r, tail: Uploads, rest: file }
					_ => { ..r, tail: Invalid }
				}
			[first] => { ..r, tail: named_tail(first) }
			[first, ..] => { ..r, tail: if first == Str.to_utf8("send") InvalidSend else Invalid }
		}

	## The tail one segment names, or `Invalid`.
	named_tail : List(U8) -> Tail
	named_tail = |seg| {
		tails = [("stream", Stream), ("send", Send), ("upload", Upload), ("pin", Pin), ("unpin", Unpin), ("raw", Raw), ("download", Download), ("saved", Saved), ("reactions", Reactions), ("react", React)]
		List.fold(tails, Invalid, |found, (name, tail)|
			if found == Invalid and Str.to_utf8(name) == seg tail else found)
	}

	with_rest : Family, List(U8) -> R
	with_rest = |f, rest| { ..family(f), rest }

	## The path's segments, empty ones skipped (chat.zig's SegIter).
	segments : List(U8) -> List(List(U8))
	segments = |path| {
		(done, last) = List.fold(
			path,
			([], []),
			|(segs, cur), b|
				if b == '/' {
					(if cur == [] segs else List.append(segs, cur), [])
				} else {
					(segs, List.append(cur, b))
				},
		)
		if last == [] done else List.append(done, last)
	}

	ends_with : List(U8), List(U8) -> Bool
	ends_with = |l, p| List.len(l) >= List.len(p) and List.take_last(l, List.len(p)) == p

	valid_channel_name = Paths.valid_channel_name
	valid_topic_id = Paths.valid_topic_id

}
