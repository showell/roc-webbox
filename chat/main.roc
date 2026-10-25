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
				if is_action(route) act!(req, route) else Chat.zig(route, !Route.is_stream(route))
			}
	}

## A topic's reactions (10), react (11), pin (5) or unpin (6), in a DM (11)
## or a channel (12).
is_action : Route.R -> Bool
is_action = |r|
	(r.family == 11 or r.family == 12) and r.part == 3 and (r.tail == 5 or r.tail == 6 or r.tail == 10 or r.tail == 11)

## The four, in the Zig's order: presence; the conversation and the topic
## (a miss is Zig's to answer, the same 404s); the method; then the route's
## own work.
act! : Chat.Request, Route.R => Chat.Answer
act! = |req, route| {
	Host.presence!({})
	if !Host.topic!(route.family, route.key, route.sid) {
		Chat.zig(route, Bool.False)
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
	body = Host.body!({})
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
