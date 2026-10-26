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
## C4, `act!`); the store's writes stay Zig's, as hosted functions, until
## C8. The files and folders it reads by name (the member's own, a
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
import Paths
import Topics
import Form
import ZigText
import Feeds
import Recent
import ChatState
import Conversation

handle! : Chat.Request => Chat.Answer
handle! = |req|
	match (if req.channel Err(None) else Route.asset(req.sub)) {
		Ok(route) => Chat.zig(route, Bool.False)
		Err(None) =>
			if !Host.member!({}) {
				area = if req.channel "/channel" else "/chat"
				Chat.redirect(List.concat(Str.to_utf8("/login/full?next=${area}"), req.sub))
			} else {
				route = if req.channel Route.under_channel(req.sub) else Route.under_chat(req.sub)
				if roc_serves(route) act!(req, route) else Chat.zig(route, !Route.is_stream(route))
			}
	}

## The routes the Roc serves itself: /chat and /chat/default, the recent,
## images and code pages (not their streams), /chat/links,
## /chat/conversations, /chat/msg/<id>; and in a DM or a channel its
## landing, a new topic, and a topic's page, raw transcript, send,
## reactions, react, pin and unpin. Every other route is Zig's.
roc_serves : Route.R -> Bool
roc_serves = |r|
	match r.family {
		Default | Links | Conversations | Msg => Bool.True
		Recent | Images | Code => r.rest != Str.to_utf8("/stream")
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
		Msg => msg!(route.rest)
		Links => links!(route.rest)
		Recent => recent!(route.rest)
		Images => feed!(Images, route.rest)
		Code => feed!(Code, route.rest)
		_ => in_conversation!(req, route)
	}
}

## A DM's or a channel's, in the Zig's order: a new topic and a send look
## their conversation up themselves (a send makes its topic); the landing
## needs no topic; everything else needs the topic there (a miss is Zig's
## to answer, the same 404s), then the method, then the work.
in_conversation! : Chat.Request, Route.R => Chat.Answer
in_conversation! = |req, route|
	if route.part == New {
		new_topic!(req, route)
	} else if route.tail == Send or route.tail == InvalidSend {
		send!(req, route)
	} else if route.part == Landing {
		landing!(route)
	} else {
		match find!(route) {
			Err(NotYours) => Chat.zig(route, Bool.False)
			Ok(conv) => {
				# The title before the topics, as findTopic read them: a
				# partner whose name will not read fails every topic route.
				title = Conversation.topic_title(title!(conv), route.sid)
				if Conversation.has_topic(topics!(route.family, route.key), route.sid) {
					in_topic!(req, route, conv, title)
				} else {
					Chat.zig(route, Bool.False)
				}
			}
		}
	}

## A topic that is there, in `conv`, titled `title`: the method, then the
## work.
in_topic! : Chat.Request, Route.R, Chat.Conv, List(U8) => Chat.Answer
in_topic! = |req, route, conv, title|
	match route.tail {
		Page | Raw =>
			if req.method != Get and req.method != Head {
				Chat.not_allowed(Get)
			} else if route.tail == Page {
				page!(route, conv, title)
			} else if Host.raw!(conv, route.sid) {
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
				match read!(Paths.reactions_path(conv_dir(conv.family, conv.key), route.sid)) {
					Found(bytes) => Chat.respond(200, ndjson, bytes)
					Missing => Chat.respond(200, ndjson, [])
					Failed => Chat.answered
				}
			}
		_ =>
			if req.method != Post {
				Chat.not_allowed(Post)
			} else if route.tail == React {
				react!(conv, route.sid)
			} else if pin!(conv, route.sid, route.tail == Pin) {
				Chat.respond(204, [], [])
			} else {
				Chat.answered
			}
	}

## **THE CONVERSATION A DM OR CHANNEL ROUTE NAMES, IF IT IS THE MEMBER'S**
## (angry-gopher chat.zig `findConv`): a DM whose pair holds the member
## and whose other half is an account; a channel that lists the member.
## `NotYours` for every 404 the Zig answers (the route handed back to it,
## whose page says why).
find! : Route.R => Try(Chat.Conv, [NotYours])
find! = |route|
	match route.family {
		Dm =>
			match Conversation.dm_other(route.key, Host.me!({})) {
				Ok(other) =>
					if Host.account!(other) {
						Ok({ family: Dm, key: route.key, base: Conversation.dm_base(route.key), members: Conversation.dm_members(route.key) })
					} else {
						Err(NotYours)
					}
				Err(None) => Err(NotYours)
			}
		Channel => {
			members = channel_members!(route.key)
			if List.contains(members, Host.me!({})) {
				Ok({ family: Channel, key: route.key, base: Conversation.channel_base(route.key), members })
			} else {
				Err(NotYours)
			}
		}
		_ => Err(NotYours)
	}

## Channel `name`'s members, as its member file lists them (Paths's
## parse); none when there is no such channel. **A MALFORMED ONE FAILS THE
## REQUEST** on its own route (channelMembers's error.MalformedChannel), never
## the 404 of a channel that is not the member's; a read that failed has
## failed it already.
channel_members! : List(U8) => List(List(U8))
channel_members! = |name|
	match read!(Paths.channel_path(name)) {
		Found(bytes) =>
			match Paths.channel_members(bytes) {
				Ok(members) => members
				Err(Malformed) => {
					Host.fail!(MalformedChannel)
					[]
				}
			}
		Missing | Failed => []
	}

## **EVERY CHANNEL'S ROSTER** (channelRosters): channels/ listed
## (Paths.channel_names), then each member file read and judged in the
## listing's order (Paths.roster), a malformed one counted as it is met
## (Host.malformed_channel!), as the Zig counted it, before any read after
## it can fail.
channel_rosters! : {} => List(Paths.Roster)
channel_rosters! = |{}| rosters!(Paths.channel_names(list!(Str.to_utf8("channels"))), 0, [])

rosters! : List(List(U8)), U64, List(Paths.Roster) => List(Paths.Roster)
rosters! = |names, i, out|
	match List.get(names, i) {
		Err(_) => out
		Ok(name) =>
			match Paths.roster(name, read!(Paths.channel_path(name))) {
				Listed(r) => rosters!(names, i + 1, List.append(out, r))
				Malformed => {
					Host.malformed_channel!(name)
					rosters!(names, i + 1, out)
				}
				Gone => rosters!(names, i + 1, out)
				Failed => out
			}
	}

## **A CONVERSATION'S TOPICS** (listTopics): its sessions folder listed,
## the choice Paths.topics's.
topics! : Chat.Family, List(U8) => List(List(U8))
topics! = |family, key| Paths.topics(list!(Paths.sessions_dir(conv_dir(family, key))))

## A DM's or a channel's folder under the chat root.
conv_dir : Chat.Family, List(U8) -> List(U8)
conv_dir = |family, key|
	match family {
		Dm => Paths.dm_conv_dir(key)
		Channel => Paths.channel_conv_dir(key)
		_ => crash "conv_dir: a family with no conversation"
	}

## Host.list!'s entries. **NOTHING THERE HOLDS NOTHING** (webbox's
## store.list); a listing that failed has failed the request, and answers
## nothing too, so what follows writes nothing (the host does nothing more).
list! : List(U8) => List(Paths.Entry)
list! = |path| {
	got = Host.list!(path)
	match got.status {
		Found => got.entries
		Missing | Failed => []
	}
}

## `conv`'s title (convTitle): a DM's partner's name read, a channel's own.
title! : Chat.Conv => List(U8)
title! = |conv|
	if conv.family == Dm {
		other = Conversation.partner(conv.key, Host.me!({}))
		Conversation.dm_title(Host.name!(other), other)
	} else {
		Conversation.channel_title(conv.key)
	}

## POST .../pin and .../unpin: the member's pins in the conversation read,
## `sid` pinned or unpinned (ChatState.pinned), and the file written back or,
## emptied, removed. A read that failed stops here: the set is not empty, it
## is unknown, and writing it would drop every pin. False when a step failed.
pin! : Chat.Conv, List(U8), Bool => Bool
pin! = |conv, sid, on| {
	path = ChatState.pinned_path(Host.me!({}), conv.key)
	match read!(path) {
		Found(stored) => repin!(path, stored, sid, on)
		Missing => repin!(path, [], sid, on)
		Failed => Bool.False
	}
}

## The pinned file at `path`, read as `stored`, with `sid` pinned or
## unpinned: written back, or, emptied, removed.
repin! : List(U8), List(U8), List(U8), Bool => Bool
repin! = |path, stored, sid, on|
	match ChatState.pinned(stored, sid, on) {
		Write(bytes) => Host.write!(path, bytes)
		Remove => Host.remove!(path)
	}

## Host.read!'s answer as one tag: the file's bytes, nothing there, or a
## read that failed (the request has failed: what follows writes nothing).
read! : List(U8) => [Found(List(U8)), Missing, Failed]
read! = |path| {
	got = Host.read!(path)
	match got.status {
		Found => Found(got.bytes)
		Missing => Missing
		Failed => Failed
	}
}

## **WHERE THE MEMBER RESUMES DM `conv`: TOPIC `sid`** (setLastViewedTopic):
## the topic last viewed there first, then the DM last in, each written
## only when it changed (ChatState.changed); false when a step failed, and
## nothing after it is written. A member or topic with no name records
## nothing.
bookmark! : Chat.Conv, List(U8) => Bool
bookmark! = |conv, sid| {
	me = Host.me!({})
	if me == [] or sid == [] {
		Bool.True
	} else if write_if_changed!(ChatState.last_session_path(me, conv.key), sid) {
		write_if_changed!(ChatState.last_conv_path(me), conv.key)
	} else {
		Bool.False
	}
}

## **WRITTEN ONLY WHEN IT CHANGES** (zig-metal-unikernel 153(1)): on every
## send and view the value is usually the one already there, and a write is
## disk requests each time.
write_if_changed! : List(U8), List(U8) => Bool
write_if_changed! = |path, value|
	if ChatState.changed(read!(path), value) Host.write!(path, ChatState.bookmark_line(value)) else Bool.True

## POST .../react: the form, then the store's answer.
react! : Chat.Conv, List(U8) => Chat.Answer
react! = |conv, sid| {
	body = Host.body!(Reaction)
	if !body.ok {
		Chat.answered
	} else {
		match Reaction.form(body.bytes) {
			Malformed => Chat.malformed
			Bad(why) => Chat.respond(400, [], why)
			Reacted(r) =>
				match Host.react!(conv, sid, r.msg, r.emoji, r.on) {
					Stored => Chat.respond(204, [], [])
					NoSuchMessage => Chat.respond(400, [], Str.to_utf8("react: no such message\n"))
					Failed => Chat.answered
				}
		}
	}
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
		viewer = Host.viewer!({})
		src = Chrome.src_in(Host.srcs!({}))
		if Host.links!({}) {
			(before, after) = Pages.links_around(src, viewer)
			Chat.held_html(before, after)
		} else {
			Chat.respond(200, html, Pages.links(src, viewer, []))
		}
	}

## /chat/recent by any method, as the Zig had it: what the host gathered,
## named, dated, excerpted and ordered here; nothing below it but its stream.
recent! : List(U8) => Chat.Answer
recent! = |rest|
	if rest != [] {
		Chat.not_found
	} else {
		viewer = Host.viewer!({})
		rows = Recent.rows(Host.recent!({}))
		me = Host.me!({})
		Chat.respond(200, html, Pages.recent(Chrome.src_in(Host.srcs!({})), viewer, Recent.json(me, rows)))
	}

## /chat/images (the newest 20 entries) or /chat/code (every one), by any
## method, as the Zig had them; nothing below them but their streams.
feed! : [Images, Code], List(U8) => Chat.Answer
feed! = |which, rest|
	if rest != [] {
		Chat.not_found
	} else {
		viewer = Host.viewer!({})
		# A feed that failed is the request's failure; the page made of
		# nothing is not sent.
		file = match read!(Feeds.path(Host.me!({}), which)) {
			Found(bytes) => bytes
			Missing | Failed => []
		}
		src = Chrome.src_in(Host.srcs!({}))
		page = match which {
			Images => Pages.images(src, viewer, Feeds.images_json(Feeds.images(file), 20))
			Code => Pages.code(src, viewer, Feeds.code_json(Feeds.code(file)))
		}
		Chat.respond(200, html, page)
	}

## A conversation's landing: its first topic, or, with none, the page that
## offers one, the title and viewer read in the Zig's order.
landing! : Route.R => Chat.Answer
landing! = |route|
	match find!(route) {
		Err(NotYours) => Chat.zig(route, Bool.False)
		Ok(conv) => {
			first = Paths.first_of(topics!(route.family, route.key))
			if first != [] {
				Chat.redirect(List.join([conv.base, [47], first]))
			} else {
				title = title!(conv)
				viewer = Host.viewer!({})
				Chat.respond(200, html, Pages.no_topics(Chrome.src_in(Host.srcs!({})), viewer, conv.base, title))
			}
		}
	}

## A topic's page, titled `title`: a DM's topic recorded as where the
## member resumes it first (a bookmark that fails serves no page), then
## what the host read.
page! : Route.R, Chat.Conv, List(U8) => Chat.Answer
page! = |route, conv, title|
	if conv.family == Dm and !bookmark!(conv, route.sid) {
		Chat.answered
	} else {
		match Host.page!(conv, route.sid) {
			[viewer, image_max, video_max, accept, search_min, .. as fields] => {
				sb = Pages.decode_sidebar(fields)
				limits = { image_max: Pages.number(image_max), video_max: Pages.number(video_max), accept, search_min: Pages.number(search_min) }
				view = { key: route.key, base: sb.base, sid: route.sid, title, uid: sb.uid, viewer, sidebar_json: Pages.sidebar_json(sb) }
				Chat.respond(200, html, Pages.conversation(Chrome.src_in(Host.srcs!({})), limits, view))
			}
			_ => Chat.answered
		}
	}

json : List(U8)
json = Str.to_utf8("application/json; charset=utf-8")

## /chat: the member's last DM, at the topic they resume, or its own page
## when it has no topic yet; with none, the empty /chat.
resume! : {} => Chat.Answer
resume! = |{}| {
	me = Host.me!({})
	conv = ChatState.bookmark(read!(ChatState.last_conv_path(me)))
	if conv == [] or !Paths.participant(conv, me) {
		Chat.respond(200, html, Pages.no_conversations(Chrome.src_in(Host.srcs!({})), Host.viewer!({})))
	} else {
		topics = topics!(Dm, conv)
		if Paths.first_of(topics) == [] {
			Chat.redirect(List.concat(Str.to_utf8("/chat/c/"), conv))
		} else {
			Chat.redirect(List.join([Str.to_utf8("/chat/c/"), conv, [47], resume_at!(conv, topics)]))
		}
	}
}

## Where the member resumes DM `conv`, whose topics are `topics`: the choice
## ChatState's, the last-viewed topic and the clock the host's.
resume_at! : List(U8), List(List(U8)) => List(U8)
resume_at! = |conv, topics| {
	last = ChatState.bookmark(read!(ChatState.last_session_path(Host.me!({}), conv)))
	ChatState.resume_topic(topics, last, Host.now!({}))
}

## /chat/conversations: a DM with every other member, where the member
## resumes it, and its topics.
conversations! : {} => Chat.Answer
conversations! = |{}| {
	me = Host.me!({})
	Chat.respond(200, json, Topics.conversations_json(me, entries!(me, Host.members!({}), 0, [])))
}

entries! : List(U8), List(List(U8)), U64, List(Topics.Entry) => List(Topics.Entry)
entries! = |me, members, i, acc|
	match (List.get(members, i), List.get(members, i + 1)) {
		(Ok(id), Ok(name)) =>
			if id == me {
				entries!(me, members, i + 2, acc)
			} else {
				conv = Paths.pair_key(me, id)
				sessions = topics!(Dm, conv)
				default = resume_at!(conv, sessions)
				entries!(me, members, i + 2, List.append(acc, { conv, id, name, default, sessions }))
			}
		_ => acc
	}

## /chat/msg/<id>: the topic a message id names, in the member's DMs, then
## their channels; a 302 there.
msg! : List(U8) => Chat.Answer
msg! = |id|
	if !Paths.valid_msg_ref_id(id) {
		Chat.not_found
	} else {
		sid = match Paths.cut_last(id, 95) {
			Ok((before, _)) => before
			Err(None) => []
		}
		me = Host.me!({})
		at = |base, key| List.join([Str.to_utf8(base), key, [47], sid, Str.to_utf8("#msg-"), id])
		match find_dm!(me, Host.members!({}), sid, 0) {
			Ok(conv) => Chat.found(at("/chat/c/", conv))
			Err(None) =>
				match find_channel!(Paths.member_channels(channel_rosters!({}), me), sid, 0) {
					Ok(name) => Chat.found(at("/channel/", name))
					Err(None) => Chat.not_found
				}
		}
	}

find_dm! : List(U8), List(List(U8)), List(U8), U64 => Try(List(U8), [None])
find_dm! = |me, members, sid, i|
	match List.get(members, i) {
		Ok(id) =>
			if id == me {
				find_dm!(me, members, sid, i + 2)
			} else {
				conv = Paths.pair_key(me, id)
				if List.contains(topics!(Dm, conv), sid) Ok(conv) else find_dm!(me, members, sid, i + 2)
			}
		Err(_) => Err(None)
	}

find_channel! : List(List(U8)), List(U8), U64 => Try(List(U8), [None])
find_channel! = |names, sid, i|
	match List.get(names, i) {
		Ok(name) => if List.contains(topics!(Channel, name), sid) Ok(name) else find_channel!(names, sid, i + 1)
		Err(_) => Err(None)
	}

## POST <base>/new: a topic made with a first "hi", a DM's announced in its
## highest general<N>; the conversation and topic as JSON.
new_topic! : Chat.Request, Route.R => Chat.Answer
new_topic! = |req, route|
	match find!(route) {
		Ok(conv) =>
			if req.method != Post {
				Chat.not_allowed(Post)
			} else {
				body = Host.body!(Message)
				if !body.ok {
					Chat.answered
				} else {
					match Form.field(body.bytes, Str.to_utf8("topic")) {
						Malformed => Chat.malformed
						Found(raw) => make!(route, conv, ZigText.trim(raw))
						Missing => make!(route, conv, [])
					}
				}
			}
		Err(NotYours) => Chat.zig(route, Bool.False)
	}

make! : Route.R, Chat.Conv, List(U8) => Chat.Answer
make! = |route, conv, topic|
	if !Paths.valid_topic_id(topic) {
		Chat.respond(400, [], Str.to_utf8("Topic must be letters, digits, and hyphens only — no spaces, underscores, or punctuation.\n"))
	} else if Topics.same_name(topic, Str.to_utf8("new")) {
		Chat.respond(400, [], Str.to_utf8("\"new\" is reserved — pick another topic name.\n"))
	} else if Conversation.has_topic(topics!(route.family, route.key), topic) {
		Chat.respond(409, [], Str.to_utf8("That topic already exists.\n"))
	} else {
		name = Host.viewer!({})
		dm = conv.family == Dm
		# The bookmark first, as a send's: one that fails makes no topic.
		if dm and !bookmark!(conv, topic) {
			Chat.answered
		} else if !Host.append!(conv, topic, name, Str.to_utf8("hi"), []) {
			Chat.answered
		} else if dm and !announce!(route, conv, topic, name) {
			Chat.answered
		} else {
			Chat.respond(200, json, Topics.made_json(route.key, topic))
		}
	}

## A DM's new topic, said where the partner already watches: its highest
## general<N>, unless that is the topic made.
announce! : Route.R, Chat.Conv, List(U8), List(U8) => Bool
announce! = |route, conv, topic, name|
	match Topics.highest_general(topics!(route.family, route.key)) {
		Ok(gen) if gen != topic =>
			Host.append!(conv, gen, name, List.join([Str.to_utf8("New topic: ["), topic, Str.to_utf8("]("), conv.base, [47], topic, Str.to_utf8(")")]), [])
		_ => Bool.True
	}

## POST .../<sid>/send: docs/ROC-CHAT.md §6.2's steps, the store's append
## the host's. A send makes its topic, so no topic need be there; the
## conversation must be the member's.
send! : Chat.Request, Route.R => Chat.Answer
send! = |req, route|
	match find!(route) {
		Ok(conv) => {
			# The title is read, unused, as the Zig's convRoute read it before
			# any tail: a partner whose name will not read fails a send too.
			_ = title!(conv)
			if route.tail == InvalidSend {
				Chat.not_found
			} else if req.method != Post {
				Chat.not_allowed(Post)
			} else {
				# The header before the body: reading the body moves past it.
				is_async = Host.header!(Str.to_utf8("x-chat-async")) == [[49]]
				body = Host.body!(Message)
				if !body.ok {
					Chat.answered
				} else {
					match Form.field(body.bytes, Str.to_utf8("markdown")) {
						Malformed => Chat.malformed
						Missing => refuse("not sent: no message (the form has no markdown field)\n")
						Found(md) =>
							match Form.field(body.bytes, Str.to_utf8("cid")) {
								Malformed => Chat.malformed
								Found(cid) => store!(route, conv, is_async, md, cid)
								Missing => store!(route, conv, is_async, md, [])
							}
					}
				}
			}
		}
		Err(NotYours) => Chat.zig(route, Bool.False)
	}

refuse : Str -> Chat.Answer
refuse = |why| Chat.respond(400, [], Str.to_utf8(why))

## The message judged, then stored: empty, not UTF-8 text, or hostile is
## refused; the bookmark (a DM's) before the store, so one that fails
## stores nothing; then 204 for an async sender, else back to the topic.
store! : Route.R, Chat.Conv, Bool, List(U8), List(U8) => Chat.Answer
store! = |route, conv, is_async, md, cid|
	if ZigText.trim(md) == [] {
		refuse("not sent: the message is empty\n")
	} else if Str.from_utf8(md).is_err() {
		refuse("not sent: the message is not UTF-8 text\n")
	} else if Host.hostile!(md) != Fine {
		Chat.answered
	} else {
		name = Host.viewer!({})
		if conv.family == Dm and !bookmark!(conv, route.sid) {
			Chat.answered
		} else if !Host.append!(conv, route.sid, name, md, cid) {
			Chat.answered
		} else if is_async {
			Chat.respond(204, [], [])
		} else {
			Chat.redirect(List.join([conv.base, [47], route.sid]))
		}
	}
