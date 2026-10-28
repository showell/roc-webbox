## WHERE A CHAT PATH GOES, BY ZIG'S RULES (angry-gopher chat.zig's dispatch
## as it was: `handle`, `handleChannel`, `convRoute`, `topicRoute`). Pure:
## the decisions that need the disk or the viewer (whether they are in the
## DM, whether the account or the topic exists) are main.roc's, which
## serves the route, so this says only what the path says.
##
## A path is text (main.handle! checked it at the door).
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

	## A static script: `/<name>.js` under /chat, its name.
	asset : Str -> Try(Str, [NotAnAsset])
	asset = |sub|
		if sub.count_utf8_bytes() > 1 and sub.ends_with(".js") {
			Ok(sub.drop_prefix("/"))
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

	## A route: a family, and for a conversation its key, its part, and for
	## a topic its id and tail. `rest` is the family's own remainder: the
	## rest of a docs/recent/images/code/links/search path, a message id, an
	## upload's file. Unused fields are empty, `Landing` and `Page`, so two
	## routes are equal exactly when they go the same place.
	R : {
		family : Family,
		key : Str,
		rest : Str,
		topic : Str,
		part : Part,
		tail : Tail,
	}

	## Which part of the chat a path names.
	Family : [
		NotFound,
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

	## Which part of a conversation: none named (`Landing`), `.../new`, a
	## topic id that is not one (refused after the conversation's own
	## checks), or a topic, `tail` what of it.
	Part : [
		Landing,
		New,
		Invalid,
		Topic,
	]

	## What of a topic. `Invalid` is no tail there is (refused once the
	## topic is known to exist); `InvalidSend` the same under `send`, which
	## skips that check (a send makes its topic).
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
