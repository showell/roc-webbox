## **THE CHAT'S ONE WAY TO THE DISK**: every file primitive the chat calls
## is called here, on a path Paths.roc made (tools/roc_hunt's `fs_bypass`
## flags a call anywhere else).
import pf.Host
import Paths

Files := [].{

	## Host.read!'s answer, **TEXT AT THE DOOR**: the file's text, or nothing
	## there (`Missing`), or a read that failed (`Failed`: the request has
	## failed, and what follows writes nothing). **A FILE THAT IS NOT UTF-8
	## FAILS THE REQUEST** (Host.fail!'s `NotUtf8`, about its path): every
	## file the chat reads is text it wrote, so bytes that are not are a
	## damaged file, never passed on.
	read! : Paths.ChatPath => Try(Str, [Missing, Failed])
	read! = |path| {
		got = Host.read!(path.bytes())
		match decoded(answer(got.status, got.bytes)) {
			Ok(text) => Ok(text)
			Err(Missing) => Err(Missing)
			Err(Failed) => Err(Failed)
			Err(NotUtf8) => {
				Host.fail!(NotUtf8, path.bytes())
				Err(Failed)
			}
		}
	}

	## Host.read!'s answer, **NOT DECODED**: the file's bytes as stored, for
	## a file served as it is (a topic's reactions: its client drops a bad
	## line) or decoded part by part, where one damaged line, entry or
	## block is that part's alone, skipped and counted, never the whole
	## page's (metal-vmm QUEUE 267). `Missing` and `Failed` as `read!`'s.
	read_bytes! : Paths.ChatPath => Try(List(U8), [Missing, Failed])
	read_bytes! = |path| {
		got = Host.read!(path.bytes())
		answer(got.status, got.bytes)
	}

	## Host.read!'s answer as text, **BYTES THAT ARE NOT UTF-8 AN ANSWER**
	## (`NotUtf8`), not the request's failure: for a file one of many, which
	## a listing skips as damaged and counts (a channel's member file).
	read_text! : Paths.ChatPath => Try(
		Str,
		[
			Missing,
			Failed,
			NotUtf8,
		],
	)
	read_text! = |path| {
		got = Host.read!(path.bytes())
		decoded(answer(got.status, got.bytes))
	}

	## Host.stat!: the file's size and its mtime in seconds.
	stat! : Paths.ChatPath => Try({ size : U64, mtime : I64 }, [Missing, Failed])
	stat! = |path| {
		got = Host.stat!(path.bytes())
		match got.status {
			Found => Ok({ size: got.size, mtime: got.mtime })
			Missing => Err(Missing)
			Failed => Err(Failed)
		}
	}

	## **A CACHE'S READ** (Host.read_at!, metal-vmm QUEUE 284): at most `max`
	## bytes from `offset`, or `Miss`. A cache not there and a cache whose
	## read failed are one answer, and neither fails the request: the
	## caller recounts or reads the truth, as for any miss. The chat's
	## caches are the .count sidecar and the last message's window; every
	## other read is the truth's, and its failure fails the request.
	read_cache! : Paths.ChatPath, U64, U64 => Try(List(U8), [Miss])
	read_cache! = |
		path,
		offset,
		max,
	| {
		got = Host.read_at!(
			path.bytes(),
			offset,
			max,
		)
		match got.status {
			Found => Ok(got.bytes)
			Missing | Failed => Err(Miss)
		}
	}

	## **A CACHE WRITTEN** (Host.write_cache!, metal-vmm QUEUE 287): the
	## whole file as `bytes`; one not written is a miss for the next read.
	write_cache! : Paths.ChatPath, List(U8) => {}
	write_cache! = |path, bytes| Host.write_cache!(path.bytes(), bytes)

	## Host.write!: the whole file as `bytes`.
	write! : Paths.ChatPath, List(U8) => Try({}, [Failed])
	write! = |path, bytes| Host.write!(path.bytes(), bytes)

	## Host.remove!: the file gone.
	remove! : Paths.ChatPath => Try({}, [Failed])
	remove! = |path| Host.remove!(path.bytes())

	## Host.append_line!: `line` and a newline appended.
	append_line! : Paths.ChatPath, List(U8) => Try({}, [Failed])
	append_line! = |path, line| Host.append_line!(path.bytes(), line)

	## Host.append_entry!: a feed's entry appended, or failed with its fault.
	append_entry! : Paths.ChatPath,
	List(U8),
	List(U8) => {
		fault : U16,
		status : [Appended, Failed],
	}
	append_entry! = |
		path,
		separator,
		entry,
	| Host.append_entry!(
		path.bytes(),
		separator,
		entry,
	)

	## Host.serve_file!: the host loads the file and serves its bytes as the answer
	## (Chat.served_plain), so Roc never copies a large transcript. `Serving`
	## when it loaded; `NotServing` when the file is not there or the read
	## failed: the host answers both as one.
	serve_file! : Paths.ChatPath => [Serving, NotServing]
	serve_file! = |path| Host.serve_file!(path.bytes())

	## Host.serve_rendered!: the host loads the file, renders it as the server's own
	## markdown, and serves that inside the page (Chat.served_html). `Serving`
	## when it did; `NotServing` when the file is not there, or the read or
	## the render failed: the host answers them as one.
	serve_rendered! : Paths.ChatPath => [Serving, NotServing]
	serve_rendered! = |path| Host.serve_rendered!(path.bytes())

	## Host.list!'s answer as one tag: the folder's entries, nothing there,
	## or a listing that failed (the request has failed). **MISSING AND
	## FAILED ARE NEVER ONE ANSWER** here; a caller may hold both empty.
	## **AN ENTRY'S NAME IS TEXT AT THE DOOR**: one whose name is not UTF-8
	## names nothing the chat wrote, so it is left out of `entries` and its
	## bytes kept in `not_utf8`, for the caller to count where a counter fits.
	list! : Paths.ChatPath => Try(Listing, [Missing, Failed])
	list! = |path| {
		got = Host.list!(path.bytes())
		answer(got.status, got.entries).map_ok(listing)
	}

	## A listing's entries named in text, and the names that were not.
	Listing : { entries : List(Paths.Entry), not_utf8 : List(List(U8)) }
}

## A read's bytes as text, or `NotUtf8`; `Missing` and `Failed` stay
## themselves.
decoded : Try(List(U8), [Missing, Failed]) -> Try(
	Str,
	[
		Missing,
		Failed,
		NotUtf8,
	],
)
decoded = |got|
	match got {
		Ok(bytes) =>
			match Str.from_utf8(bytes) {
				Ok(text) => Ok(text)
				Err(_) => Err(NotUtf8)
			}
		Err(Missing) => Err(Missing)
		Err(Failed) => Err(Failed)
	}

## **A HOST'S STATUS AND WHAT CAME WITH IT, AS ONE TRY**: `Found` is
## `Ok(got)`; `Missing` and `Failed` carry nothing, and each stays itself.
## read! and list! both answer by it.
answer : [
	Found,
	Missing,
	Failed,
],
a -> Try(a, [Missing, Failed])
answer = |status, got|
	match status {
		Found => Ok(got)
		Missing => Err(Missing)
		Failed => Err(Failed)
	}

listing : List(
	{
		kind : [
			Dir,
			File,
			Other,
		],
		name : List(U8),
	},
) -> Listing
listing = |raw|
	List.fold(
		raw,
		{ entries: [], not_utf8: [] },
		|got, e|
			match Str.from_utf8(e.name) {
				Ok(name) => { ..got, entries: List.append(got.entries, { kind: e.kind, name }) }
				Err(_) => { ..got, not_utf8: List.append(got.not_utf8, e.name) }
			},
	)

# decoded: text, multibyte included; bytes that are not UTF-8 are NotUtf8.
expect decoded(Ok(Str.to_utf8("caf\u(e9)"))) == Ok("caf\u(e9)")
expect decoded(Ok(Str.to_utf8("👍"))) == Ok("👍")
expect decoded(Ok([0x61, 0xff])) == Err(NotUtf8)
expect decoded(Ok([0xc3])) == Err(NotUtf8)
expect decoded(Ok([])) == Ok("")
expect decoded(Err(Missing)) == Err(Missing)
expect decoded(Err(Failed)) == Err(Failed)

# listing: names decoded, multibyte included; a name that is not UTF-8 is
# left out and kept apart.
expect listing([
	{ kind: File, name: Str.to_utf8("caf\u(e9).md") },
	{ kind: File, name: [0x61, 0xff] },
	{ kind: Dir, name: Str.to_utf8("👍") },
]) == {
	entries: [{ kind: File, name: "caf\u(e9).md" }, { kind: Dir, name: "👍" }],
	not_utf8: [[0x61, 0xff]],
}

# read!'s answers: bytes found, empty bytes found (an empty file is there),
# nothing there, a failed read; never one for another.
expect answer(Found, Str.to_utf8("hi")) == Ok(Str.to_utf8("hi"))
expect answer(Found, []) == Ok([])
expect answer(Missing, Str.to_utf8("hi")) == Err(Missing)
expect answer(Failed, Str.to_utf8("hi")) == Err(Failed)
expect answer(Missing, []) != Err(Failed)
expect answer(Failed, []) != Err(Missing)

# list!'s: an empty folder is Ok([]), never Missing; Missing and Failed
# stay apart.
expect answer(
	Found,
	[{ kind: File, name: Str.to_utf8("a.md") }],
) == Ok([{ kind: File, name: Str.to_utf8("a.md") }])
expect answer(
	Found,
	List.drop_first([{ kind: Dir, name: [] }], 1),
) == Ok(List.drop_first([{ kind: Dir, name: [] }], 1))
expect answer(Missing, [{ kind: Dir, name: Str.to_utf8("x") }]) == Err(Missing)
expect answer(Failed, [{ kind: Dir, name: Str.to_utf8("x") }]) == Err(Failed)
