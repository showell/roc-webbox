## THE HOST'S ANSWERS, AS EFFECTS: each is asked when the app asks it, inside
## the request's call.
import Chat

Host := [].{

	## Whether the one asking may use the chat (`Member`): a member, or the agent
	## (angry-gopher's `users.principalAuthorized` of who the request's
	## cookie or API key names). Asked after the static assets, which anyone
	## may fetch, so a request for one does no identity reads.
	check_member! : {} => [Member, Outsider]

	## Count this request as the member's presence, now (the prelude's, for
	## a request the Roc serves itself).
	count_presence! : {} => {}

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
	list_accounts! : {} => { accounts : List({ id : List(U8), kind : [Agent, Guest, Member, Unreadable], name : List(U8), name_read : [Found, Unreadable] }), status : [Failed, Found] }

	## The request's body, read to a form's limit (`which`: the react
	## form's, a message's or a doc's): `Read`, its bytes beside it;
	## `Answered` when the host answered instead (too big) or failed.
	read_body! : [Doc, Message, Reaction] => { bytes : List(U8), status : [Answered, Read] }

	## **THE BUS, AS A PRIMITIVE** (webbox's `bus.publish`): `bytes` to every
	## subscriber on `key`, each its own copy, as the stream writes it. It
	## cannot fail.
	publish! : List(U8), List(U8) => {}

	## **ONE LINE APPENDED** to the file at `path` under the chat root
	## (checked as `read!`'s is), its folders made as needed: `line`, then a
	## newline. **A TORN LINE STAYS ITS OWN LINE**: a file that does not end
	## in a newline gets one first, the host reading its last byte before it
	## stores, so a read that fails stores nothing. `Err(Failed)` when it
	## failed (the request has failed).
	append_line! : List(U8), List(U8) => Try({}, [Failed])

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

	## **A FILE'S SIZE AND ITS LAST CHANGE** under the chat root, the path
	## checked as `read!`'s is (metal-vmm QUEUE 274): its size in bytes and
	## its mtime in whole seconds since the epoch (`Found`), nothing there
	## (`Missing`), or a stat that failed, a folder among them (`Failed`: the
	## request has failed). Missing and failed are two answers, as `read!`'s.
	stat! : List(U8) => { mtime : I64, size : U64, status : [Failed, Found, Missing] }

	## **AT MOST `max` OF A FILE'S BYTES, FROM `offset`** under the chat
	## root, the path checked as `read!`'s is: fewer where the file ends
	## first (none past its end), `Missing` and `Failed` as `read!`'s.
	read_at! : List(U8), U64, U64 => { bytes : List(U8), status : [Failed, Found, Missing] }

	## Write the whole file as `bytes`, its folders made as needed; `Err(Failed)`
	## when it failed.
	write! : List(U8), List(U8) => Try({}, [Failed])

	## Remove the file (one not there is gone already); `Err(Failed)` when
	## it failed.
	remove! : List(U8) => Try({}, [Failed])

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
	## name, which a lookup needed and which `list_accounts!` listed as
	## unreadable (the error that read failed with, as the host kept it); a
	## message with no author's name (appendMessage's error.NoAuthor, `whose`
	## unused); a file at path `whose` whose bytes are not UTF-8 (Files.read!'s
	## door, error.NotUtf8).
	## An id that is no canonical uid (the member's own, from `me!`, or an
	## account folder's) is `NotAUid` (error.NotAUid), never said as a file
	## that is not UTF-8.
	fail! : [KindUnreadable, MalformedChannel, NameUnreadable, NoAuthor, NotAUid, NotUtf8], List(U8) => {}

	## Count channel `name` as one a listing skipped as malformed: the
	## operator's count, kept by the host for /admin/host.
	count_malformed_channel! : List(U8) => {}

	## **WHAT THE CHAT DROPPED RATHER THAN FAIL A REQUEST FOR** (metal-vmm
	## QUEUE 267), counted for the operator (/admin/host), about `whose`: a
	## DM's new-topic announcement that failed after the topic was made (the
	## topic), a feed's entries whose bytes are not UTF-8 (the feed's path),
	## a recent row whose text is not (its key).
	count_dropped! : [Announcement, FeedEntry, RecentRow], List(U8) => {}

	## **AN ASIDE: WORK WHOSE FAILURE IS ITS OWN** (STORED IS DONE): from
	## `Begin` to `End`, a primitive that fails fails the aside, never the
	## request, and the aside's later calls do nothing, as a failed
	## request's do. `End` answers `Failed` when anything in it failed, and
	## the request goes on. `Begin` answers `Failed` only for a request that
	## has failed already.
	aside! : [Begin, End] => [Done, Failed]

	## **WHO IS ONLINE, AT THE REQUEST'S TIME** (angry-gopher presence.zig
	## `isOnline`): for each of `ids`, in their order, whether it was seen
	## within the presence window of the request's `now`. A read of the
	## host's process-lifetime map, one call for the whole roster. It cannot
	## fail; an id never seen is `Offline`.
	check_online! : List(List(U8)) => List([Offline, Online])

	## **SEARCH'S RATE LIMIT** (angry-gopher chat_search.zig `admit`): whether
	## the member may search now, a few times a second; `Refused` past it.
	admit! : {} => [Admitted, Refused]

	## The value of the request's query field `name`, as written (not
	## decoded), the first of them; none when there is no such field.
	read_query! : List(U8) => List(List(U8))

	## **SEARCH'S INDEX, ASKED** (angry-gopher search_index.zig `wordsFor`):
	## the words beginning `key` (already a key: trimmed and folded) that
	## the member can see, each with how many messages hold it, the most
	## held first, at most `most`; and how many of their transcripts the
	## index could not read. `NotReady` when there is no index to ask.
	search_words! : List(U8), U64 => { status : [NotReady, Ready], unreadable : U64, words : List({ count : U64, word : List(U8) }) }

	## **SEARCH'S INDEX, ASKED FOR MESSAGES** (angry-gopher search_index.zig
	## `messagesFor`): the messages holding the word `key` the member can
	## see, at most `most`, within the byte cap; how many hold it in all;
	## the unreadable count. Each hit's excerpt window, not the message: its
	## bytes from `start` through the one past the excerpt's end, of a
	## message `length` long, the word `at` when `found`.
	search_messages! : List(U8), U64 => { status : [NotReady, Ready], matched : U64, unreadable : U64, hits : List({ at : U64, length : U64, start : U64, base : List(U8), date : List(U8), from : List(U8), id : List(U8), sid : List(U8), window : List(U8), found : [Found, Missing], kind : [Channel, Dm] }) }

	## **THE WELCOME, PENDING** (angry-gopher users.zig `welcomePending`,
	## metal-vmm QUEUE 283): whether the member's welcome is pending, a fact
	## signup wrote in the gopher's own users folder. `Failed` when the look
	## failed (the host has failed the request).
	welcome_pending! : {} => [Failed, None, Pending]

	## The member's welcome given: the pending mark goes (one gone already
	## is done). `Err(Failed)` when it failed.
	welcome_done! : {} => Try({}, [Failed])

	## Where a page names each script, by its name (a src's hash is of bytes
	## the host holds).
	srcs! : {} => List({ name : List(U8), src : List(U8) })

	## **AFTER A FAILURE THE HOST DOES NOTHING MORE** for the call: a hosted
	## function the Roc calls once one has failed answers empty,
	## `Err(Failed)`, `NotServing` or "failed", writes nothing, and the host
	## returns the failure.

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
	## search index (`message`, as it lands). `Err(Failed)` when the append failed
	## (the request has failed, and nothing was stored). **STORED IS DONE**:
	## the count and the search are best-effort and never fail it.
	store_message! : Chat.Conv, List(U8), List(U8), U64, Chat.Message => Try({}, [Failed])

	## **THE FAN-OUT'S PRIMITIVES NEVER FAIL THE REQUEST** (metal-vmm QUEUE
	## 172, 156(c)): the fan-out runs after the store, and **STORED IS DONE**.
	## Each that can fail answers its `fault`, the host's error as a number
	## the Roc never reads, carried to `report_fanout_failure!` to be counted and
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
	report_fanout_failure! : [Code, Images], List(U8), List(U8), List(U8), U16 => {}

	## A request header's value, or none (read before the body).
	read_header! : List(U8) => List(List(U8))

	## **THE HOST SERVES THE FILE** at `path` under the chat root (checked as
	## `read!`'s is) as the answer, `Serving` when it is there: the host reads
	## it and holds its bytes (Chat.served_plain), never handing them to Roc
	## (`NotServing` when the read failed, too).
	serve_file! : List(U8) => [Serving, NotServing]

	## **THE HOST SERVES THE FILE RENDERED** at `path` under the chat root
	## (checked as `read!`'s is) as the answer, `Serving` when it is there: the
	## host renders it as the server's own markdown and holds it
	## (Chat.served_html) (`NotServing` when the read failed, too).
	serve_rendered! : List(U8) => [Serving, NotServing]

	## Whether markdown is hostile: `Fine`; `Refused`, the host having refused it
	## (webbox's edge counter and its 400, saying `refusal`, the Roc's words);
	## or `Failed`, the check itself.
	check_hostile! : List(U8), List(U8) => [Fine, Refused, Failed]
}
