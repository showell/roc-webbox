## A REQUEST AS THE HOST HANDS IT, AND THE ANSWER: each crosses as a C struct
## (roc-webbox src/chat_abi.zig lays them out, and asserts their sizes).
##
## The path crosses as bytes, never `Str` (docs/ROC-CHAT.md R4): a request
## can name bytes that are not UTF-8, and the parts of the path a route
## hands back to Zig must be the bytes that came in.
Chat := [].{
	## `sub` is the path under /chat or /channel (`channel` says which), as
	## angry-gopher's router cut it: "" or starting with "/", no query.
	Request : { sub : List(U8), channel : Bool }

	## Where a request goes, as angry-gopher's Zig serves it (§5.2's
	## `ZigRoute`, flattened so the host lays it out by hand): a family,
	## and for a conversation its key, its part, and for a topic its id and
	## tail. `rest` is the family's own remainder: an asset's name, the
	## rest of a docs/recent/images/code/links/search path, a message id,
	## an upload's file. Unused fields are empty and 0, so two routes are
	## equal exactly when they go the same place.
	Route : { family : U8, key : List(U8), rest : List(U8), sid : List(U8), part : U8, tail : U8 }

	## `kind` 0: serve `route` with Zig (marking presence first when
	## `presence`); 1: a 303 to `location`.
	Answer : { kind : U8, location : List(U8), presence : Bool, route : Route }

	## A route of `family` with nothing else.
	family : U8 -> Route
	family = |f| { family: f, key: [], rest: [], sid: [], part: 0, tail: 0 }

	## Zig serves it.
	zig : Route, Bool -> Answer
	zig = |route, presence| { kind: 0, location: [], presence, route }

	## A 303 to `location`.
	redirect : List(U8) -> Answer
	redirect = |location| { kind: 1, location, presence: Bool.False, route: family(0) }
}
