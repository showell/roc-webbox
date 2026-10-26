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

	## Whether account `id` exists (angry-gopher's `users.principalExists`):
	## a DM's other half must, its folder and fan-out being named after
	## both.
	account! : List(U8) => Bool

	## Account `id`'s name, or "" when it has none (`users.getUserName`).
	name! : List(U8) => List(U8)

	## Channel `name`'s members, as its member file lists them; none when
	## there is no such channel (one with no members is as little the
	## member's).
	channel_members! : List(U8) => List(List(U8))

	## The request's body, read to a form's limit (`which`: the react
	## form's or a message's); not `ok` when the host answered instead (too
	## big) or failed.
	body! : [Reaction, Message] => { ok : Bool, bytes : List(U8) }

	## Topic `sid`'s reaction sidecar in `conv`, as stored; not `ok` when it
	## failed.
	reactions! : Chat.Conv, List(U8) => { ok : Bool, bytes : List(U8) }

	## Store the member's reaction to message `msg` of topic `sid` in `conv`
	## and send it live: `Stored`, `NoSuchMessage`, or `Failed`.
	react! : Chat.Conv, List(U8), U64, List(U8), Bool => [Stored, NoSuchMessage, Failed]

	## The member's pinned topics in `conv`, as the file holds them ("" when
	## there is none); not `ok` when the read failed. **A SET THAT WILL NOT
	## READ IS NOT AN EMPTY SET**: what is read is rewritten, so a failure
	## read as "no pins" would drop every pin.
	pins! : Chat.Conv => { ok : Bool, bytes : List(U8) }

	## Write that file as `bytes` (ChatState.pinned's); false when it failed.
	write_pins! : Chat.Conv, List(U8) => Bool

	## Remove that file, no pin being left; false when it failed.
	remove_pins! : Chat.Conv => Bool

	## Topic `sid`'s page's data, in `conv`: the viewer, the four limits
	## (image, video, accept, search), then the sidebar's fields
	## (Pages.decode_sidebar). None when it failed.
	page! : Chat.Conv, List(U8) => List(List(U8))

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

	## The topic the member last viewed in DM `conv`, or "" (ChatState.resume_topic
	## judges whether it is still there).
	last_viewed! : List(U8) => List(U8)

	## The request's time, in Unix seconds: the one time everything it
	## stamps carries (a new conversation's topic is named for its date).
	now! : {} => I64

	## The topics of a DM (`Dm`, `key` its pair) or a channel (`Channel`, its
	## name), as the store lists them.
	topics! : Chat.Family, List(U8) => List(List(U8))

	## Every channel and its members, flat as `name, count, member...` each,
	## in the listing's order; a malformed one the host skipped (and counted:
	## that is the operator's). Which are the member's is Paths.member_channels.
	channel_rosters! : {} => List(List(U8))

	## Every member and the agent, as `id, name` pairs.
	members! : {} => List(List(U8))

	## Record topic `sid` as the member's place to resume DM `conv` (and
	## `conv` as the DM they were last in); false when it failed.
	bookmark! : Chat.Conv, List(U8) => Bool

	## Append a message to topic `sid` of `conv`, by the member under
	## `name`, with the sender's client id `cid` ("" for none), and send it
	## live to `conv`'s members: the store's whole append (its number, date,
	## block, count, search, publish, fan-out). False when it failed.
	append! : Chat.Conv, List(U8), List(U8), List(U8), List(U8) => Bool

	## A request header's value, or none (read before the body).
	header! : List(U8) => List(List(U8))

	## Whether topic `sid` of `conv` has a transcript: the host reads it and
	## holds it for the answer (Chat.held_plain), never handing it to Roc
	## (false when the read failed, too).
	raw! : Chat.Conv, List(U8) => Bool

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
