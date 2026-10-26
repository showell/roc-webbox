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

	## **THE FILES, AS PRIMITIVES**: a file under the chat root, `path`
	## relative to it (ChatState.roc and Feeds.roc name them), its bytes as
	## the Roc's formats write them. A path that is empty, absolute or
	## through `..` is the Roc's bug: the request fails (a 500), never a
	## missing file.
	##
	## The file's bytes (`Found`), nothing there (`Missing`), or a read that
	## failed (`Failed`: the request has failed). **MISSING AND FAILED ARE
	## NEVER ONE ANSWER**: what is read is often rewritten, so a failure read
	## as "no file" would write over what could not be seen.
	read! : List(U8) => { bytes : List(U8), status : [Failed, Found, Missing] }

	## Write the whole file as `bytes`, its folders made as needed; false
	## when it failed.
	write! : List(U8), List(U8) => Bool

	## Remove the file (one not there is gone already); false when it failed.
	remove! : List(U8) => Bool

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

	## The member's recent feed as gathered (angry-gopher recent.zig
	## `gatherRows`), nine fields a row: doc, secs, uid, name, key, label,
	## topic, markdown, dm. None when it failed.
	recent! : {} => List(List(U8))

	## Whether markdown is hostile: `Fine`; `Refused`, the host having refused it
	## (webbox's edge counter and its 400); or `Failed`, the check itself.
	hostile! : List(U8) => [Fine, Refused, Failed]
}
