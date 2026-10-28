## THE HOST'S ANSWERS, AS EFFECTS: each is asked when the app asks it, inside
## the request's call.
import Chat

Host := [].{

	## **WHO IS ASKING, AND NOTHING MORE** (angry-gopher's
	## `users.currentUserID`): the account id the request's session cookie,
	## API key or guest cookie names, verified by the host, which alone holds
	## the secrets (`Known`, the id beside it); no one (`Stranger`); or the
	## look failed (`Failed`: the request has failed). Whether that one may
	## use the chat is the Roc's (Members.admit!), from `list_accounts!`.
	## Asked after the static assets, which anyone may fetch, so a request
	## for one does no identity reads.
	identify! : {} => {
		uid : List(U8),
		status : [
			Failed,
			Known,
			Stranger,
		],
	}

	## **COUNT THIS REQUEST AS THE MEMBER'S PRESENCE**, now, in the online
	## map (process-lifetime state, so the host's), and say whether it was
	## the edge: offline until now (`CameOnline`, the Roc's to broadcast,
	## metal-vmm QUEUE 288), or an edge whose broadcast was lost and is due
	## again; else `Steady`.
	count_presence! : {} => [CameOnline, Steady]

	## **THE EDGE NOT SPENT**: its broadcast was lost (a read it needed
	## failed), so a request 30 s on is the edge again, not every request.
	presence_unspent! : {} => {}

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
	## password, and each name, never a password or a key. Asked once a
	## request: at the chat's door (Members.admit!), every route then looking
	## up in that one listing; once by the admin retire.
	list_accounts! : {} => {
		accounts : List(
			{
				id : List(U8),
				kind : [
					Agent,
					Guest,
					Member,
					Unreadable,
				],
				name : List(U8),
				name_read : [Found, Unreadable],
			},
		),
		status : [Failed, Found],
	}

	## The request's body, read to a form's limit (`which`: the react
	## form's, a message's or a doc's): `Read`, its bytes beside it;
	## `Answered` when the host answered instead (too big) or failed.
	read_body! : [
		Doc,
		Message,
		Reaction,
	] => { bytes : List(U8), status : [Answered, Read] }

	## **THE BUS, AS A PRIMITIVE** (webbox's `bus.publish`): `bytes` to every
	## subscriber on `key`, each its own copy, as the stream writes it. It
	## cannot fail.
	publish! : List(U8), List(U8) => {}

	## **BYTES APPENDED, AS A PRIMITIVE**: `bytes` exactly, at the end of
	## the file at `path` under the chat root (checked as `read!`'s is), its
	## folders made as needed, in one write; the file's size after it
	## (`Appended`). `Failed` when it failed (the request has failed, or
	## the aside, and nothing was stored). Every rule of what goes before
	## the bytes (a torn line's newline, a feed's separator) is the Roc's
	## (Files.roc).
	append! : List(U8), List(U8) => { size : U64, status : [Appended, Failed] }

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
	read! : List(U8) => {
		bytes : List(U8),
		status : [
			Failed,
			Found,
			Missing,
		],
	}

	## **A FILE'S SIZE AND ITS LAST CHANGE** under the chat root, the path
	## checked as `read!`'s is (metal-vmm QUEUE 274): its size in bytes and
	## its mtime in whole seconds since the epoch (`Found`), nothing there
	## (`Missing`), or a stat that failed, a folder among them (`Failed`: the
	## request has failed). Missing and failed are two answers, as `read!`'s.
	read_stat! : List(U8) => {
		mtime : I64,
		size : U64,
		status : [
			Failed,
			Found,
			Missing,
		],
	}

	## **AT MOST `max` OF A FILE'S BYTES, FROM `offset`** under the chat
	## root, the path checked as `read!`'s is: fewer where the file ends
	## first (none past its end), `Missing` as `read!`'s. **A CACHE'S READ**
	## (metal-vmm QUEUE 284): `Failed` is the read's alone, logged by the
	## host, never the request's failure (Files.read_cache!).
	read_at! : List(U8),
	U64,
	U64 => {
		bytes : List(U8),
		status : [
			Failed,
			Found,
			Missing,
		],
	}

	## Write the whole file as `bytes`, its folders made as needed; `Err(Failed)`
	## when it failed.
	write! : List(U8), List(U8) => Try({}, [Failed])

	## Remove the file (one not there is gone already); `Err(Failed)` when
	## it failed.
	remove! : List(U8) => Try({}, [Failed])

	## **THE ADMIN RETIRE** (metal-vmm QUEUE 293), asked through the `Retire`
	## area: how old is old (`days`), the names kept, one to a line, and now
	## in unix seconds.
	retire_asked! : {} => {
		days : U64,
		keep : List(U8),
		now : I64,
	}

	## A step of the plan, said for the report: its kind and its name.
	retire_note! : [
		ChannelMember,
		Dm,
		RefLastConv,
		RefLastSession,
		RefPinned,
		Topic,
		User,
	],
	List(U8) => {}

	## The file, or the folder and all in it, removed when the retire is
	## confirmed (one not there is gone already); a dry run removes nothing.
	## `Err(Failed)` when it failed: the confirm ends there.
	retire_remove! : List(U8), [File, Tree] => Try({}, [Failed])

	## The file written whole as `bytes` when the retire is confirmed.
	retire_replace! : List(U8), List(U8) => Try({}, [Failed])

	## The member `uid` retired when confirmed: everything of theirs the host
	## keeps outside the chat now, their account once every step has gone.
	retire_user! : List(U8) => Try({}, [Failed])

	## The folder at `path` (checked as a file's is), each entry's name and
	## kind in the order the disk gives them (`Found`); nothing there
	## (`Missing`: webbox's store.list holds it empty); or a listing that
	## failed (`Failed`: the request has failed; a path that is a file is
	## one, as store.list fails it).
	list! : List(U8) => {
		entries : List(
			{
				kind : [
					Dir,
					File,
					Other,
				],
				name : List(U8),
			},
		),
		status : [
			Failed,
			Found,
			Missing,
		],
	}

	## Fail the request (a 500), for a reason, about `whose`, with the error
	## the Zig it replaced failed it with: channel `whose`'s member file the
	## Roc found malformed, on the channel's own route
	## (channelMembers's error.MalformedChannel); account `whose`'s kind or
	## name, which a lookup needed and which `list_accounts!` listed as
	## unreadable (the error that read failed with, as the host kept it); a
	## message with no author's name (appendMessage's error.NoAuthor, `whose`
	## unused); a file at path `whose` whose bytes are not UTF-8 (Files.read!'s
	## door, error.NotUtf8); a file at path `whose` whose last byte, which a
	## stat said is there, would not read (Files.append_line!'s torn-line
	## check, error.ShortRead).
	## An id that is no canonical uid (the member's own, from `me!`, or an
	## account folder's) is `NotAUid` (error.NotAUid), never said as a file
	## that is not UTF-8.
	fail! : [
		KindUnreadable,
		MalformedChannel,
		NameUnreadable,
		NoAuthor,
		NotAUid,
		NotUtf8,
		ShortRead,
	],
	List(U8) => {}

	## Count channel `name` as one a listing skipped as malformed: the
	## operator's count, kept by the host for /admin/host.
	count_malformed_channel! : List(U8) => {}

	## Count a transcript block the decoder refused (Transcript.decode_blocks:
	## no id, author or date), `first` its first line: the operator's count of
	## reads that met one, and the last one's line, kept by the host for
	## /admin/host.
	count_refused_block! : List(U8) => {}

	## **WHAT THE CHAT DROPPED RATHER THAN FAIL A REQUEST FOR** (metal-vmm
	## QUEUE 267), counted for the operator (/admin/host), about `whose`: a
	## DM's new-topic announcement that failed after the topic was made (the
	## topic), a feed's entries whose bytes are not UTF-8 (the feed's path),
	## a recent row whose text is not (its key).
	count_dropped! : [
		Announcement,
		FeedEntry,
		RecentRow,
	],
	List(U8) => {}

	## **AN ASIDE: WORK WHOSE FAILURE IS ITS OWN** (STORED IS DONE): from
	## `Begin` to `End`, a primitive that fails fails the aside, never the
	## request, and the aside's later calls do nothing, as a failed
	## request's do. `End` answers `Failed` when anything in it failed, with
	## its `fault` (the host's error as a number the Roc never reads, to be
	## carried to `report_fanout_failure!`), and the request goes on.
	## `Begin` answers `Failed` only for a request that has failed already:
	## then nothing is begun, and no `End` follows. **ASIDES NEST**: one
	## begun inside another ends first, and its failure is its own alone.
	mark_aside! : [Begin, End] => { fault : U16, status : [Done, Failed] }

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
	search_words! : List(U8),
	U64 => {
		status : [NotReady, Ready],
		unreadable : U64,
		words : List({ count : U64, word : List(U8) }),
	}

	## **SEARCH'S INDEX, ASKED FOR MESSAGES** (angry-gopher search_index.zig
	## `messagesFor`): the messages holding the word `key` the member can
	## see, at most `most`, within the byte cap; how many hold it in all;
	## the unreadable count. Each hit's excerpt window, not the message: its
	## bytes from `start` through the one past the excerpt's end, of a
	## message `length` long, the word `at` when `found`.
	search_messages! : List(U8),
	U64 => {
		status : [NotReady, Ready],
		matched : U64,
		unreadable : U64,
		hits : List(
			{
				at : U64,
				length : U64,
				start : U64,
				base : List(U8),
				date : List(U8),
				from : List(U8),
				id : List(U8),
				sid : List(U8),
				window : List(U8),
				found : [Found, Missing],
				kind : [Channel, Dm],
			},
		),
	}

	## **THE WELCOME, PENDING** (angry-gopher users.zig `welcomePending`,
	## metal-vmm QUEUE 283): whether the member's welcome is pending, a fact
	## signup wrote in the gopher's own users folder. `Failed` when the look
	## failed (the host has failed the request).
	check_welcome! : {} => [
		Failed,
		None,
		Pending,
	]

	## The member's welcome given: the pending mark goes (one gone already
	## is done). `Err(Failed)` when it failed.
	clear_welcome! : {} => Try({}, [Failed])

	## Where a page names each script, by its name (a src's hash is of bytes
	## the host holds).
	list_srcs! : {} => List({ name : List(U8), src : List(U8) })

	## **AFTER A FAILURE THE HOST DOES NOTHING MORE** for the call: a hosted
	## function the Roc calls once one has failed answers empty,
	## `Err(Failed)`, `NotServing` or "failed", writes nothing, and the host
	## returns the failure.

	## The member's own id.
	read_uid! : {} => List(U8)

	## The request's time, in Unix seconds: the one time everything it
	## stamps carries (a new conversation's topic is named for its date).
	read_time! : {} => I64

	## **THE ONE MARKDOWN PROCESSOR** (angry-gopher markdown.zig `render`):
	## a message's markdown as the HTML its frame carries. `Failed` when it
	## could not be rendered (the request has failed): never an empty page.
	render! : List(U8) => { html : List(U8), status : [Failed, Rendered] }

	## **A DOC'S LIVE PREVIEW** (metal-vmm QUEUE 290): `render!`'s, and
	## markdown too hostile to render is counted too (webbox's edge counter,
	## `malformed_markdown`), shown as the processor's placeholder.
	render_preview! : List(U8) => { html : List(U8), status : [Failed, Rendered] }

	## **THE SEARCH INDEX TOLD OF A MESSAGE AS IT LANDS** (search_index
	## `noteAppend`): topic `sid` of the conversation whose folder is `dir`
	## under the chat root (Paths.conv_folder). Process-lifetime state, so a
	## primitive. It never fails: an index that cannot take the message
	## drops itself, to be rebuilt, and a folder or topic the host would not
	## join is told nothing.
	index_message! : List(U8), { sid : List(U8), message : Chat.Message } => {}

	## **A CACHE WRITTEN** (a topic's `.count`): the whole file as `bytes`,
	## under the chat root. **NEVER THE REQUEST'S FAILURE**: a cache not
	## written is a miss, recounted (QUEUE 284); the host logs it.
	write_cache! : List(U8), List(U8) => {}

	## **A SURFACE THAT FAILED FOR ONE MEMBER, COUNTED AND SAID** (angry-gopher
	## chat_fanout `fanoutFailed`): `surface` for `member`, with `fault` (as
	## the surface's aside's `End` answered it), on topic `sid` of the
	## conversation keyed `key`.
	## The operator's count and last failure, kept by the host for
	## /admin/host.
	report_fanout_failure! : [Code, Images],
	{
		member : List(U8),
		key : List(U8),
		sid : List(U8),
		fault : U16,
	} => {}

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

	## **AN UPLOAD SERVED** (metal-vmm QUEUE 291): the file at `path` under
	## the chat root (checked as `read!`'s is), `size` bytes when the Roc
	## looked, typed `content_type`; `Whole`, the bytes `first` to `last`
	## (`Range`, a 206), or a range it cannot serve (`Unsatisfiable`, a 416).
	## The host answers it, a file too big to read whole streamed. `Gone`
	## when the file went since the Roc's look: nothing is answered.
	serve_upload! : {
		first : U64,
		last : U64,
		size : U64,
		content_type : List(U8),
		path : List(U8),
		part : [
			Range,
			Unsatisfiable,
			Whole,
		],
	} => [Gone, Served]

	## **AN UPLOAD'S FORM READ** (metal-vmm QUEUE 292): the request's
	## multipart body read to the largest upload's limit, its `file` part
	## found and its type sniffed from its first bytes; the host holds the
	## bytes, never handed to Roc. `Read`: the file's `size`, the extension
	## its bytes say (`ext`) and the name the client gave it (`filename`, as
	## sent); `NoFile`: no multipart form, or none with a file;
	## `Unsupported`: a file of a type the chat takes not; `Answered`: the
	## host answered (a body too big) or failed.
	read_upload! : {} => {
		size : U64,
		ext : List(U8),
		filename : List(U8),
		status : [
			Answered,
			NoFile,
			Read,
			Unsupported,
		],
	}

	## **AN UPLOAD REFUSED** as the client's mistake, counted on webbox's
	## edge counter (`Malformed`: malformed_multipart, a 400; `TooLarge`:
	## body_too_large, a 413) and answered `message`.
	refuse_upload! : [Malformed, TooLarge], List(U8) => {}

	## **THE MEMBER'S ALLOWANCE SPENT** by `size` bytes, if it holds them
	## (`Reserved`), else nothing spent (`Refused`); `Failed` when the
	## allowance would not read (the request has failed).
	reserve_upload! : U64 => [
		Failed,
		Refused,
		Reserved,
	]

	## **THE UPLOAD STORED** in the folder `folder` under the chat root
	## (checked as `read!`'s is), by a fresh name of 32 hex digits and the
	## extension `ext`: that name. `Failed` when it could not be stored (the
	## request has failed, and the bytes reserved are given back).
	store_upload! : List(U8), List(U8) => { name : List(U8), status : [Failed, Stored] }

	## **A TOPIC'S BUNDLE, A FILE AT A TIME** (metal-vmm QUEUE 291): the file
	## at `path` under the chat root (checked as `read!`'s is) added to the
	## bundle the host holds as the entry `name`. `Failed` when it would not
	## read (the request has failed).
	bundle_add! : List(U8), List(U8) => Try({}, [Failed])

	## **THE BUNDLE SERVED**: the files added, a gzipped tar, answered as the
	## attachment `<name>.tar.gz`.
	serve_bundle! : List(U8) => {}

	## **A STATIC SCRIPT SERVED**: the script `name` of the host's table (the
	## chat client's bundles) answered as webbox serves every embedded file,
	## its hash its ETag and its cache rule. `Missing` when the table has no
	## script of the name: nothing is answered.
	serve_script! : List(U8) => [Missing, Served]

	## Whether markdown is hostile: `Fine`; `Refused`, the host having refused it
	## (webbox's edge counter and its 400, saying `refusal`, the Roc's words);
	## or `Failed`, the check itself.
	check_hostile! : List(U8),
	List(U8) => [
		Fine,
		Refused,
		Failed,
	]
}
