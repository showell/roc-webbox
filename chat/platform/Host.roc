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

	## **EVERY ACCOUNT, THE ONE IDENTITY PRIMITIVE**: each account folder
	## named as a counter names one (a canonical id), in the disk's order,
	## with its kind (the agent; a member, who has a password; a guest, who
	## has neither) and its `name` file's bytes as stored ("" when it has
	## none). Accounts.roc does every lookup on them. `Failed` when one would
	## not read: the request has failed, and the list is no answer. **NEVER
	## THE AUTH ROOT ITSELF**: the host reads only the folders, whether each
	## has a password, and each name, never a password or a key. Asked at
	## most once a request.
	accounts! : {} => { accounts : List({ id : List(U8), kind : [Agent, Guest, Member], name : List(U8) }), status : [Failed, Found] }
	## The request's body, read to a form's limit (`which`: the react
	## form's or a message's); not `ok` when the host answered instead (too
	## big) or failed.
	body! : [Reaction, Message] => { ok : Bool, bytes : List(U8) }

	## Store the member's reaction to message `msg` of topic `sid` in `conv`
	## and send it live: `Stored`, `NoSuchMessage`, or `Failed`.
	react! : Chat.Conv, List(U8), U64, List(U8), Bool => [Stored, NoSuchMessage, Failed]

	## **THE FILES, AS PRIMITIVES**: a file or folder under the chat root,
	## `path` relative to it (ChatState.roc, Feeds.roc and Paths.roc name
	## them), its bytes as
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

	## The folder at `path` (checked as a file's is), each entry's name and
	## kind in the order the disk gives them (`Found`); nothing there
	## (`Missing`: webbox's store.list holds it empty); or a listing that
	## failed (`Failed`: the request has failed; a path that is a file is
	## one, as store.list fails it).
	list! : List(U8) => { entries : List({ kind : [Dir, File, Other], name : List(U8) }), status : [Failed, Found, Missing] }

	## Fail the request (a 500), for a reason, as the host fails it with that
	## reason's error: a channel's member file the Roc found malformed, on
	## the channel's own route (channelMembers's error.MalformedChannel).
	## One reason crosses as nothing (chat_abi.zig `roc_chat_fail`).
	fail! : [MalformedChannel] => {}

	## Count channel `name` as one a listing skipped as malformed: the
	## operator's count, kept by the host for /admin/host.
	malformed_channel! : List(U8) => {}

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

	## The request's time, in Unix seconds: the one time everything it
	## stamps carries (a new conversation's topic is named for its date).
	now! : {} => I64

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
