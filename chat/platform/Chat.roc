## A REQUEST AS THE HOST HANDS IT, AND THE ANSWER: each crosses as a C struct
## (roc-webbox src/chat_abi.zig lays them out, and asserts their sizes).
##
## The path crosses as bytes, never `Str` (docs/ROC-CHAT.md R4): a request
## can name bytes that are not UTF-8, and the parts of the path a route
## hands back to Zig must be the bytes that came in.
Chat := [].{

	## **THE TAGS CROSS AS ONE BYTE EACH, NUMBERED ALPHABETICALLY** (Roc's
	## layout of a tag union with no payloads): roc-webbox src/chat_route.zig
	## and src/chat_abi.zig list each union's names in that order, and check
	## at compile time that they do. A tag added here is added there.

	## A request's method, as the router tells them apart.
	Method : [Get, Head, Post, Other]

	## `sub` is the path under /chat or /channel (`channel` says which), as
	## angry-gopher's router cut it: "" or starting with "/", no query.
	Request : { sub : List(U8), channel : Bool, method : Method }

	## Which part of the chat a path names. `rest` (below) is the family's
	## own remainder where it has one.
	Family : [
		NotFound,

		## A static script, `rest` its name; served before the gate.
		Asset,

		## `/chat`, `/chat/`, `/chat/default`: the last conversation resumed.
		Default,

		## `rest` the path under `/docs` (and the four below likewise).
		Docs,
		Recent,
		Images,
		Code,
		Links,

		## `rest` the path after `/search`, with no boundary (`/searchX` is "X").
		Search,
		Conversations,

		## `rest` the message id after `/msg/`.
		Msg,

		## A DM, `key` its pair as written.
		Dm,

		## A channel, `key` its name (already a valid one).
		Channel,
		Notifications,
		SidebarStream,
	]

	## Which part of a conversation.
	Part : [
		## No topic named: its first topic, or the page offering one.
		Landing,

		## `.../new`: a topic made.
		New,

		## A topic id that is not one: refused after the conversation's own checks.
		Invalid,

		## `sid` a valid topic id, `tail` what of it.
		Topic,
	]

	## What of a topic. `Invalid` is no tail Zig serves (refused once the
	## topic is known to exist); `InvalidSend` the same under `send`, which
	## skips that check (a send makes its topic).
	Tail : [Page, Uploads, Stream, Send, Upload, Pin, Unpin, Raw, Download, Saved, Reactions, React, Invalid, InvalidSend]

	## Where a request goes, as angry-gopher's Zig serves it (§5.2's
	## `ZigRoute`, flattened so the host lays it out by hand): a family,
	## and for a conversation its key, its part, and for a topic its id and
	## tail. `rest` is the family's own remainder: an asset's name, the
	## rest of a docs/recent/images/code/links/search path, a message id,
	## an upload's file. Unused fields are empty, `Landing` and `Page`, so
	## two routes are equal exactly when they go the same place.
	Route : { family : Family, key : List(U8), rest : List(U8), sid : List(U8), part : Part, tail : Tail }

	## A DM or channel the Roc found to be the member's (chat/main.roc
	## `find!`), as the host takes it for an operation on it: `family` `Dm`
	## or `Channel`, `key` its pair or name, `base` its URL base, `members`
	## each member once (whom a message is fanned out to). The host keeps no
	## conversation between calls: each operation is handed this.
	Conv : { family : Family, key : List(U8), base : List(U8), members : List(List(U8)) }

	## A message as the store keeps it (angry-gopher chat_store `ChatMessage`,
	## the Roc's Transcript.Msg): its id (`<sid>_<n>`), its author's name as
	## sent and account (`uid`), its stamp, its markdown. Handed to the store
	## (the count and the search index take it) and to the fan-out.
	Message : { id : List(U8), from : List(U8), at : List(U8), uid : List(U8), markdown : List(U8) }

	## What the answer is:
	## - `Serve`: Zig serves `route` (marking presence first when `presence`);
	## - `Redirect`: a 303 to `location`;
	## - `Respond`: `status` with `body`, and a content-type when
	##   `content_type` (with `nosniff`, the browser told not to guess another);
	## - `NotAllowed`: a 405 naming `allow`;
	## - `Answered`: answered already, by the host inside the call (a body
	##   too big), or failed there (the host returns its error);
	## - `Malformed`: a malformed form (the site's own 400);
	## - `NotFound`: webbox's plain 404;
	## - `Found`: a 302 to `location` (a lookup, then go);
	## - `Held`: as `Respond`, but the body is `body`, then bytes the host
	##   holds (a transcript, a rendered page; never copied into Roc and
	##   out), then `location`.
	Kind : [Serve, Redirect, Respond, NotAllowed, Answered, Malformed, NotFound, Found, Held]

	Answer : { kind : Kind, location : List(U8), presence : Bool, route : Route, status : U16, content_type : List(U8), body : List(U8), allow : Method, nosniff : Bool }

	## A route of `family` with nothing else.
	family : Family -> Route
	family = |f| { family: f, key: [], rest: [], sid: [], part: Landing, tail: Page }

	none : Answer
	none = { kind: Serve, location: [], presence: Bool.False, route: family(NotFound), status: 0, content_type: [], body: [], allow: Other, nosniff: Bool.False }

	## Zig serves it.
	zig : Route, Bool -> Answer
	zig = |route, presence| { ..none, route, presence }

	## A 303 to `location`.
	redirect : List(U8) -> Answer
	redirect = |location| { ..none, kind: Redirect, location }

	## `status` with `body`, typed `content_type` when it is not empty.
	respond : U16, List(U8), List(U8) -> Answer
	respond = |status, content_type, body| { ..none, kind: Respond, status, content_type, body }

	## A 200 of text, as stored: plain UTF-8, never sniffed for another type.
	plain : List(U8) -> Answer
	plain = |body| { ..respond(200, Str.to_utf8("text/plain; charset=utf-8"), body), nosniff: Bool.True }

	## A 200 of the host's held bytes as text, as stored, never sniffed.
	held_plain : Answer
	held_plain = { ..plain([]), kind: Held }

	## A 200 page: `before`, the host's held bytes, `after`.
	held_html : List(U8), List(U8) -> Answer
	held_html = |before, after| { ..respond(200, Str.to_utf8("text/html; charset=utf-8"), before), kind: Held, location: after }

	## A 405 naming `allow`.
	not_allowed : Method -> Answer
	not_allowed = |allow| { ..none, kind: NotAllowed, allow }

	## The host answered inside the call, or failed there.
	answered : Answer
	answered = { ..none, kind: Answered }

	## A malformed form: the site's 400, as for every form.
	malformed : Answer
	malformed = { ..none, kind: Malformed }

	## webbox's plain "not found".
	not_found : Answer
	not_found = { ..none, kind: NotFound }

	## A 302 to `location`.
	found : List(U8) -> Answer
	found = |location| { ..none, kind: Found, location }
}
