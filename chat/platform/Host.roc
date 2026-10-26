## THE HOST'S ANSWERS, AS EFFECTS: each is asked when the app asks it, inside
## the request's call.
Host := [].{
	## Whether the one asking may use the chat: a member, or the agent
	## (angry-gopher's `users.principalAuthorized` of who the request's
	## cookie or API key names). Asked after the static assets, which anyone
	## may fetch, so a request for one does no identity reads.
	member! : {} => Bool

	## Count this request as the member's presence, now (the prelude's, for
	## a request the Roc serves itself).
	presence! : {} => {}

	## Whether the route's conversation is one the member may use and its
	## topic is there (`family`, `key`, `sid` the route's), as angry-gopher
	## looks them up before serving a topic. When it is, the host holds the
	## topic for the calls below; when not, the Roc hands the route to Zig,
	## which answers why.
	topic! : U8, List(U8), List(U8) => Bool

	## The request's body, read to the react form's limit; not `ok` when the
	## host answered instead (too big) or failed.
	body! : {} => { ok : Bool, bytes : List(U8) }

	## The topic's reaction sidecar, as stored; not `ok` when it failed.
	reactions! : {} => { ok : Bool, bytes : List(U8) }

	## Store the member's reaction to message `msg` and send it live: 0 when
	## stored, 1 when there is no such message, 2 when it failed.
	react! : U64, List(U8), Bool => U8

	## Pin the topic for the member, or unpin it; false when it failed.
	pin! : Bool => Bool

	## A DM's or channel's landing (`family`, `key` the route's): none when
	## the conversation is not the member's (Zig answers why); else its URL
	## base and its first topic, and when it has none ("" ), the viewer and
	## the conversation's title.
	landing! : U8, List(U8) => List(List(U8))

	## The conversation page's data, for the topic `topic!` found: the
	## viewer, the title, the four limits (image, video, accept, search),
	## then the sidebar's fields (Pages.decode_sidebar). Reading it records
	## the topic as a DM's place to resume. None when it failed.
	page! : {} => List(List(U8))

	## Where a page names each script, as `name, src` pairs (a src's hash is
	## of bytes the host holds).
	srcs! : {} => List(List(U8))
}
