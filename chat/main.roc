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
## C8.
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
				if is_action(route) or is_page(route) or is_own(route) act!(req, route) else Chat.zig(route, !Route.is_stream(route))
			}
	}

## A topic's reactions (10), react (11), pin (5) or unpin (6), in a DM (11)
## or a channel (12).
is_action : Route.R -> Bool
is_action = |r|
	(r.family == 11 or r.family == 12) and r.part == 3 and (r.tail == 5 or r.tail == 6 or r.tail == 10 or r.tail == 11)

## A conversation's landing (part 0) or a topic's page (part 3, tail 0), in
## a DM or a channel (docs/ROC-CHAT.md C3).
is_page : Route.R -> Bool
is_page = |r|
	(r.family == 11 or r.family == 12) and (r.part == 0 or (r.part == 3 and r.tail == 0))

## /chat and /chat/default (2), /chat/conversations (9), /chat/msg/<id>
## (10), and a new topic in a DM or a channel (part 1).
is_own : Route.R -> Bool
is_own = |r|
	r.family == 2 or r.family == 9 or r.family == 10 or ((r.family == 11 or r.family == 12) and r.part == 1)

## The Roc's own routes, in the Zig's order: presence; the conversation and
## the topic (a miss is Zig's to answer, the same 404s); the method; then
## the route's own work.
act! : Chat.Request, Route.R => Chat.Answer
act! = |req, route| {
	Host.presence!({})
	if route.family == 2 {
		resume!({})
	} else if route.family == 9 {
		if req.method != Chat.get Chat.not_allowed(Chat.get) else conversations!({})
	} else if route.family == 10 {
		msg!(route.rest)
	} else if route.part == 1 {
		new_topic!(req, route)
	} else if route.part == 0 {
		landing!(route)
	} else if !Host.topic!(route.family, route.key, route.sid) {
		Chat.zig(route, Bool.False)
	} else if route.tail == 0 {
		if req.method != Chat.get and req.method != Chat.head Chat.not_allowed(Chat.get) else page!(route)
	} else if route.tail == 10 {
		if req.method != Chat.get {
			Chat.not_allowed(Chat.get)
		} else {
			got = Host.reactions!({})
			if got.ok Chat.respond(200, Str.to_utf8("application/x-ndjson; charset=utf-8"), got.bytes) else Chat.answered
		}
	} else if req.method != Chat.post {
		Chat.not_allowed(Chat.post)
	} else if route.tail == 11 {
		react!({})
	} else if Host.pin!(route.tail == 5) {
		Chat.respond(204, [], [])
	} else {
		Chat.answered
	}
}

## POST .../react: the form, then the store's answer.
react! : {} => Chat.Answer
react! = |{}| {
	body = Host.body!(0)
	if !body.ok {
		Chat.answered
	} else {
		match Reaction.form(body.bytes) {
			Malformed => Chat.malformed
			Bad(why) => Chat.respond(400, [], why)
			Reacted(r) =>
				match Host.react!(r.msg, r.emoji, r.on) {
					0 => Chat.respond(204, [], [])
					1 => Chat.respond(400, [], Str.to_utf8("react: no such message\n"))
					_ => Chat.answered
				}
		}
	}
}

html : List(U8)
html = Str.to_utf8("text/html; charset=utf-8")

## A conversation's landing: its first topic, or, with none, the page that
## offers one.
landing! : Route.R => Chat.Answer
landing! = |route|
	match Host.landing!(route.family, route.key) {
		[base, first] => Chat.redirect(List.join([base, [47], first]))
		[base, _, viewer, title] => Chat.respond(200, html, Pages.no_topics(Chrome.src_in(Host.srcs!({})), viewer, base, title))
		_ => Chat.zig(route, Bool.False)
	}

## A topic's page, from what the host read.
page! : Route.R => Chat.Answer
page! = |route|
	match Host.page!({}) {
		[viewer, title, image_max, video_max, accept, search_min, .. as fields] => {
			sb = Pages.decode_sidebar(fields)
			limits = { image_max: Pages.number(image_max), video_max: Pages.number(video_max), accept, search_min: Pages.number(search_min) }
			view = { key: route.key, base: sb.base, sid: route.sid, title, uid: sb.uid, viewer, sidebar_json: Pages.sidebar_json(sb) }
			Chat.respond(200, html, Pages.conversation(Chrome.src_in(Host.srcs!({})), limits, view))
		}
		_ => Chat.answered
	}

json : List(U8)
json = Str.to_utf8("application/json; charset=utf-8")

## /chat: the member's last DM, at the topic they resume, or its own page
## when it has no topic yet; with none, the empty /chat.
resume! : {} => Chat.Answer
resume! = |{}| {
	conv = Host.last_conv!({})
	if conv == [] or !Paths.participant(conv, Host.me!({})) {
		Chat.respond(200, html, Pages.no_conversations(Chrome.src_in(Host.srcs!({})), Host.viewer!({})))
	} else if Paths.first_of(Host.topics!(11, conv)) == [] {
		Chat.redirect(List.concat(Str.to_utf8("/chat/c/"), conv))
	} else {
		Chat.redirect(List.join([Str.to_utf8("/chat/c/"), conv, [47], Host.resume_topic!(conv)]))
	}
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
				default = Host.resume_topic!(conv)
				sessions = Host.topics!(11, conv)
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
				match find_channel!(Host.channels!({}), sid, 0) {
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
				if List.contains(Host.topics!(11, conv), sid) Ok(conv) else find_dm!(me, members, sid, i + 2)
			}
		Err(_) => Err(None)
	}

find_channel! : List(List(U8)), List(U8), U64 => Try(List(U8), [None])
find_channel! = |names, sid, i|
	match List.get(names, i) {
		Ok(name) => if List.contains(Host.topics!(12, name), sid) Ok(name) else find_channel!(names, sid, i + 1)
		Err(_) => Err(None)
	}

## POST <base>/new: a topic made with a first "hi", a DM's announced in its
## highest general<N>; the conversation and topic as JSON.
new_topic! : Chat.Request, Route.R => Chat.Answer
new_topic! = |req, route|
	match Host.conv!(route.family, route.key) {
		[base, dm] =>
			if req.method != Chat.post {
				Chat.not_allowed(Chat.post)
			} else {
				body = Host.body!(1)
				if !body.ok {
					Chat.answered
				} else {
					match Form.field(body.bytes, Str.to_utf8("topic")) {
						Malformed => Chat.malformed
						Found(raw) => make!(route, base, dm == [49], ZigText.trim(raw))
						Missing => make!(route, base, dm == [49], [])
					}
				}
			}
		_ => Chat.zig(route, Bool.False)
	}

make! : Route.R, List(U8), Bool, List(U8) => Chat.Answer
make! = |route, base, dm, topic|
	if !Paths.valid_topic_id(topic) {
		Chat.respond(400, [], Str.to_utf8("Topic must be letters, digits, and hyphens only — no spaces, underscores, or punctuation.\n"))
	} else if Topics.same_name(topic, Str.to_utf8("new")) {
		Chat.respond(400, [], Str.to_utf8("\"new\" is reserved — pick another topic name.\n"))
	} else if List.any(Host.topics!(route.family, route.key), |s| Topics.same_name(s, topic)) {
		Chat.respond(409, [], Str.to_utf8("That topic already exists.\n"))
	} else {
		name = Host.viewer!({})
		# The bookmark first, as a send's: one that fails makes no topic.
		if dm and !Host.bookmark!(topic) {
			Chat.answered
		} else if !Host.append!(topic, name, Str.to_utf8("hi")) {
			Chat.answered
		} else if dm and !announce!(route, base, topic, name) {
			Chat.answered
		} else {
			Chat.respond(200, json, Topics.made_json(route.key, topic))
		}
	}

## A DM's new topic, said where the partner already watches: its highest
## general<N>, unless that is the topic made.
announce! : Route.R, List(U8), List(U8), List(U8) => Bool
announce! = |route, base, topic, name|
	match Topics.highest_general(Host.topics!(route.family, route.key)) {
		Ok(gen) if gen != topic =>
			Host.append!(gen, name, List.join([Str.to_utf8("New topic: ["), topic, Str.to_utf8("]("), base, [47], topic, Str.to_utf8(")")]))
		_ => Bool.True
	}
