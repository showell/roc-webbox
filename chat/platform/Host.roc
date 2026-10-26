## THE HOST'S ANSWERS, AS EFFECTS: each is asked when the app asks it, inside
## the request's call.
import Chat

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
	topic! : Chat.Family, List(U8), List(U8) => Bool

	## The request's body, read to a form's limit (`which`: the react
	## form's or a message's); not `ok` when the host answered instead (too
	## big) or failed.
	body! : [Reaction, Message] => { ok : Bool, bytes : List(U8) }

	## The topic's reaction sidecar, as stored; not `ok` when it failed.
	reactions! : {} => { ok : Bool, bytes : List(U8) }

	## Store the member's reaction to message `msg` and send it live: `Stored`,
	## `NoSuchMessage`, or `Failed`.
	react! : U64, List(U8), Bool => [Stored, NoSuchMessage, Failed]

	## Pin the topic for the member, or unpin it; false when it failed.
	pin! : Bool => Bool

	## A DM's or channel's landing (`family`, `key` the route's): none when
	## the conversation is not the member's (Zig answers why); else its URL
	## base and its first topic, and when it has none ("" ), the viewer and
	## the conversation's title.
	landing! : Chat.Family, List(U8) => List(List(U8))

	## The conversation page's data, for the topic `topic!` found: the
	## viewer, the title, the four limits (image, video, accept, search),
	## then the sidebar's fields (Pages.decode_sidebar). Reading it records
	## the topic as a DM's place to resume. None when it failed.
	page! : {} => List(List(U8))

	## Where a page names each script, as `name, src` pairs (a src's hash is
	## of bytes the host holds).
	srcs! : {} => List(List(U8))

	## **AFTER A FAILURE THE HOST DOES NOTHING MORE** for the call: a hosted
	## function the Roc calls once one has failed answers empty, false or
	## "failed", writes nothing, and the host returns the failure.

	## The member's own id.
	me! : {} => List(U8)

	## The member's name.
	viewer! : {} => List(U8)

	## The DM the member was last in (their bookmark), or "".
	last_conv! : {} => List(U8)

	## Where the member resumes DM `conv`: its last topic, else a default.
	resume_topic! : List(U8) => List(U8)

	## The topics of a DM (`Dm`, `key` its pair) or a channel (`Channel`, its
	## name), as the store lists them.
	topics! : Chat.Family, List(U8) => List(List(U8))

	## The channels the member is in.
	channels! : {} => List(List(U8))

	## Every member and the agent, as `id, name` pairs.
	members! : {} => List(List(U8))

	## A DM's or channel's conversation, for a new topic in it: none when it
	## is not the member's (Zig answers why); else its URL base and "1" for a
	## DM. The host holds it for `bookmark!` and `append!`.
	conv! : Chat.Family, List(U8) => List(List(U8))

	## Record topic `sid` as the member's place to resume the DM `conv!`
	## found; false when it failed.
	bookmark! : List(U8) => Bool

	## Append a message to topic `sid` of the conversation `conv!` or
	## `send_conv!` found, by the member under `name`, with the sender's
	## client id `cid` ("" for none), and send it live: the store's whole
	## append (its number, date, block, count, search, publish, fan-out).
	## False when it failed.
	append! : List(U8), List(U8), List(U8), List(U8) => Bool

	## A topic to send to (`family`, `key`, `sid` the route's): none when the
	## conversation is not the member's (Zig answers why); else its URL base
	## and "1" for a DM. Reads the conversation's title, as the Zig did. The
	## host holds it for `bookmark!` and `append!`.
	send_conv! : Chat.Family, List(U8), List(U8) => List(List(U8))

	## A request header's value, or none (read before the body).
	header! : List(U8) => List(List(U8))

	## Whether the topic `topic!` found has a transcript: the host reads it
	## and holds it for the answer (Chat.held_plain), never handing it to
	## Roc (false when the read failed, too).
	raw! : {} => Bool

	## Whether the member has a links page (users/<uid>/links.md): the host
	## renders it as the server's own markdown and holds it for the answer
	## (Chat.held_html) (false when the read failed, too).
	links! : {} => Bool

	## The member's feed file as stored (images.md or code.md):
	## none when there is none (or the read failed).
	feed! : [Images, Code] => List(List(U8))

	## The member's recent feed as gathered (angry-gopher recent.zig
	## `gatherRows`), nine fields a row: doc, secs, uid, name, key, label,
	## topic, markdown, dm. None when it failed.
	recent! : {} => List(List(U8))

	## Whether markdown is hostile: `Fine`; `Refused`, the host having refused it
	## (webbox's edge counter and its 400); or `Failed`, the check itself.
	hostile! : List(U8) => [Fine, Refused, Failed]
}
