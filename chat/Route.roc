## WHERE A CHAT PATH GOES, BY ZIG'S RULES (angry-gopher chat.zig's dispatch
## as it was: `handle`, `handleChannel`, `convRoute`, `topicRoute`). Pure:
## the decisions that need the disk or the viewer (whether they are in the
## DM, whether the account or the topic exists) stay in the Zig that serves
## the route, so this says only what the path says.
##
## A path is text (main.handle! checked it at the door); the route it makes
## crosses back to the Zig as bytes (to_wire; Chat.roc's `Route`).
import Paths

Route := [].{

	## The route for `sub`, the path under /chat.
	under_chat : Str -> R
	under_chat = |sub|
		if sub.is_empty() or sub == "/" {
			family(Default)
		} else {
			match family_under(sub) {
				Ok(r) => r
				Err(NotUnderAPrefix) =>
					if sub.starts_with("/search") {
						with_rest(Search, sub.drop_prefix("/search"))
					} else if sub == "/default" {
						family(Default)
					} else if sub == "/conversations" {
						family(Conversations)
					} else if sub.starts_with("/msg/") {
						with_rest(Msg, sub.drop_prefix("/msg/"))
					} else if sub.starts_with("/c/") {
						conversation(Dm, segments(sub.drop_prefix("/c/")))
					} else if sub == "/notifications" {
						family(Notifications)
					} else if sub == "/sidebar/stream" {
						family(SidebarStream)
					} else {
						family(NotFound)
					}
			}
		}

	## The route for `sub`, the path under /channel.
	under_channel : Str -> R
	under_channel = |sub| conversation(Channel, segments(sub))

	## A static script: `/<name>.js` under /chat, `rest` the name.
	asset : Str -> Try(R, [NotAnAsset])
	asset = |sub|
		if sub.count_utf8_bytes() > 1 and sub.ends_with(".js") {
			Ok(with_rest(Asset, sub.drop_prefix("/")))
		} else {
			Err(NotAnAsset)
		}

	## A live stream, which presence does not count: a topic's, the two
	## cross-page ones, and the feeds'. From the route, not the path's
	## spelling: `.../stream/` is a topic's stream, and a topic named
	## `stream` is a page.
	is_stream : R -> Bool
	is_stream = |r|
		match r.family {
			Notifications | SidebarStream => Bool.True
			Recent | Images | Code => r.rest == "/stream"
			_ => r.tail == Stream
		}

	## A route, as Chat.roc's `Route` (records are structural: the same
	## type).
	R : {
		family : Family,
		key : Str,
		rest : Str,
		topic : Str,
		part : Part,
		tail : Tail,
	}

	## The route as it crosses back to the Zig: Chat.roc's `Route`, bytes.
	to_wire : R -> {
		family : Family,
		key : List(U8),
		rest : List(U8),
		topic : List(U8),
		part : Part,
		tail : Tail,
	}
	to_wire = |r| {
		family: r.family,
		key: r.key.to_utf8(),
		rest: r.rest.to_utf8(),
		topic: r.topic.to_utf8(),
		part: r.part,
		tail: r.tail,
	}

	## Chat.roc's, spelled again (aliases are structural: the same types).
	Family : [
		NotFound,
		Asset,
		Default,
		Docs,
		Recent,
		Images,
		Code,
		Links,
		Search,
		Conversations,
		Msg,
		Dm,
		Channel,
		Notifications,
		SidebarStream,
	]
	Part : [
		Landing,
		New,
		Invalid,
		Topic,
	]
	Tail : [
		Page,
		Uploads,
		Stream,
		Send,
		Upload,
		Pin,
		Unpin,
		Raw,
		Download,
		Saved,
		Reactions,
		React,
		Invalid,
		InvalidSend,
	]

	## A route of `family` with nothing else.
	family : Family -> R
	family = |f| {
		family: f,
		key: "",
		rest: "",
		topic: "",
		part: Landing,
		tail: Page,
	}

	## A DM's or a channel's route from its path's segments.
	conversation : Family, List(Str) -> R
	conversation = |f, segs| match segs {
		[] => family(NotFound)
		[key, .. as more] =>
			if f == Channel and !Paths.is_channel_name(key) {
				family(NotFound)
			} else {
				base = { ..family(f), key }
				match more {
					[] => base
					[first, .. as after] =>
						if first == "new" {
							{ ..base, part: New }
						} else if !Paths.is_topic_id(first) {
							{ ..base, part: Invalid }
						} else {
							tail_of(
								{
									..base,
									part: Topic,
									topic: first,
								},
								after,
							)
						}
				}
			}
	}
}

## The five families under a prefix of their own, at a segment's
## boundary (`/docsX` is none of them).
family_under : Str -> Try(R, [NotUnderAPrefix])
family_under = |sub| {
	named = [
		("/docs", Docs),
		("/recent", Recent),
		("/images", Images),
		("/code", Code),
		("/links", Links),
	]
	List.fold(
		named,
		Err(NotUnderAPrefix),
		|found, (prefix, f)|
			match found {
				Ok(r) => Ok(r)
				Err(NotUnderAPrefix) =>
					if sub.starts_with(prefix) {
						rest = sub.drop_prefix(prefix)
						if rest.is_empty() or rest.starts_with("/") Ok(
							with_rest(
								f,
								rest,
							),
						) else Err(NotUnderAPrefix)
					} else {
						Err(NotUnderAPrefix)
					}
			},
	)
}

## A topic's tail (chat.zig `topicRoute`): one segment naming it, or
## `uploads/<file>`.
tail_of : R, List(Str) -> R
tail_of = |r, segs|
	match segs {
		[] => r
		[first, ..] if first == "uploads" =>
			match segs {
				[_, file] => {
					..r,
					tail: Uploads,
					rest: file,
				}
				_ => { ..r, tail: Invalid }
			}
		[first] => { ..r, tail: named_tail(first) }
		[first, ..] => { ..r, tail: if first == "send" InvalidSend else Invalid }
	}

## The tail one segment names, or `Invalid`.
named_tail : Str -> Tail
named_tail = |seg| {
	tails = [
		("stream", Stream),
		("send", Send),
		("upload", Upload),
		("pin", Pin),
		("unpin", Unpin),
		("raw", Raw),
		("download", Download),
		("saved", Saved),
		("reactions", Reactions),
		("react", React),
	]
	List.fold(tails, Invalid, |found, (name, tail)|
		if found == Invalid and name == seg tail else found)
}

with_rest : Family, Str -> R
with_rest = |f, rest| { ..Route.family(f), rest }

## The path's segments, empty ones skipped (chat.zig's SegIter).
segments : Str -> List(Str)
segments = |path| path.split_on("/").drop_if(|s| s.is_empty())
