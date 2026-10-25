## A REQUEST AS THE HOST HANDS IT, AND THE ANSWER: each crosses as a C struct
## (roc-webbox src/chat_abi.zig lays them out, and asserts their sizes).
##
## The path crosses as bytes, never `Str` (docs/ROC-CHAT.md R4): a request
## can name bytes that are not UTF-8, and the parts of the path a route
## hands back to Zig must be the bytes that came in.
Chat := [].{
	## `sub` is the path under /chat or /channel (`channel` says which), as
	## angry-gopher's router cut it: "" or starting with "/", no query.
	## `method`: 1 GET, 2 HEAD, 3 POST, 0 any other.
	Request : { sub : List(U8), channel : Bool, method : U8 }

	## Where a request goes, as angry-gopher's Zig serves it (§5.2's
	## `ZigRoute`, flattened so the host lays it out by hand): a family,
	## and for a conversation its key, its part, and for a topic its id and
	## tail. `rest` is the family's own remainder: an asset's name, the
	## rest of a docs/recent/images/code/links/search path, a message id,
	## an upload's file. Unused fields are empty and 0, so two routes are
	## equal exactly when they go the same place.
	Route : { family : U8, key : List(U8), rest : List(U8), sid : List(U8), part : U8, tail : U8 }

	## `kind`:
	## - 0: serve `route` with Zig (marking presence first when `presence`);
	## - 1: a 303 to `location`;
	## - 2: `status` with `body`, and a content-type when `content_type`;
	## - 3: a 405 naming `allow`, a method's number;
	## - 4: answered already, by the host inside the call (a body too big),
	##   or failed there (the host returns its error);
	## - 5: a malformed form (the site's own 400).
	Answer : { kind : U8, location : List(U8), presence : Bool, route : Route, status : U16, content_type : List(U8), body : List(U8), allow : U8 }

	## A route of `family` with nothing else.
	family : U8 -> Route
	family = |f| { family: f, key: [], rest: [], sid: [], part: 0, tail: 0 }

	get : U8
	get = 1

	head : U8
	head = 2

	post : U8
	post = 3

	none : Answer
	none = { kind: 0, location: [], presence: Bool.False, route: family(0), status: 0, content_type: [], body: [], allow: 0 }

	## Zig serves it.
	zig : Route, Bool -> Answer
	zig = |route, presence| { ..none, route, presence }

	## A 303 to `location`.
	redirect : List(U8) -> Answer
	redirect = |location| { ..none, kind: 1, location }

	## `status` with `body`, typed `content_type` when it is not empty.
	respond : U16, List(U8), List(U8) -> Answer
	respond = |status, content_type, body| { ..none, kind: 2, status, content_type, body }

	## A 405 naming `allow`.
	not_allowed : U8 -> Answer
	not_allowed = |allow| { ..none, kind: 3, allow }

	## The host answered inside the call, or failed there.
	answered : Answer
	answered = { ..none, kind: 4 }

	## A malformed form: the site's 400, as for every form.
	malformed : Answer
	malformed = { ..none, kind: 5 }
}
