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
	## none). Accounts.roc does every lookup on them. **AN ACCOUNT THAT WILL
	## NOT READ IS LISTED, NEVER LEFT OUT**: a password whose stat failed is
	## a `kind` of `Unreadable`, a name that would not read a `name_read` of
	## `Unreadable` (its `name` empty, and never one); the host keeps each
	## error, and the request fails with it only when a lookup needs that
	## read (`fail!`). `Failed` when the accounts could not be listed at all:
	## the request has failed, and the list is no answer. **NEVER THE AUTH
	## ROOT ITSELF**: the host reads only the folders, whether each has a
	## password, and each name, never a password or a key. Asked at most once
	## a request.
	accounts! : {} => { accounts : List({ id : List(U8), kind : [Agent, Guest, Member, Unreadable], name : List(U8), name_read : [Found, Unreadable] }), status : [Failed, Found] }

	## The request's body, read to a form's limit (`which`: the react
	## form's or a message's): `Read`, its bytes beside it; `Answered` when
	## the host answered instead (too big) or failed.
	body! : [Reaction, Message] => { bytes : List(U8), status : [Answered, Read] }

	## **THE BUS, AS A PRIMITIVE** (webbox's `bus.publish`): `bytes` to every
	## subscriber on `key`, each its own copy, as the stream writes it. It
	## cannot fail.
	publish! : List(U8), List(U8) => {}

	## **ONE LINE APPENDED** to the file at `path` under the chat root
	## (checked as `read!`'s is), its folders made as needed: `line`, then a
	## newline. **A TORN LINE STAYS ITS OWN LINE**: a file that does not end
	## in a newline gets one first, the host reading its last byte before it
	## stores, so a read that fails stores nothing. False when it failed (the
	## request has failed).
	append_line! : List(U8), List(U8) => Bool

	## Topic `sid` of `conv`'s message count (the store's count cache,
	## believed only while the transcript is the size it was counted at, or
	## the transcript recounted). `Failed` when it could not be counted (the
	## request has failed): **NEVER 0 FOR A COUNT THAT FAILED**.
	message_count! : Chat.Conv, List(U8) => { count : U64, status : [Counted, Failed] }

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

	## Fail the request (a 500), for a reason, about `whose`, with the error
	## the Zig it replaced failed it with: channel `whose`'s member file the
	## Roc found malformed, on the channel's own route
	## (channelMembers's error.MalformedChannel); account `whose`'s kind or
	## name, which a lookup needed and which `accounts!` listed as
	## unreadable (the error that read failed with, as the host kept it); a
	## message with no author's name (appendMessage's error.NoAuthor, `whose`
	## unused); a file at path `whose` whose bytes are not UTF-8 (Files.read!'s
	## door, error.NotUtf8).
	fail! : [KindUnreadable, MalformedChannel, NameUnreadable, NoAuthor, NotUtf8], List(U8) => {}

	## Count channel `name` as one a listing skipped as malformed: the
	## operator's count, kept by the host for /admin/host.
	malformed_channel! : List(U8) => {}

	## **WHO IS ONLINE, AT THE REQUEST'S TIME** (angry-gopher presence.zig
	## `isOnline`): for each of `ids`, in their order, whether it was seen
	## within the presence window of the request's `now`. A read of the
	## host's process-lifetime map, one call for the whole roster. It cannot
	## fail; an id never seen is `Offline`.
	online! : List(List(U8)) => List([Offline, Online])

	## **THE LIMITS THE SERVER ENFORCES**, as the page tells its client: the
	## largest image and video an upload takes, the types it accepts, the
	## shortest word a search looks for. **SINGLE-SOURCED IN THE HOST**: the
	## upload and search code enforce these values, so the Roc never copies
	## them.
	limits! : {} => { image_max : U64, video_max : U64, accept : List(U8), search_min : U64 }

	## Where a page names each script, by its name (a src's hash is of bytes
	## the host holds).
	srcs! : {} => List({ name : List(U8), src : List(U8) })

	## **AFTER A FAILURE THE HOST DOES NOTHING MORE** for the call: a hosted
	## function the Roc calls once one has failed answers empty, false or
	## "failed", writes nothing, and the host returns the failure.

	## The member's own id.
	me! : {} => List(U8)

	## The request's time, in Unix seconds: the one time everything it
	## stamps carries (a new conversation's topic is named for its date).
	now! : {} => I64

	## **THE ONE MARKDOWN PROCESSOR** (angry-gopher markdown.zig `render`):
	## a message's markdown as the HTML its frame carries. `Failed` when it
	## could not be rendered (the request has failed): never an empty page.
	render! : List(U8) => { html : List(U8), status : [Failed, Rendered] }

	## **A MESSAGE STORED**: `block` (Transcript.stored_form of message
	## `index` of topic `sid` in `conv`) appended to the topic's transcript,
	## then the store's infrastructure told: the count cache (`index` + 1,
	## the transcript's new size, the block's offset and its author) and the
	## search index (`message`, as it lands). False when the append failed
	## (the request has failed, and nothing was stored). **STORED IS DONE**:
	## the count and the search are best-effort and never fail it.
	store_message! : Chat.Conv, List(U8), List(U8), U64, Chat.Message => Bool

	## **THE FAN-OUT'S PRIMITIVES NEVER FAIL THE REQUEST** (metal-vmm QUEUE
	## 172, 156(c)): the fan-out runs after the store, and **STORED IS DONE**.
	## Each that can fail answers its `fault`, the host's error as a number
	## the Roc never reads, carried to `fanout_failed!` to be counted and
	## said; a member's other surfaces, and every other member's, go on.

	## **A FEED'S ENTRY APPENDED** to the file at `path` under the chat root
	## (checked as `read!`'s is, but a path outside it is this append's
	## failure, never the request's), its folders made: `separator` and
	## `entry` when the file holds anything, else `entry` alone. `Failed`,
	## with its fault, when it could not be.
	append_entry! : List(U8), List(U8), List(U8) => { fault : U16, status : [Appended, Failed] }

	## **A SURFACE THAT FAILED FOR ONE MEMBER, COUNTED AND SAID** (angry-gopher
	## chat_fanout `fanoutFailed`): `surface` for `member`, with `fault` (as a
	## primitive answered it), on topic `sid` of the conversation keyed `key`.
	## The operator's count and last failure, kept by the host for
	## /admin/host.
	fanout_failed! : [Code, Images], List(U8), List(U8), List(U8), U16 => {}

	## A request header's value, or none (read before the body).
	header! : List(U8) => List(List(U8))

	## Whether the file at `path` under the chat root (checked as `read!`'s
	## is) is there: the host reads it and holds its bytes for the answer
	## (Chat.held_plain), never handing them to Roc (false when the read
	## failed, too).
	raw! : List(U8) => Bool

	## Whether the file at `path` under the chat root (checked as `read!`'s
	## is) is there: the host renders it as the server's own markdown and
	## holds it for the answer (Chat.held_html) (false when the read failed,
	## too).
	links! : List(U8) => Bool

	## The member's recent feed as gathered (angry-gopher recent.zig
	## `gatherRows`), each field as the host writes it: `secs` a signed
	## decimal. None when it failed.
	recent! : {} => List({ kind : [Doc, Message], secs : List(U8), uid : List(U8), name : List(U8), key : List(U8), label : List(U8), topic : List(U8), markdown : List(U8), dm : [Dm, Channel] })

	## Whether markdown is hostile: `Fine`; `Refused`, the host having refused it
	## (webbox's edge counter and its 400); or `Failed`, the check itself.
	hostile! : List(U8) => [Fine, Refused, Failed]
}
