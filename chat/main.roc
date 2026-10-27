## THE ROC CHAT: the router (docs/ROC-CHAT.md §3, milestone 1). Every /chat
## and /channel request angry-gopher has comes here first. The router runs
## the prelude angry-gopher's chat.zig `handle` and `handleChannel` ran,
## parses the path (Route.roc), and hands the route to Zig, which serves it
## once this call has returned.
##
## The prelude, in Zig's order:
##   1. a static script under /chat (`/<name>.js`) is served to anyone;
##   2. anyone not a member or the agent is sent to sign in, and returned;
##   3. every other request counts as presence, but a stream (by its route:
##      chat.zig read it from the path's spelling, so `.../stream/` counted).
##
## A topic's reactions, react, pin and unpin are the Roc's (docs/ROC-CHAT.md
## C4, `act!`); a reaction is the Roc's whole (its reactor, its bound, its
## stamp, its line and its frame), stored and sent through the primitives
## (`append_line!`, `message_count!`, `publish!`); a message is the Roc's
## too (`appended!`: its author, number, stamp, block and frame), stored
## through `store_message!` (the append, the count cache, the search index),
## and its fan-out (Fanout.roc: every member's surfaces, their keys, events
## and feed entries) through `publish!`, `append_entry!` and
## `fanout_failed!`, the message's parts its own (Fanout.parts_of). The files and folders it reads by name (the member's own, a
## conversation's topics, a channel's members, the rosters, a topic's
## reactions) it reads through the file primitives, the names and formats
## its own.
app [handle!] { pf: platform "platform/main.roc" }

import pf.Chat
import pf.Host
import Route
import Reaction
import Pages
import Chrome
import Html
import Paths
import Topics
import Form
import ZigText
import Uid
import Feeds
import Recent
import ChatState
import Files
import Conversation
import Accounts
import Frame
import Time
import Transcript
import Fanout

handle! : Chat.Request => Chat.Answer
handle! = |req|
	# **A PATH IS TEXT AT THE DOOR**: one that is not UTF-8 is the site's 400
	# for a malformed request, before anything else reads it.
	match Str.from_utf8(req.sub) {
		Ok(sub) => routed!(req, sub)
		Err(_) => Chat.malformed
	}

## The request, its path (`sub`) the text handle! checked.
routed! : Chat.Request, Str => Chat.Answer
routed! = |req, sub|
	match (if req.area == Channel Err(NotAnAsset) else Route.asset(sub)) {
		Ok(route) => zig(route, Uncounted)
		Err(NotAnAsset) =>
			if !Host.member!({}) {
				area = if req.area == Channel "/channel" else "/chat"
				Chat.redirect(List.concat(Str.to_utf8("/login/full?next=${area}"), req.sub))
			} else {
				route = if req.area == Channel Route.under_channel(sub) else Route.under_chat(sub)
				if roc_serves(route) act!(req, route) else zig(route, if Route.is_stream(route) Uncounted else Counted)
			}
	}

## The route handed back to the Zig, as the seam's bytes.
zig : Route.R, Chat.Counting -> Chat.Answer
zig = |route, counting| Chat.zig(Route.to_wire(route), counting)

## The routes the Roc serves itself: /chat and /chat/default, the recent,
## images and code pages (not their streams), /chat/links,
## /chat/conversations, /chat/msg/<id>; and in a DM or a channel its
## landing, a new topic, and a topic's page, raw transcript, send,
## reactions, react, pin and unpin. Every other route is Zig's.
roc_serves : Route.R -> Bool
roc_serves = |r|
	match r.family {
		Default | Links | Conversations | Msg => Bool.True
		Recent | Images | Code => r.rest != "/stream"
		Dm | Channel =>
			match r.part {
				Landing | New => Bool.True
				Invalid => Bool.False
				Topic =>
					match r.tail {
						Page | Raw | Send | InvalidSend | Reactions | React | Pin | Unpin => Bool.True
						_ => Bool.False
					}
			}
		_ => Bool.False
	}

## The Roc's own routes: presence, then the route's own work.
act! : Chat.Request, Route.R => Chat.Answer
act! = |req, route| {
	Host.presence!({})
	match route.family {
		Default => resume!({})
		Conversations => if req.method != Get Chat.not_allowed(Get) else conversations!({})
		Msg => msg!(route.rest.to_utf8())
		Links => links!(route.rest.to_utf8())
		Recent => recent!(route.rest.to_utf8())
		Images => feed!(Images, route.rest.to_utf8())
		Code => feed!(Code, route.rest.to_utf8())
		_ => in_conversation!(req, route)
	}
}

## A DM's or a channel's, in the Zig's order: a new topic and a send look
## their conversation up themselves (a send makes its topic); the landing
## needs no topic; everything else needs the topic there (a miss is Zig's
## to answer, the same 404s), then the method, then the work.
in_conversation! : Chat.Request, Route.R => Chat.Answer
in_conversation! = |req, route|
	match conv_key(route) {
		# **A KEY THAT NAMES NO CONVERSATION IS THE ZIG'S 404**, as find!
		# answered it: no pair (Paths.participant's rule), no valid name.
		Err(Invalid) => zig(route, Uncounted)
		Ok(key) =>
			if route.part == New {
				new_topic!(req, route, key)
			} else if route.tail == Send or route.tail == InvalidSend {
				send!(req, route, key)
			} else if route.part == Landing {
				landing!(route, key)
			} else {
				match find!(key) {
					Err(NotYours) => zig(route, Uncounted)
					Err(Failed) => Chat.answered
					Ok((conv, who)) =>
					# The title before the topics, as findTopic read them: a
					# partner whose name will not read fails every topic route.
						match title!(conv, key, who) {
							Err(Failed) => Chat.answered
							Ok(t) => {
								topics = topics!(key)
								if Conversation.has_topic(topics, route.topic) {
									in_topic!(req, route, { key, conv, who, title: Conversation.topic_title(t, route.topic), topics })
								} else {
									zig(route, Uncounted)
								}
							}
						}
				}
			}
	}

## **THE CONVERSATION'S KEY, BUILT ONCE, WHERE THE REQUEST COMES IN**: the
## route's key as a DM's pair key (Paths.pair_key_from_str) or a channel's
## name (Paths.channel_name_from_str); every path past here is built from
## it.
conv_key : Route.R -> Try(Paths.ConvKey, [Invalid])
conv_key = |route|
	match route.family {
		Dm => Paths.pair_key_from_str(route.key).map_ok(|pair| Dm(pair))
		Channel => Paths.channel_name_from_str(route.key).map_ok(|name| Channel(name))
		_ => Err(Invalid)
	}

## A topic found: its conversation, the accounts as far as they were asked,
## its title, and the conversation's topics as they were listed to find it.
AtTopic : { key : Paths.ConvKey, conv : Chat.Conv, who : Who, title : List(U8), topics : List(Str) }

## A topic that is there: the method, then the work.
in_topic! : Chat.Request, Route.R, AtTopic => Chat.Answer
in_topic! = |req, route, found| {
	conv = found.conv
	who = found.who
	match route.tail {
		Page | Raw =>
			if req.method != Get and req.method != Head {
				Chat.not_allowed(Get)
			} else if route.tail == Page {
				page!(route, found)
			} else if Files.held_raw!(Paths.transcript_path({ key: found.key, topic: route.topic })) {
				Chat.held_plain
			} else {
				Chat.not_found
			}
		Reactions =>
			if req.method != Get {
				Chat.not_allowed(Get)
			} else {
				# readReactions's: nobody has reacted yet is no events.
				ndjson = Str.to_utf8("application/x-ndjson; charset=utf-8")
				match Files.read!(Paths.reactions_path({ key: found.key, topic: route.topic })) {
					Ok(text) => Chat.respond(200, ndjson, Str.to_utf8(text))
					Err(Missing) => Chat.respond(200, ndjson, [])
					Err(Failed) => Chat.answered
				}
			}
		_ =>
			if req.method != Post {
				Chat.not_allowed(Post)
			} else if route.tail == React {
				react!(conv, who, { key: found.key, topic: route.topic })
			} else {
				match pin!(found.key, route.topic, if route.tail == Pin Pinned else Unpinned) {
					Ok({}) => Chat.respond(204, [], [])
					Err(Failed) => Chat.answered
				}
			}
	}
}

## **THE CONVERSATION A DM OR CHANNEL ROUTE NAMES, IF IT IS THE MEMBER'S**
## (angry-gopher chat.zig `findConv`): a DM whose pair holds the member
## and whose other half is an account; a channel that lists the member.
## `NotYours` for every 404 the Zig answers (the route handed back to it,
## whose page says why); `Failed` when a read failed (the request has).
## A DM's accounts come back `Known`, for what looks one up next; a
## channel's are not asked.
find! : Paths.ConvKey => Try((Chat.Conv, Who), [NotYours, Failed])
find! = |key| {
	bytes = Paths.conv_key_bytes(key)
	me = me!({})?
	match key {
		Dm(pair) =>
			match Conversation.dm_other(pair, me) {
				Ok(other) =>
					match accounts!(Unasked) {
						Ok(all) =>
							if Accounts.exists(all, other) {
								Ok(({ family: Dm, key: bytes, base: Conversation.dm_base(bytes), members: Conversation.dm_members(bytes) }, Known(all)))
							} else {
								Err(NotYours)
							}
						Err(Failed) => Err(Failed)
					}
				Err(NotAParticipant) => Err(NotYours)
			}
		Channel(name) => {
			members = channel_members!(name)
			if List.contains(members, me.to_str().to_utf8()) {
				Ok(({ family: Channel, key: bytes, base: Conversation.channel_base(bytes), members }, Unasked))
			} else {
				Err(NotYours)
			}
		}
	}
}

## **THE ACCOUNTS ARE ASKED OF THE HOST AT MOST ONCE A REQUEST**
## (Host.accounts! lists every one, two reads each): `Known` once asked,
## handed down to whatever looks one up next; `Unasked` until a route first
## needs them.
Who : [Known(List(Accounts.Account)), Unasked]

## The accounts: those already asked, or the host's now. `Failed` when they
## could not be listed: the request has failed, and no lookup is made on
## nothing. An account that would not read is among them, and fails the
## request only when a lookup needs it (`named!`): never "no such account".
accounts! : Who => Try(List(Accounts.Account), [Failed])
accounts! = |who|
	match who {
		Known(all) => Ok(all)
		Unasked => {
			got = Host.accounts!({})
			match got.status {
				# **EACH ID DECODED HERE, AT THE DOOR**: the host lists only the
				# folders a counter named, so one that is no uid fails the
				# request (NotUtf8, about it).
				Found =>
					match List.keep_if(got.accounts, |a| uid_of(a.id).is_err()) {
						[bad, ..] => {
							Host.fail!(NotUtf8, bad.id)
							Err(Failed)
						}
						[] => Ok(List.keep_oks(got.accounts, |a| uid_of(a.id).map_ok(|id| { id, kind: a.kind, name: a.name, name_read: a.name_read })))
					}
				Failed => Err(Failed)
			}
		}
	}

## The member's name (getUserName of their own id), from the accounts.
## `Failed` when it would not read (the request has failed with its error).
viewer! : Who => Try(List(U8), [Failed])
viewer! = |who| {
	me = me!({})?
	match accounts!(who) {
		Ok(all) => named!(Accounts.name(all, me))
		Err(Failed) => Err(Failed)
	}
}

## **THE MEMBER'S ID, DECODED WHERE THE HOST HANDS IT** (Host.me!): a
## session is signed only for an id a counter made, so one that is no
## canonical uid fails the request (NotUtf8, about the id), and `Failed`.
me! : {} => Try(Uid, [Failed])
me! = |{}| {
	bytes = Host.me!({})
	match Uid.from_str(Str.from_utf8(bytes) ?? "") {
		Ok(uid) => Ok(uid)
		Err(NotAUid) => {
			Host.fail!(NotUtf8, bytes)
			Err(Failed)
		}
	}
}

## A lookup's answer, or, when it needed an account's read that failed, the
## request failed with that read's error (`unreadable!`) and `Failed`.
named! : Try(a, Accounts.Unreadable) => Try(a, [Failed])
named! = |looked|
	match looked {
		Ok(answer) => Ok(answer)
		Err(why) => {
			unreadable!(why)
			Err(Failed)
		}
	}

## **THE REQUEST FAILS WITH THE ACCOUNT'S OWN ERROR**: a lookup needed
## account `id`'s kind or name, which `accounts!` listed as unreadable, so
## the host fails the request with the error that read failed with, as the
## Zig's own read of it did.
unreadable! : Accounts.Unreadable => {}
unreadable! = |why|
	match why {
		KindUnreadable(id) => Host.fail!(KindUnreadable, id.to_str().to_utf8())
		NameUnreadable(id) => Host.fail!(NameUnreadable, id.to_str().to_utf8())
	}

## Channel `name`'s members, as its member file lists them (Paths's
## parse); none when there is no such channel. **A MALFORMED ONE FAILS THE
## REQUEST** on its own route (channelMembers's error.MalformedChannel), never
## the 404 of a channel that is not the member's; a read that failed has
## failed it already.
channel_members! : Paths.ChannelName => List(List(U8))
channel_members! = |name|
	match text_bytes!(Paths.channel_path(name)) {
		Ok(bytes) =>
			match Paths.channel_members(bytes) {
				Ok(members) => members
				Err(Malformed) => {
					Host.fail!(MalformedChannel, Paths.channel_name_bytes(name))
					[]
				}
			}
		Err(Missing) | Err(Failed) => []
	}

## **EVERY CHANNEL'S ROSTER** (channelRosters): channels/ listed
## (Paths.channel_names), then each member file read and judged in the
## listing's order (Paths.roster), a malformed one counted as it is met
## (Host.malformed_channel!), as the Zig counted it, before any read after
## it can fail. `Failed` when the listing or a member file would not read
## (the request has failed with its error): **NEVER THE ROSTERS THAT READ
## BEFORE IT**, which would leave the rest out.
channel_rosters! : {} => Try(List(Paths.Roster), [Failed])
channel_rosters! = |{}| {
	match Files.list!(Paths.channels_folder) {
		Ok(listed) => {
			# A channel whose name is not UTF-8 is skipped, and counted as a
			# malformed one is.
			List.for_each!(Paths.channel_names_not_utf8(listed.not_utf8), |name| Host.malformed_channel!(name))
			rosters!(Paths.channel_names(listed.entries), 0, [])
		}
		Err(Missing) => Ok([])
		Err(Failed) => Err(Failed)
	}
}

rosters! : List(Str), U64, List(Paths.Roster) => Try(List(Paths.Roster), [Failed])
rosters! = |names, i, out|
	match List.get(names, i) {
		Err(_) => Ok(out)
		Ok(name) =>
			match Paths.channel_name_from_str(name) {
				Ok(valid) =>
					match Paths.roster(name, text_bytes!(Paths.channel_path(valid))) {
						Listed(r) => rosters!(names, i + 1, List.append(out, r))
						Malformed => {
							Host.malformed_channel!(name.to_utf8())
							rosters!(names, i + 1, out)
						}
						Gone => rosters!(names, i + 1, out)
						Failed => Err(Failed)
					}
				Err(Invalid) => {
					Host.malformed_channel!(name.to_utf8())
					rosters!(names, i + 1, out)
				}
			}
	}

## **A CONVERSATION'S TOPICS** (listTopics): its sessions folder listed,
## the choice Paths.topics's.
topics! : Paths.ConvKey => List(Str)
topics! = |key| Paths.topics(list!(Paths.topics_folder(key)))

## Files.list!'s entries. **NOTHING THERE HOLDS NOTHING** (webbox's
## store.list); a listing that failed has failed the request, and answers
## nothing too, so what follows writes nothing (the host does nothing more).
## A name that is not UTF-8 is no topic, and no counter is kept of it.
list! : Paths.ChatPath => List(Paths.Entry)
list! = |path|
	match Files.list!(path) {
		Ok(listed) => listed.entries
		Err(Missing) | Err(Failed) => []
	}

## `conv`'s title (convTitle): a DM's partner's name (its accounts known
## since find!), a channel's own. `Failed` when the partner's name would not
## read (the request has failed with its error).
title! : Chat.Conv, Paths.ConvKey, Who => Try(List(U8), [Failed])
title! = |conv, key, who|
	match key {
		Dm(pair) =>
			match accounts!(who) {
				Ok(all) => {
					other = Paths.partner(pair, me!({})?)
					match named!(Accounts.name(all, other)) {
						Ok(name) => Ok(Conversation.dm_title(name, other))
						Err(Failed) => Err(Failed)
					}
				}
				Err(Failed) => Err(Failed)
			}
		Channel(_) => Ok(Conversation.channel_title(conv.key))
	}

## POST .../pin and .../unpin: the member's pins in the conversation read,
## `topic` pinned or unpinned (ChatState.pinned), and the file written back or,
## emptied, removed. A read that failed stops here: the set is not empty, it
## is unknown, and writing it would drop every pin. `Failed` when a step failed.
pin! : Paths.ConvKey, Str, ChatState.Pin => Try({}, [Failed])
pin! = |key, topic, pin| {
	path = Paths.pinned_path(me!({})?, key)
	match text_bytes!(path) {
		Ok(stored) => repin!(path, stored, topic, pin)
		Err(Missing) => repin!(path, [], topic, pin)
		Err(Failed) => Err(Failed)
	}
}

## The pinned file at `path`, read as `stored`, with `topic` pinned or
## unpinned: written back, or, emptied, removed.
repin! : Paths.ChatPath, List(U8), Str, ChatState.Pin => Try({}, [Failed])
repin! = |path, stored, topic, pin|
	match ChatState.pinned(stored, topic.to_utf8(), pin) {
		Write(bytes) => Files.write!(path, bytes)
		Remove => Files.remove!(path)
	}

## **WHERE THE MEMBER RESUMES DM `conv`: TOPIC `topic`** (setLastViewedTopic):
## the topic last viewed there first, then the DM last in, each written
## only when it changed (ChatState.changed); `Failed` when a step failed,
## and nothing after it is written. A topic with no name records nothing.
bookmark! : Paths.ConvKey, Str => Try({}, [Failed])
bookmark! = |key, topic| {
	me = me!({})?
	if topic.is_empty() {
		Ok({})
	} else {
		write_if_changed!(Paths.last_session_path(me, key), topic.to_utf8())?
		write_if_changed!(Paths.last_conv_path(me), Paths.conv_key_bytes(key))
	}
}

## **WRITTEN ONLY WHEN IT CHANGES** (zig-metal-unikernel 153(1)): on every
## send and view the value is usually the one already there, and a write is
## disk requests each time.
write_if_changed! : Paths.ChatPath, List(U8) => Try({}, [Failed])
write_if_changed! = |path, value|
	if ChatState.changed(text_bytes!(path), value) Files.write!(path, ChatState.bookmark_line(value)) else Ok({})

## TEMPORARY DOOR: moves out in a later run. A file's text (Files.read!,
## which refuses bytes that are not UTF-8) as bytes, for the parsers not yet
## on Str: ChatState's, Feeds's and Paths.roster.
text_bytes! : Paths.ChatPath => Try(List(U8), [Missing, Failed])
text_bytes! = |path| Files.read!(path).map_ok(Str.to_utf8)

## POST .../react: the form, then the reaction stored and sent live.
react! : Chat.Conv, Who, Paths.TopicAt => Chat.Answer
react! = |conv, who, at| {
	body = Host.body!(Reaction)
	if body.status == Answered {
		Chat.answered
	} else {
		match Reaction.form(body.bytes) {
			Malformed => Chat.malformed
			Bad(why) => Chat.respond(400, [], why)
			Reacted(r) =>
				match reacted!(conv, who, at, r) {
					Stored => Chat.respond(204, [], [])
					NoSuchMessage => Chat.respond(400, [], Str.to_utf8("react: no such message\n"))
					Failed => Chat.answered
				}
		}
	}
}

## **A REACTION STORED, THEN SENT LIVE** (storeReaction, appendReaction):
## the reactor's own name (getUserName, from the accounts), the message
## judged against the topic's count, the line stamped with the request's
## time, then its sidecar line appended and its frame published on the
## topic's key. `Failed` when a step failed (the request has, with its
## error), and nothing after it is done.
reacted! : Chat.Conv, Who, Paths.TopicAt, { msg : U64, emoji : List(U8), change : Reaction.Change } => [Stored, NoSuchMessage, Failed]
reacted! = |conv, who, topic_at, r|
	match (viewer!(who), me!({})) {
		(Ok(name), Ok(uid)) => {
			counted = Host.message_count!(conv, topic_at.topic.to_utf8())
			match counted.status {
				Failed => Failed
				Counted =>
				# Message numbers start at 1 (the N of MSG_<topic>_N).
					if r.msg == 0 or r.msg > counted.count {
						NoSuchMessage
					} else {
						at = Time.rfc3339(Host.now!({}))
						line = Reaction.line({ msg: r.msg, uid, from: name, emoji: r.emoji, change: r.change, at })
						# **THE ECHO IS MADE BEFORE THE STORE** (metal-vmm QUEUE
						# 177.1), as a message's: its key and frame, so nothing
						# can fail between the append and the publish.
						key = Fanout.topic_key(topic_at)
						frame = Frame.reaction(line)
						match Files.append_line!(Paths.reactions_path(topic_at), line) {
							Ok({}) => {
								# **STORED IS DONE**: the live publish cannot fail.
								Host.publish!(key, frame)
								Stored
							}
							Err(Failed) => Failed
						}
					}
			}
		}
		_ => Failed
	}

html : List(U8)
html = Str.to_utf8("text/html; charset=utf-8")

## /chat/links, by any method, as the Zig had it: the member's own, or the
## stub; nothing below it.
links! : List(U8) => Chat.Answer
links! = |rest|
	if rest != [] {
		Chat.not_found
	} else {
		match (viewer!(Unasked), me!({})) {
			(Err(Failed), _) | (Ok(_), Err(Failed)) => Chat.answered
			(Ok(viewer), Ok(me)) => {
				src = Chrome.src_in(Host.srcs!({}))
				if Files.held_rendered!(Paths.links_path(me)) {
					(before, after) = Pages.links_around(src, viewer)
					Chat.held_html(before, after)
				} else {
					Chat.respond(200, html, Html.bytes(Pages.links(src, viewer, NoLinks)))
				}
			}
		}
	}

## /chat/recent by any method, as the Zig had it: what the host gathered,
## named, dated, excerpted and ordered here; nothing below it but its stream.
recent! : List(U8) => Chat.Answer
recent! = |rest|
	if rest != [] {
		Chat.not_found
	} else {
		match (viewer!(Unasked), me!({})) {
			(Ok(viewer), Ok(me)) => {
				rows = Recent.rows(Host.recent!({}))
				Chat.respond(200, html, Html.bytes(Pages.recent(Chrome.src_in(Host.srcs!({})), { viewer, json: Recent.json(me, rows) })))
			}
			_ => Chat.answered
		}
	}

## /chat/images (the newest 20 entries) or /chat/code (every one), by any
## method, as the Zig had them; nothing below them but their streams.
feed! : [Images, Code], List(U8) => Chat.Answer
feed! = |which, rest|
	if rest != [] {
		Chat.not_found
	} else {
		match (viewer!(Unasked), me!({})) {
			(Err(Failed), _) | (Ok(_), Err(Failed)) => Chat.answered
			(Ok(viewer), Ok(me)) => {
				# A feed that failed is the request's failure; the page made
				# of nothing is not sent.
				file = match text_bytes!(Paths.feed_path(me, which)) {
					Ok(bytes) => bytes
					Err(Missing) | Err(Failed) => []
				}
				src = Chrome.src_in(Host.srcs!({}))
				page = match which {
					Images => Pages.images(src, { viewer, json: Feeds.images_json(Feeds.images(file), 20) })
					Code => Pages.code(src, { viewer, json: Feeds.code_json(Feeds.code(file)) })
				}
				Chat.respond(200, html, Html.bytes(page))
			}
		}
	}

## A conversation's landing: its first topic, or, with none, the page that
## offers one, the title and viewer read in the Zig's order.
landing! : Route.R, Paths.ConvKey => Chat.Answer
landing! = |route, key|
	match find!(key) {
		Err(NotYours) => zig(route, Uncounted)
		Err(Failed) => Chat.answered
		Ok((conv, who)) => {
			first = Paths.first_of(topics!(key))
			if !first.is_empty() {
				Chat.redirect(List.join([conv.base, ['/'], first.to_utf8()]))
			} else {
				match title!(conv, key, who) {
					Err(Failed) => Chat.answered
					Ok(title) =>
						match viewer!(who) {
							Ok(viewer) => Chat.respond(200, html, Html.bytes(Pages.no_topics(Chrome.src_in(Host.srcs!({})), { viewer, base: conv.base, title })))
							Err(Failed) => Chat.answered
						}
				}
			}
		}
	}

## A topic's page (angry-gopher chat_page.zig `conversationPage`): a DM's
## topic recorded as where the member resumes it first (a bookmark that
## fails serves no page), then the viewer and the sidebar (`sidebar!`), and
## the limits the server enforces (Host.limits!).
page! : Route.R, AtTopic => Chat.Answer
page! = |route, at|
	if at.conv.family == Dm and bookmark!(at.key, route.topic).is_err() {
		Chat.answered
	} else {
		match sidebar!(route.topic, at) {
			Err(Failed) => Chat.answered
			Ok((viewer, sb)) => {
				view = { key: route.key, base: Paths.conv_base(at.key), topic: route.topic, title: at.title, uid: sb.uid, viewer, sidebar_json: Pages.sidebar_json(sb) }
				Chat.respond(200, html, Html.bytes(Pages.conversation(Chrome.src_in(Host.srcs!({})), Host.limits!({}), view)))
			}
		}
	}

## **THE VIEWER AND THE SIDEBAR, READ IN THE ZIG'S ORDER** (conversationPage's
## getUserName, then sidebarOf): the viewer's name; every other authorized
## member (listAuthorized: an account it reads that will not read fails
## it), each online or not at the request's time (Host.online!, one asking
## for all); the member's channels (listUserChannels: a malformed one
## skipped and counted); their pins in this conversation (pinnedTopics,
## sorted); its topics as they were listed to find `topic`. `Failed`
## when a read failed (the request has, with its error): **A PINS FILE
## THAT WILL NOT READ IS NEVER NO PINS.**
sidebar! : Str, AtTopic => Try((List(U8), Pages.Sidebar), [Failed])
sidebar! = |topic, at| {
	uid = me!({})?
	me = uid.to_str().to_utf8()
	match accounts!(at.who) {
		Err(Failed) => Err(Failed)
		Ok(all) =>
			match named!(Accounts.name(all, uid)) {
				Err(Failed) => Err(Failed)
				Ok(viewer) =>
					match named!(Accounts.authorized(all)) {
						Err(Failed) => Err(Failed)
						Ok(roster) => {
							others = List.drop_if(roster, |u| u.id == uid)
							flags = Host.online!(List.map(others, |u| u.id.to_str().to_utf8()))
							match channel_rosters!({}) {
								Err(Failed) => Err(Failed)
								Ok(rosters) =>
									match Files.read!(Paths.pinned_path(uid, at.key)) {
										Err(Failed) => Err(Failed)
										Ok(stored) => Ok((viewer, sidebar_of(uid, topic, at, with_online(others, flags), Paths.member_channels(rosters, me), ChatState.pins(stored))))
										Err(Missing) => Ok((viewer, sidebar_of(uid, topic, at, with_online(others, flags), Paths.member_channels(rosters, me), [])))
									}
							}
						}
					}
			}
	}
}

## The other members, each beside its own flag (Host.online! answers one
## per id, in their order).
with_online : List({ id : Uid, name : List(U8) }), List([Offline, Online]) -> List({ id : Uid, name : List(U8), presence : [Online, Offline] })
with_online = |others, flags|
	List.map_with_index(others, |u, i|
		{ id: u.id, name: u.name, presence: if List.get(flags, i) == Ok(Online) Online else Offline })

sidebar_of : Uid, Str, AtTopic, List({ id : Uid, name : List(U8), presence : [Online, Offline] }), List(Str), List(Str) -> Pages.Sidebar
sidebar_of = |me, topic, at, others, channels, pins|
	{ uid: me, kind: if at.conv.family == Dm Dm else Channel, key: Paths.conv_key_to_str(at.key), base: Paths.conv_base(at.key), topic, others, channels, pins, topics: at.topics }

json : List(U8)
json = Str.to_utf8("application/json; charset=utf-8")

## /chat: the member's last DM, at the topic they resume, or its own page
## when it has no topic yet; with none, the empty /chat.
resume! : {} => Chat.Answer
resume! = |{}|
	match me!({}) {
		Err(Failed) => Chat.answered
		Ok(me) => {
			conv = ChatState.bookmark(text_bytes!(Paths.last_conv_path(me)))
			# The bookmark's bytes are text_bytes!'s, so they decode (its door).
			pair_of = match Str.from_utf8(conv) {
				Ok(text) => Paths.pair_key_from_str(text)
				Err(_) => Err(Invalid)
			}
			match pair_of {
				Ok(pair) if Paths.is_participant(pair, me) => {
					topics = topics!(Dm(pair))
					if Paths.first_of(topics).is_empty() {
						Chat.redirect(List.concat(Str.to_utf8("/chat/c/"), conv))
					} else {
						Chat.redirect(List.join([Str.to_utf8("/chat/c/"), conv, ['/'], resume_at!(me, pair, topics)]))
					}
				}
				_ =>
					match viewer!(Unasked) {
						Ok(viewer) => Chat.respond(200, html, Html.bytes(Pages.no_conversations(Chrome.src_in(Host.srcs!({})), viewer)))
						Err(Failed) => Chat.answered
					}
			}
		}
	}

## Where member `me` resumes DM `conv`, whose topics are `topics`: the
## choice ChatState's, the last-viewed topic and the clock the host's.
resume_at! : Uid, Paths.PairKey, List(Str) => List(U8)
resume_at! = |me, pair, topics| {
	last = ChatState.bookmark(text_bytes!(Paths.last_session_path(me, Dm(pair))))
	ChatState.resume_topic(topics, last, Host.now!({}))
}

## /chat/conversations: a DM with every other member, where the member
## resumes it, and its topics.
conversations! : {} => Chat.Answer
conversations! = |{}|
	match (roster!({}), me!({})) {
		(Ok(members), Ok(me)) => Chat.respond(200, json, Topics.conversations_json(me.to_str().to_utf8(), entries!(me, members, 0, [])))
		(Err(Failed), _) | (Ok(_), Err(Failed)) => Chat.answered
	}

## The authorized roster (listAuthorized), from the accounts. `Failed` when
## the accounts could not be listed, or one the roster reads would not read
## (the request has failed with its error).
roster! : {} => Try(List({ id : Uid, name : List(U8) }), [Failed])
roster! = |{}|
	match accounts!(Unasked) {
		Ok(all) => named!(Accounts.authorized(all))
		Err(Failed) => Err(Failed)
	}

entries! : Uid, List({ id : Uid, name : List(U8) }), U64, List(Topics.Entry) => List(Topics.Entry)
entries! = |me, members, i, acc|
	match List.get(members, i) {
		Ok({ id, name }) =>
			if id == me {
				entries!(me, members, i + 1, acc)
			} else {
				pair = Paths.pair_key(me, id)
				conv = Paths.pair_key_bytes(pair)
				listed = topics!(Dm(pair))
				sessions = List.map(listed, Str.to_utf8)
				default = resume_at!(me, pair, listed)
				entries!(me, members, i + 1, List.append(acc, { conv, id: id.to_str().to_utf8(), name, default, sessions }))
			}
		Err(_) => acc
	}

## An id the host hands as bytes, as a Uid.
uid_of : List(U8) -> Try(Uid, [NotAUid])
uid_of = |bytes| Uid.from_str(Str.from_utf8(bytes) ?? "")

## A conversation's members as Uids: each is a canonical pair's half or a
## line Paths.channel_members checked, so one that is no uid fails the
## request (NotUtf8, about it), and `Failed`.
members! : List(List(U8)) => Try(List(Uid), [Failed])
members! = |all|
	match List.keep_if(all, |m| uid_of(m).is_err()) {
		[bad, ..] => {
			Host.fail!(NotUtf8, bad)
			Err(Failed)
		}
		[] => Ok(List.keep_oks(all, uid_of))
	}

## /chat/msg/<id>: the topic a message id names, in the member's DMs, then
## their channels; a 302 there.
msg! : List(U8) => Chat.Answer
msg! = |id|
	if !Paths.valid_msg_ref_id(id) {
		Chat.not_found
	} else {
		topic = match Paths.cut_last(id, '_') {
			Ok((before, _)) => before
			Err(NoSeparator) => []
		}
		at = |base, key| List.join([Str.to_utf8(base), key, ['/'], topic, Str.to_utf8("#msg-"), id])
		match (me!({}), roster!({})) {
			(Err(Failed), _) | (Ok(_), Err(Failed)) => Chat.answered
			(Ok(me), Ok(members)) =>
				match find_dm!(me, members, topic, 0) {
					Ok(conv) => Chat.found(at("/chat/c/", conv))
					Err(NoSuchTopic) =>
						match channel_rosters!({}) {
							Err(Failed) => Chat.answered
							Ok(rosters) =>
								match find_channel!(Paths.member_channels(rosters, me.to_str().to_utf8()), topic, 0) {
									Ok(name) => Chat.found(at("/channel/", name))
									Err(NoSuchTopic) => Chat.not_found
								}
						}
				}
		}
	}

find_dm! : Uid, List({ id : Uid, name : List(U8) }), List(U8), U64 => Try(List(U8), [NoSuchTopic])
find_dm! = |me, members, topic, i|
	match List.get(members, i) {
		Ok({ id, name: _ }) =>
			if id == me {
				find_dm!(me, members, topic, i + 1)
			} else {
				pair = Paths.pair_key(me, id)
				if List.contains(List.map(topics!(Dm(pair)), Str.to_utf8), topic) Ok(Paths.pair_key_bytes(pair)) else find_dm!(me, members, topic, i + 1)
			}
		Err(_) => Err(NoSuchTopic)
	}

find_channel! : List(Str), List(U8), U64 => Try(List(U8), [NoSuchTopic])
find_channel! = |names, topic, i|
	match List.get(names, i) {
		# Every name here passed channel_name_from_str already (rosters! keeps
		# no other).
		Ok(name) =>
			match Paths.channel_name_from_str(name) {
				Ok(valid) if List.contains(List.map(topics!(Channel(valid)), Str.to_utf8), topic) => Ok(name.to_utf8())
				_ => find_channel!(names, topic, i + 1)
			}
		Err(_) => Err(NoSuchTopic)
	}

## POST <base>/new: a topic made with a first "hi", a DM's announced in its
## highest general<N>; the conversation and topic as JSON.
new_topic! : Chat.Request, Route.R, Paths.ConvKey => Chat.Answer
new_topic! = |req, route, key|
	match find!(key) {
		Ok((conv, who)) =>
			if req.method != Post {
				Chat.not_allowed(Post)
			} else {
				body = Host.body!(Message)
				if body.status == Answered {
					Chat.answered
				} else {
					match Form.field(body.bytes, "topic") {
						Malformed => Chat.malformed
						Found(raw) => make!(key, conv, who, ZigText.trim_str(raw))
						Missing => make!(key, conv, who, "")
					}
				}
			}
		Err(NotYours) => zig(route, Uncounted)
		Err(Failed) => Chat.answered
	}

make! : Paths.ConvKey, Chat.Conv, Who, Str => Chat.Answer
make! = |key, conv, who, topic| {
	if !Paths.is_topic_id(topic) {
		Chat.respond(400, [], Str.to_utf8("Topic must be letters, digits, and hyphens only — no spaces, underscores, or punctuation.\n"))
	} else if Topics.same_name(topic, "new") {
		Chat.respond(400, [], Str.to_utf8("\"new\" is reserved — pick another topic name.\n"))
	} else if Conversation.has_topic(topics!(key), topic) {
		Chat.respond(409, [], Str.to_utf8("That topic already exists.\n"))
	} else {
		match viewer!(who) {
			Err(Failed) => Chat.answered
			Ok(name) => {
				dm = conv.family == Dm
				# The bookmark first, as a send's: one that fails makes no topic.
				if dm and bookmark!(key, topic).is_err() {
					Chat.answered
				} else if !appended!(conv, who, { at: { key, topic }, name, markdown: Str.to_utf8("hi"), cid: [] }) {
					Chat.answered
				} else if dm and !announce!(key, conv, who, topic, name) {
					Chat.answered
				} else {
					Chat.respond(200, json, Topics.made_json({ key, topic }))
				}
			}
		}
	}
}

## A DM's new topic, said where the partner already watches: its highest
## general<N>, unless that is the topic made.
announce! : Paths.ConvKey, Chat.Conv, Who, Str, List(U8) => Bool
announce! = |key, conv, who, topic, name|
	match Topics.highest_general(topics!(key)) {
		Ok(gen) if gen != topic =>
			appended!(conv, who, { at: { key, topic: gen }, name, markdown: List.join([Str.to_utf8("New topic: [${topic}]("), conv.base, Str.to_utf8("/${topic})")]), cid: [] })
		_ => Bool.True
	}

## POST .../<topic>/send: docs/ROC-CHAT.md §6.2's steps, the store's append
## the host's. A send makes its topic, so no topic need be there; the
## conversation must be the member's.
send! : Chat.Request, Route.R, Paths.ConvKey => Chat.Answer
send! = |req, route, key|
	match find!(key) {
		Err(Failed) => Chat.answered
		Ok((conv, who)) =>
		# The title before any tail, unused, as the Zig's convRoute read
		# it: a partner whose name will not read fails a send too.
			match title!(conv, key, who) {
				Err(Failed) => Chat.answered
				Ok(_) => sent!(req, route, { key, topic: route.topic }, conv, who)
			}
		Err(NotYours) => zig(route, Uncounted)
	}

## A send in `conv`, found and titled: the tail, the method, the header,
## the body, the form.
sent! : Chat.Request, Route.R, Paths.TopicAt, Chat.Conv, Who => Chat.Answer
sent! = |req, route, at, conv, who|
	if route.tail == InvalidSend {
		Chat.not_found
	} else if req.method != Post {
		Chat.not_allowed(Post)
	} else {
		# The header before the body: reading the body moves past it.
		send = if Host.header!(Str.to_utf8("x-chat-async")) == [['1']] Async else Sync
		body = Host.body!(Message)
		if body.status == Answered {
			Chat.answered
		} else {
			match Form.field(body.bytes, "markdown") {
				Malformed => Chat.malformed
				Missing => refuse("not sent: no message (the form has no markdown field)\n")
				Found(md) =>
					match Form.field(body.bytes, "cid") {
						Malformed => Chat.malformed
						Found(cid) => store!(at, conv, who, send, { markdown: Str.to_utf8(md), cid: Str.to_utf8(cid) })
						Missing => store!(at, conv, who, send, { markdown: Str.to_utf8(md), cid: [] })
					}
			}
		}
	}

refuse : Str -> Chat.Answer
refuse = |why| Chat.respond(400, [], Str.to_utf8(why))

## What the send form carried: the message's `markdown` and the sender's
## client id `cid`. Named fields because both are byte lists. It becomes
## a Draft once the message is judged and its author's name read.
Posted : { markdown : List(U8), cid : List(U8) }

## The message judged, then stored: empty or hostile is refused (one that
## is not UTF-8 text the form refused); the bookmark (a DM's) before the
## store, so one that fails stores nothing; then 204 for an async sender,
## else back to the topic.
store! : Paths.TopicAt, Chat.Conv, Who, [Async, Sync], Posted => Chat.Answer
store! = |at, conv, who, send, { markdown: md, cid }|
	if ZigText.trim(md) == [] {
		refuse("not sent: the message is empty\n")
	} else if Host.hostile!(md) != Fine {
		Chat.answered
	} else {
		match viewer!(who) {
			Err(Failed) => Chat.answered
			Ok(name) =>
				if conv.family == Dm and bookmark!(at.key, at.topic).is_err() {
					Chat.answered
				} else if !appended!(conv, who, { at, name, markdown: md, cid }) {
					Chat.answered
				} else if send == Async {
					Chat.respond(204, [], [])
				} else {
					Chat.redirect(List.concat(conv.base, "/${at.topic}".to_utf8()))
				}
		}
	}

## A message not yet stored: where it goes (`at`, its conversation and
## topic), its author's `name`, its `markdown`, and the sender's client id
## `cid`. Named fields because three are byte lists: in a row of
## arguments, a swapped pair type-checks.
Draft : { at : Paths.TopicAt, name : List(U8), markdown : List(U8), cid : List(U8) }

## **A MESSAGE STORED, THEN SENT LIVE** (angry-gopher chat_store
## `appendMessage`, its comments the spec): by the member, named `name`, to
## `topic` of `conv` (as the request spelled it), with the
## sender's client id `cid` ("" for none). Its number is the topic's count
## (`message_count!`), its id `<topic>_<n>`, its stamp the request's time; its
## block and its frame are made, then the block stored (`store_message!`:
## the append, the count cache, the search index), then the frame published
## on the topic's key, then the fan-out (`fanned!`, its steps Fanout.roc's,
## made before the store too). `who` holds a DM's accounts (the fan-out
## names the other member). False when a step before the store failed (the
## request has, with its error), and nothing was stored.
appended! : Chat.Conv, Who, Draft => Bool
appended! = |conv, who, { at: topic_at, name, markdown: md, cid }|
	# **NO MESSAGE WITHOUT AN AUTHOR** (the review of 156): the decoder
	# refuses such a block on every read, so it would go out live and be
	# gone on reload. A nameless member (a release cut short) cannot post.
	if name == [] {
		Host.fail!(NoAuthor, [])
		Bool.False
	} else {
		topic = topic_at.topic
		counted = Host.message_count!(conv, topic.to_utf8())
		match counted.status {
			Failed => Bool.False
			Counted => {
				index = counted.count
				uid = Host.me!({})
				# A count of the largest U64 has no next number: the call
				# crashes into a 500, storing nothing.
				id = "${topic}_${U64.to_str(index + 1)}".to_utf8()
				message = { id, from: name, at: Str.to_utf8(Time.rfc3339(Host.now!({}))), uid, markdown: md }
				block = Transcript.stored_form(index, message)
				rendered = Host.render!(md)
				match rendered.status {
					Failed => Bool.False
					Rendered => {
						# **THE ECHO IS MADE BEFORE THE STORE** (metal-vmm QUEUE
						# 177.1): the live publish's key and frame, so nothing
						# can fail between the store and the publish. A live
						# publish that failed after the store answered success
						# with no echo on the sender's stream, whose client then
						# sent the message again: a duplicate.
						key = Fanout.topic_key(topic_at)
						frame = Frame.message({ index, from: name, from_uid: uid, at: message.at, html: rendered.html, markdown: md, id, cid })
						# **THE FAN-OUT IS MADE BEFORE THE STORE TOO**: every
						# member's events and feed entries, so what runs after
						# the store only sends and appends. A DM's accounts are
						# the request's already (`find!`); asked here only were
						# they not, before anything is stored.
						named = if Paths.conv_kind(topic_at.key) == Dm accounts!(who) else Ok([])
						match (named, me!({}), members!(conv.members)) {
							(Ok(all), Ok(me), Ok(members)) => {
								steps = Fanout.steps({ key: topic_at.key, members, topic, index, id, from: name, at: message.at, uid: me, accounts: all }, Fanout.parts_of(md))
								if Host.store_message!(conv, topic.to_utf8(), block, index, message) {
									# **STORED IS DONE** (metal-vmm QUEUE 172): from
									# here nothing fails the send, which a client
									# would answer by sending it again. The publish
									# cannot fail; the fan-out is best-effort, each
									# failure counted and said.
									Host.publish!(key, frame)
									fanned!(topic_at, steps)
									Bool.True
								} else {
									Bool.False
								}
							}
							_ => Bool.False
						}
					}
				}
			}
		}
	}

## **THE FAN-OUT, CARRIED OUT IN ITS ORDER** (Fanout.steps): each publish
## sent; each feed's entry appended and only then its event sent; each
## surface that failed for a member counted and said (`fanout_failed!`),
## on the topic `at`. **A FAILURE NEVER STOPS
## THE STEPS AFTER IT, NOR FAILS THE SEND.**
fanned! : Paths.TopicAt, List(Fanout.Step) => {}
fanned! = |at, steps|
	match steps {
		[] => {}
		[step, .. as rest] => {
			match step {
				Publish(on, bytes) => Host.publish!(on, bytes)
				Feed(f) => {
					got = Files.append_entry!(f.path, Feeds.sep, f.entry)
					match got.status {
						Appended => Host.publish!(f.key, f.event)
						Failed => Host.fanout_failed!(f.surface, f.member, Paths.conv_key_bytes(at.key), at.topic.to_utf8(), got.fault)
					}
				}
			}
			fanned!(at, rest)
		}
	}
