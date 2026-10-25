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
app [handle!] { pf: platform "platform/main.roc" }

import pf.Chat
import pf.Host
import Route

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
				Chat.zig(route, !Route.is_stream(route))
			}
	}
