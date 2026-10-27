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
## `fanout_failed!` over the host's `message_parts!`. The files and folders it reads by name (the member's own, a
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
import Accounts
import Frame
import Time
import Transcript
import Fanout

handle! : Chat.Request => Chat.Answer
handle! = |req|
	match (if req.area == Channel Err(None) else Route.asset(req.sub)) {
		Ok(route) => Chat.zig(route, Uncounted)
		Err(None) =>
			if !Host.member!({}) {
				area = if req.area == Channel "/channel" else "/chat"
				Chat.redirect(List.concat(Str.to_utf8("/login/full?next=${area}"), req.sub))
			} else {
				route = if req.area == Channel Route.under_channel(req.sub) else Route.under_chat(req.sub)
				if roc_serves(route) act!(req, route) else Chat.zig(route, if Route.is_stream(route) Uncounted else Counted)
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
			Err(NotYours) => Chat.zig(route, Uncounted)
			Err(Failed) => Chat.answered
			Ok((conv, who)) =>
			# The title before the topics, as findTopic read them: a
			# partner whose name will not read fails every topic route.
				match title!(conv, who) {
					Err(Failed) => Chat.answered
					Ok(t) => {
						topics = topics!(route.family, route.key)
						if Conversation.has_topic(topics, route.sid) {
							in_topic!(req, route, { conv, who, title: Conversation.topic_title(t, route.sid), topics })
						} else {
							Chat.zig(route, Uncounted)
						}
					}
				}
		}
	}

## A topic found: its conversation, the accounts as far as they were asked,
## its title, and the conversation's topics as they were listed to find it.
AtTopic : { conv : Chat.Conv, who : Who, title : List(U8), topics : List(List(U8)) }

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
				react!(conv, who, route.sid)
			} else if pin!(conv, route.sid, if route.tail == Pin Pinned else Unpinned) {
				Chat.respond(204, [], [])
			} else {
				Chat.answered
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
find! : Route.R => Try((Chat.Conv, Who), [NotYours, Failed])
find! = |route|
	match route.family {
		Dm =>
			match Conversation.dm_other(route.key, Host.me!({})) {
				Ok(other) =>
					match accounts!(Unasked) {
						Ok(all) =>
							if Accounts.exists(all, other) {
								Ok(({ family: Dm, key: route.key, base: Conversation.dm_base(route.key), members: Conversation.dm_members(route.key) }, Known(all)))
							} else {
								Err(NotYours)
							}
						Err(Failed) => Err(Failed)
					}
				Err(None) => Err(NotYours)
			}
		Channel => {
			members = channel_members!(route.key)
			if List.contains(members, Host.me!({})) {
				Ok(({ family: Channel, key: route.key, base: Conversation.channel_base(route.key), members }, Unasked))
			} else {
				Err(NotYours)
			}
		}
		_ => Err(NotYours)
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
				Found => Ok(got.accounts)
				Failed => Err(Failed)
			}
		}
	}

## The member's name (getUserName of their own id), from the accounts.
## `Failed` when it would not read (the request has failed with its error).
viewer! : Who => Try(List(U8), [Failed])
viewer! = |who|
	match accounts!(who) {
		Ok(all) => named!(Accounts.name(all, Host.me!({})))
		Err(Failed) => Err(Failed)
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
		KindUnreadable(id) => Host.fail!(KindUnreadable, id)
		NameUnreadable(id) => Host.fail!(NameUnreadable, id)
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
					Host.fail!(MalformedChannel, name)
					[]
				}
			}
		Missing | Failed => []
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
	got = Host.list!(Str.to_utf8("channels"))
	match got.status {
		Found => rosters!(Paths.channel_names(got.entries), 0, [])
		Missing => Ok([])
		Failed => Err(Failed)
	}
}

rosters! : List(List(U8)), U64, List(Paths.Roster) => Try(List(Paths.Roster), [Failed])
rosters! = |names, i, out|
	match List.get(names, i) {
		Err(_) => Ok(out)
		Ok(name) =>
			match Paths.roster(name, read!(Paths.channel_path(name))) {
				Listed(r) => rosters!(names, i + 1, List.append(out, r))
				Malformed => {
					Host.malformed_channel!(name)
					rosters!(names, i + 1, out)
				}
				Gone => rosters!(names, i + 1, out)
				Failed => Err(Failed)
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

## `conv`'s title (convTitle): a DM's partner's name (its accounts known
## since find!), a channel's own. `Failed` when the partner's name would not
## read (the request has failed with its error).
title! : Chat.Conv, Who => Try(List(U8), [Failed])
title! = |conv, who|
	if conv.family == Dm {
		match accounts!(who) {
			Ok(all) => {
				other = Conversation.partner(conv.key, Host.me!({}))
				match named!(Accounts.name(all, other)) {
					Ok(name) => Ok(Conversation.dm_title(name, other))
					Err(Failed) => Err(Failed)
				}
			}
			Err(Failed) => Err(Failed)
		}
	} else {
		Ok(Conversation.channel_title(conv.key))
	}

## POST .../pin and .../unpin: the member's pins in the conversation read,
## `sid` pinned or unpinned (ChatState.pinned), and the file written back or,
## emptied, removed. A read that failed stops here: the set is not empty, it
## is unknown, and writing it would drop every pin. False when a step failed.
pin! : Chat.Conv, List(U8), ChatState.Pin => Bool
pin! = |conv, sid, pin| {
	path = ChatState.pinned_path(Host.me!({}), conv.key)
	match read!(path) {
		Found(stored) => repin!(path, stored, sid, pin)
		Missing => repin!(path, [], sid, pin)
		Failed => Bool.False
	}
}

## The pinned file at `path`, read as `stored`, with `sid` pinned or
## unpinned: written back, or, emptied, removed.
repin! : List(U8), List(U8), List(U8), ChatState.Pin => Bool
repin! = |path, stored, sid, pin|
	match ChatState.pinned(stored, sid, pin) {
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

## POST .../react: the form, then the reaction stored and sent live.
react! : Chat.Conv, Who, List(U8) => Chat.Answer
react! = |conv, who, sid| {
	body = Host.body!(Reaction)
	if body.status == Answered {
		Chat.answered
	} else {
		match Reaction.form(body.bytes) {
			Malformed => Chat.malformed
			Bad(why) => Chat.respond(400, [], why)
			Reacted(r) =>
				match reacted!(conv, who, sid, r) {
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
reacted! : Chat.Conv, Who, List(U8), { msg : U64, emoji : List(U8), change : Reaction.Change } => [Stored, NoSuchMessage, Failed]
reacted! = |conv, who, sid, r|
	match viewer!(who) {
		Err(Failed) => Failed
		Ok(name) => {
			counted = Host.message_count!(conv, sid)
			match counted.status {
				Failed => Failed
				Counted =>
				# Message numbers start at 1 (the N of MSG_<sid>_N).
					if r.msg == 0 or r.msg > counted.count {
						NoSuchMessage
					} else {
						at = Str.to_utf8(Time.rfc3339(Host.now!({})))
						line = Reaction.line(r.msg, Host.me!({}), name, r.emoji, r.change, at)
						# **THE ECHO IS MADE BEFORE THE STORE** (metal-vmm QUEUE
						# 177.1), as a message's: its key and frame, so nothing
						# can fail between the append and the publish.
						key = List.join([conv.key, ['/'], sid])
						frame = Frame.reaction(line)
						if Host.append_line!(Paths.reactions_path(conv_dir(conv.family, conv.key), sid), line) {
							# **STORED IS DONE**: the live publish cannot fail.
							Host.publish!(key, frame)
							Stored
						} else {
							Failed
						}
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
		match viewer!(Unasked) {
			Err(Failed) => Chat.answered
			Ok(viewer) => {
				src = Chrome.src_in(Host.srcs!({}))
				if Host.links!({}) {
					(before, after) = Pages.links_around(src, viewer)
					Chat.held_html(before, after)
				} else {
					Chat.respond(200, html, Pages.links(src, viewer, []))
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
		match viewer!(Unasked) {
			Err(Failed) => Chat.answered
			Ok(viewer) => {
				rows = Recent.rows(Host.recent!({}))
				me = Host.me!({})
				Chat.respond(200, html, Pages.recent(Chrome.src_in(Host.srcs!({})), { viewer, json: Recent.json(me, rows) }))
			}
		}
	}

## /chat/images (the newest 20 entries) or /chat/code (every one), by any
## method, as the Zig had them; nothing below them but their streams.
feed! : [Images, Code], List(U8) => Chat.Answer
feed! = |which, rest|
	if rest != [] {
		Chat.not_found
	} else {
		match viewer!(Unasked) {
			Err(Failed) => Chat.answered
			Ok(viewer) => {
				# A feed that failed is the request's failure; the page made
				# of nothing is not sent.
				file = match read!(Feeds.path(Host.me!({}), which)) {
					Found(bytes) => bytes
					Missing | Failed => []
				}
				src = Chrome.src_in(Host.srcs!({}))
				page = match which {
					Images => Pages.images(src, { viewer, json: Feeds.images_json(Feeds.images(file), 20) })
					Code => Pages.code(src, { viewer, json: Feeds.code_json(Feeds.code(file)) })
				}
				Chat.respond(200, html, page)
			}
		}
	}

## A conversation's landing: its first topic, or, with none, the page that
## offers one, the title and viewer read in the Zig's order.
landing! : Route.R => Chat.Answer
landing! = |route|
	match find!(route) {
		Err(NotYours) => Chat.zig(route, Uncounted)
		Err(Failed) => Chat.answered
		Ok((conv, who)) => {
			first = Paths.first_of(topics!(route.family, route.key))
			if first != [] {
				Chat.redirect(List.join([conv.base, ['/'], first]))
			} else {
				match title!(conv, who) {
					Err(Failed) => Chat.answered
					Ok(title) =>
						match viewer!(who) {
							Ok(viewer) => Chat.respond(200, html, Pages.no_topics(Chrome.src_in(Host.srcs!({})), { viewer, base: conv.base, title }))
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
	if at.conv.family == Dm and !bookmark!(at.conv, route.sid) {
		Chat.answered
	} else {
		match sidebar!(route.sid, at) {
			Err(Failed) => Chat.answered
			Ok((viewer, sb)) => {
				view = { key: route.key, base: sb.base, sid: route.sid, title: at.title, uid: sb.uid, viewer, sidebar_json: Pages.sidebar_json(sb) }
				Chat.respond(200, html, Pages.conversation(Chrome.src_in(Host.srcs!({})), Host.limits!({}), view))
			}
		}
	}

## **THE VIEWER AND THE SIDEBAR, READ IN THE ZIG'S ORDER** (conversationPage's
## getUserName, then sidebarOf): the viewer's name; every other authorized
## member (listAuthorized: an account it reads that will not read fails
## it), each online or not at the request's time (Host.online!, one asking
## for all); the member's channels (listUserChannels: a malformed one
## skipped and counted); their pins in this conversation (pinnedTopics,
## sorted); its topics as they were listed to find topic `sid`. `Failed`
## when a read failed (the request has, with its error): **A PINS FILE
## THAT WILL NOT READ IS NEVER NO PINS.**
sidebar! : List(U8), AtTopic => Try((List(U8), Pages.Sidebar), [Failed])
sidebar! = |sid, at| {
	me = Host.me!({})
	match accounts!(at.who) {
		Err(Failed) => Err(Failed)
		Ok(all) =>
			match named!(Accounts.name(all, me)) {
				Err(Failed) => Err(Failed)
				Ok(viewer) =>
					match named!(Accounts.authorized(all)) {
						Err(Failed) => Err(Failed)
						Ok(roster) => {
							others = List.drop_if(roster, |u| u.id == me)
							flags = Host.online!(List.map(others, |u| u.id))
							match channel_rosters!({}) {
								Err(Failed) => Err(Failed)
								Ok(rosters) =>
									match read!(ChatState.pinned_path(me, at.conv.key)) {
										Failed => Err(Failed)
										Found(stored) => Ok((viewer, sidebar_of(me, sid, at, with_online(others, flags), Paths.member_channels(rosters, me), ChatState.pins(stored))))
										Missing => Ok((viewer, sidebar_of(me, sid, at, with_online(others, flags), Paths.member_channels(rosters, me), [])))
									}
							}
						}
					}
			}
	}
}

## The other members, each beside its own flag (Host.online! answers one
## per id, in their order).
with_online : List({ id : List(U8), name : List(U8) }), List([Offline, Online]) -> List({ id : List(U8), name : List(U8), presence : [Online, Offline] })
with_online = |others, flags|
	List.map_with_index(others, |u, i|
		{ id: u.id, name: u.name, presence: if List.get(flags, i) == Ok(Online) Online else Offline })

sidebar_of : List(U8), List(U8), AtTopic, List({ id : List(U8), name : List(U8), presence : [Online, Offline] }), List(List(U8)), List(List(U8)) -> Pages.Sidebar
sidebar_of = |me, sid, at, others, channels, pins|
	{ uid: me, kind: if at.conv.family == Dm Dm else Channel, key: at.conv.key, base: at.conv.base, sid, others, channels, pins, topics: at.topics }

json : List(U8)
json = Str.to_utf8("application/json; charset=utf-8")

## /chat: the member's last DM, at the topic they resume, or its own page
## when it has no topic yet; with none, the empty /chat.
resume! : {} => Chat.Answer
resume! = |{}| {
	me = Host.me!({})
	conv = ChatState.bookmark(read!(ChatState.last_conv_path(me)))
	if conv == [] or !Paths.participant(conv, me) {
		match viewer!(Unasked) {
			Ok(viewer) => Chat.respond(200, html, Pages.no_conversations(Chrome.src_in(Host.srcs!({})), viewer))
			Err(Failed) => Chat.answered
		}
	} else {
		topics = topics!(Dm, conv)
		if Paths.first_of(topics) == [] {
			Chat.redirect(List.concat(Str.to_utf8("/chat/c/"), conv))
		} else {
			Chat.redirect(List.join([Str.to_utf8("/chat/c/"), conv, ['/'], resume_at!(conv, topics)]))
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
conversations! = |{}|
	match roster!({}) {
		Ok(members) => {
			me = Host.me!({})
			Chat.respond(200, json, Topics.conversations_json(me, entries!(me, members, 0, [])))
		}
		Err(Failed) => Chat.answered
	}

## The authorized roster (listAuthorized), from the accounts. `Failed` when
## the accounts could not be listed, or one the roster reads would not read
## (the request has failed with its error).
roster! : {} => Try(List({ id : List(U8), name : List(U8) }), [Failed])
roster! = |{}|
	match accounts!(Unasked) {
		Ok(all) => named!(Accounts.authorized(all))
		Err(Failed) => Err(Failed)
	}

entries! : List(U8), List({ id : List(U8), name : List(U8) }), U64, List(Topics.Entry) => List(Topics.Entry)
entries! = |me, members, i, acc|
	match List.get(members, i) {
		Ok({ id, name }) =>
			if id == me {
				entries!(me, members, i + 1, acc)
			} else {
				conv = Paths.pair_key(me, id)
				sessions = topics!(Dm, conv)
				default = resume_at!(conv, sessions)
				entries!(me, members, i + 1, List.append(acc, { conv, id, name, default, sessions }))
			}
		Err(_) => acc
	}

## /chat/msg/<id>: the topic a message id names, in the member's DMs, then
## their channels; a 302 there.
msg! : List(U8) => Chat.Answer
msg! = |id|
	if !Paths.valid_msg_ref_id(id) {
		Chat.not_found
	} else {
		sid = match Paths.cut_last(id, '_') {
			Ok((before, _)) => before
			Err(None) => []
		}
		me = Host.me!({})
		at = |base, key| List.join([Str.to_utf8(base), key, ['/'], sid, Str.to_utf8("#msg-"), id])
		match roster!({}) {
			Err(Failed) => Chat.answered
			Ok(members) =>
				match find_dm!(me, members, sid, 0) {
					Ok(conv) => Chat.found(at("/chat/c/", conv))
					Err(None) =>
						match channel_rosters!({}) {
							Err(Failed) => Chat.answered
							Ok(rosters) =>
								match find_channel!(Paths.member_channels(rosters, me), sid, 0) {
									Ok(name) => Chat.found(at("/channel/", name))
									Err(None) => Chat.not_found
								}
						}
				}
		}
	}

find_dm! : List(U8), List({ id : List(U8), name : List(U8) }), List(U8), U64 => Try(List(U8), [None])
find_dm! = |me, members, sid, i|
	match List.get(members, i) {
		Ok({ id, name: _ }) =>
			if id == me {
				find_dm!(me, members, sid, i + 1)
			} else {
				conv = Paths.pair_key(me, id)
				if List.contains(topics!(Dm, conv), sid) Ok(conv) else find_dm!(me, members, sid, i + 1)
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
		Ok((conv, who)) =>
			if req.method != Post {
				Chat.not_allowed(Post)
			} else {
				body = Host.body!(Message)
				if body.status == Answered {
					Chat.answered
				} else {
					match Form.field(body.bytes, Str.to_utf8("topic")) {
						Malformed => Chat.malformed
						Found(raw) => make!(route, conv, who, ZigText.trim(raw))
						Missing => make!(route, conv, who, [])
					}
				}
			}
		Err(NotYours) => Chat.zig(route, Uncounted)
		Err(Failed) => Chat.answered
	}

make! : Route.R, Chat.Conv, Who, List(U8) => Chat.Answer
make! = |route, conv, who, topic|
	if !Paths.valid_topic_id(topic) {
		Chat.respond(400, [], Str.to_utf8("Topic must be letters, digits, and hyphens only — no spaces, underscores, or punctuation.\n"))
	} else if Topics.same_name(topic, Str.to_utf8("new")) {
		Chat.respond(400, [], Str.to_utf8("\"new\" is reserved — pick another topic name.\n"))
	} else if Conversation.has_topic(topics!(route.family, route.key), topic) {
		Chat.respond(409, [], Str.to_utf8("That topic already exists.\n"))
	} else {
		match viewer!(who) {
			Err(Failed) => Chat.answered
			Ok(name) => {
				dm = conv.family == Dm
				# The bookmark first, as a send's: one that fails makes no topic.
				if dm and !bookmark!(conv, topic) {
					Chat.answered
				} else if !appended!(conv, who, { sid: topic, name, markdown: Str.to_utf8("hi"), cid: [] }) {
					Chat.answered
				} else if dm and !announce!(route, conv, who, topic, name) {
					Chat.answered
				} else {
					Chat.respond(200, json, Topics.made_json(route.key, topic))
				}
			}
		}
	}

## A DM's new topic, said where the partner already watches: its highest
## general<N>, unless that is the topic made.
announce! : Route.R, Chat.Conv, Who, List(U8), List(U8) => Bool
announce! = |route, conv, who, topic, name|
	match Topics.highest_general(topics!(route.family, route.key)) {
		Ok(gen) if gen != topic =>
			appended!(conv, who, { sid: gen, name, markdown: List.join([Str.to_utf8("New topic: ["), topic, Str.to_utf8("]("), conv.base, ['/'], topic, Str.to_utf8(")")]), cid: [] })
		_ => Bool.True
	}

## POST .../<sid>/send: docs/ROC-CHAT.md §6.2's steps, the store's append
## the host's. A send makes its topic, so no topic need be there; the
## conversation must be the member's.
send! : Chat.Request, Route.R => Chat.Answer
send! = |req, route|
	match find!(route) {
		Err(Failed) => Chat.answered
		Ok((conv, who)) =>
		# The title before any tail, unused, as the Zig's convRoute read
		# it: a partner whose name will not read fails a send too.
			match title!(conv, who) {
				Err(Failed) => Chat.answered
				Ok(_) => sent!(req, route, conv, who)
			}
		Err(NotYours) => Chat.zig(route, Uncounted)
	}

## A send in `conv`, found and titled: the tail, the method, the header,
## the body, the form.
sent! : Chat.Request, Route.R, Chat.Conv, Who => Chat.Answer
sent! = |req, route, conv, who|
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
			match Form.field(body.bytes, Str.to_utf8("markdown")) {
				Malformed => Chat.malformed
				Missing => refuse("not sent: no message (the form has no markdown field)\n")
				Found(md) =>
					match Form.field(body.bytes, Str.to_utf8("cid")) {
						Malformed => Chat.malformed
						Found(cid) => store!(route, conv, who, send, md, cid)
						Missing => store!(route, conv, who, send, md, [])
					}
			}
		}
	}

refuse : Str -> Chat.Answer
refuse = |why| Chat.respond(400, [], Str.to_utf8(why))

## The message judged, then stored: empty, not UTF-8 text, or hostile is
## refused; the bookmark (a DM's) before the store, so one that fails
## stores nothing; then 204 for an async sender, else back to the topic.
store! : Route.R, Chat.Conv, Who, [Async, Sync], List(U8), List(U8) => Chat.Answer
store! = |route, conv, who, send, md, cid|
	if ZigText.trim(md) == [] {
		refuse("not sent: the message is empty\n")
	} else if Str.from_utf8(md).is_err() {
		refuse("not sent: the message is not UTF-8 text\n")
	} else if Host.hostile!(md) != Fine {
		Chat.answered
	} else {
		match viewer!(who) {
			Err(Failed) => Chat.answered
			Ok(name) =>
				if conv.family == Dm and !bookmark!(conv, route.sid) {
					Chat.answered
				} else if !appended!(conv, who, { sid: route.sid, name, markdown: md, cid }) {
					Chat.answered
				} else if send == Async {
					Chat.respond(204, [], [])
				} else {
					Chat.redirect(List.join([conv.base, ['/'], route.sid]))
				}
		}
	}

## A message not yet stored: its topic's `sid`, its author's `name`, its
## `markdown`, and the sender's client id `cid`. Named fields because all
## four are byte lists: in a row of arguments, a swapped pair type-checks.
Draft : { sid : List(U8), name : List(U8), markdown : List(U8), cid : List(U8) }

## **A MESSAGE STORED, THEN SENT LIVE** (angry-gopher chat_store
## `appendMessage`, its comments the spec): by the member, named `name`, to
## topic `sid` of `conv` (the sid as the request spelled it), with the
## sender's client id `cid` ("" for none). Its number is the topic's count
## (`message_count!`), its id `<sid>_<n>`, its stamp the request's time; its
## block and its frame are made, then the block stored (`store_message!`:
## the append, the count cache, the search index), then the frame published
## on the topic's key, then the fan-out (`fanned!`, its steps Fanout.roc's,
## made before the store too). `who` holds a DM's accounts (the fan-out
## names the other member). False when a step before the store failed (the
## request has, with its error), and nothing was stored.
appended! : Chat.Conv, Who, Draft => Bool
appended! = |conv, who, { sid, name, markdown: md, cid }|
	# **NO MESSAGE WITHOUT AN AUTHOR** (the review of 156): the decoder
	# refuses such a block on every read, so it would go out live and be
	# gone on reload. A nameless member (a release cut short) cannot post.
	if name == [] {
		Host.fail!(NoAuthor, [])
		Bool.False
	} else {
		counted = Host.message_count!(conv, sid)
		match counted.status {
			Failed => Bool.False
			Counted => {
				index = counted.count
				uid = Host.me!({})
				# A count of the largest U64 has no next number: the call
				# crashes into a 500, storing nothing.
				id = List.join([sid, ['_'], Str.to_utf8(U64.to_str(index + 1))])
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
						key = List.join([conv.key, ['/'], sid])
						frame = Frame.message({ index, from: name, from_uid: uid, at: message.at, html: rendered.html, markdown: md, id, cid })
						# **THE FAN-OUT IS MADE BEFORE THE STORE TOO**: every
						# member's events and feed entries, so what runs after
						# the store only sends and appends. A DM's accounts are
						# the request's already (`find!`); asked here only were
						# they not, before anything is stored.
						kind = if conv.family == Dm Dm else Channel
						named = if kind == Dm accounts!(who) else Ok([])
						match named {
							Err(Failed) => Bool.False
							Ok(all) => {
								steps = Fanout.steps({ kind, key: conv.key, members: conv.members, sid, index, id, from: name, at: message.at, uid, accounts: all }, parts!(md))
								if Host.store_message!(conv, sid, block, index, message) {
									# **STORED IS DONE** (metal-vmm QUEUE 172): from
									# here nothing fails the send, which a client
									# would answer by sending it again. The publish
									# cannot fail; the fan-out is best-effort, each
									# failure counted and said.
									Host.publish!(key, frame)
									fanned!(conv.key, sid, steps)
									Bool.True
								} else {
									Bool.False
								}
							}
						}
					}
				}
			}
		}
	}

## The message's parts as the host found them (Host.message_parts!), each
## made or failed on its own.
parts! : List(U8) => Fanout.Parts
parts! = |md| {
	got = Host.message_parts!(md)
	{
		excerpt: match got.excerpt.status {
			Made => Made(got.excerpt.bytes)
			Failed => Failed(got.excerpt.fault)
		},
		images: match got.images.status {
			Made => Made(got.images.tags)
			Failed => Failed(got.images.fault)
		},
		code: match got.code.status {
			Made => Made(got.code.blocks)
			Failed => Failed(got.code.fault)
		},
	}
}

## **THE FAN-OUT, CARRIED OUT IN ITS ORDER** (Fanout.steps): each publish
## sent; each feed's entry appended and only then its event sent; each
## surface that failed for a member counted and said (`fanout_failed!`),
## on topic `sid` of the conversation keyed `key`. **A FAILURE NEVER STOPS
## THE STEPS AFTER IT, NOR FAILS THE SEND.**
fanned! : List(U8), List(U8), List(Fanout.Step) => {}
fanned! = |key, sid, steps|
	match steps {
		[] => {}
		[step, .. as rest] => {
			match step {
				Publish(on, bytes) => Host.publish!(on, bytes)
				Feed(f) => {
					got = Host.append_entry!(f.path, Feeds.sep, f.entry)
					match got.status {
						Appended => Host.publish!(f.key, f.event)
						Failed => Host.fanout_failed!(f.surface, f.member, key, sid, got.fault)
					}
				}
				Failed(surface, member, fault) => Host.fanout_failed!(surface, member, key, sid, fault)
			}
			fanned!(key, sid, rest)
		}
	}
