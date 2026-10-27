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
		got = Host.read!(Paths.bytes(path))
		match decoded(answer(got.status, got.bytes)) {
			Ok(text) => Ok(text)
			Err(Missing) => Err(Missing)
			Err(Failed) => Err(Failed)
			Err(NotUtf8) => {
				Host.fail!(NotUtf8, Paths.bytes(path))
				Err(Failed)
			}
		}
	}

	## A read's bytes as text, or `NotUtf8`; `Missing` and `Failed` stay
	## themselves.
	decoded : Try(List(U8), [Missing, Failed]) -> Try(Str, [Missing, Failed, NotUtf8])
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
	answer : [Found, Missing, Failed], a -> Try(a, [Missing, Failed])
	answer = |status, got|
		match status {
			Found => Ok(got)
			Missing => Err(Missing)
			Failed => Err(Failed)
		}

	## Host.write!: the whole file as `bytes`.
	write! : Paths.ChatPath, List(U8) => Try({}, [Failed])
	write! = |path, bytes| if Host.write!(Paths.bytes(path), bytes) Ok({}) else Err(Failed)

	## Host.remove!: the file gone.
	remove! : Paths.ChatPath => Try({}, [Failed])
	remove! = |path| if Host.remove!(Paths.bytes(path)) Ok({}) else Err(Failed)

	## Host.append_line!: `line` and a newline appended.
	append_line! : Paths.ChatPath, List(U8) => Try({}, [Failed])
	append_line! = |path, line| if Host.append_line!(Paths.bytes(path), line) Ok({}) else Err(Failed)

	## Host.append_entry!: a feed's entry appended, or failed with its fault.
	append_entry! : Paths.ChatPath, List(U8), List(U8) => { fault : U16, status : [Appended, Failed] }
	append_entry! = |path, separator, entry| Host.append_entry!(Paths.bytes(path), separator, entry)

	## Host.raw!: `Held` when the file is there, the host holding its bytes for
	## the answer (Chat.held_plain); `NotHeld` when it is not, or the read
	## failed: the host answers both as one.
	held_raw! : Paths.ChatPath => [Held, NotHeld]
	held_raw! = |path| if Host.raw!(Paths.bytes(path)) Held else NotHeld

	## Host.links!: `Held` when the file is there, the host holding it rendered
	## as the server's own markdown for the answer (Chat.held_html); `NotHeld`
	## when it is not, or the read or the render failed: the host answers
	## them as one.
	held_rendered! : Paths.ChatPath => [Held, NotHeld]
	held_rendered! = |path| if Host.links!(Paths.bytes(path)) Held else NotHeld

	## Host.list!'s answer as one tag: the folder's entries, nothing there,
	## or a listing that failed (the request has failed). **MISSING AND
	## FAILED ARE NEVER ONE ANSWER** here; a caller may hold both empty.
	## **AN ENTRY'S NAME IS TEXT AT THE DOOR**: one whose name is not UTF-8
	## names nothing the chat wrote, so it is left out of `entries` and its
	## bytes kept in `not_utf8`, for the caller to count where a counter fits.
	list! : Paths.ChatPath => Try(Listing, [Missing, Failed])
	list! = |path| {
		got = Host.list!(Paths.bytes(path))
		answer(got.status, got.entries).map_ok(listing)
	}

	## A listing's entries named in text, and the names that were not.
	Listing : { entries : List(Paths.Entry), not_utf8 : List(List(U8)) }

	listing : List({ kind : [Dir, File, Other], name : List(U8) }) -> Listing
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
}

# decoded: text, multibyte included; bytes that are not UTF-8 are NotUtf8.
expect Files.decoded(Ok(Str.to_utf8("caf\u(e9)"))) == Ok("caf\u(e9)")
expect Files.decoded(Ok(Str.to_utf8("👍"))) == Ok("👍")
expect Files.decoded(Ok([0x61, 0xff])) == Err(NotUtf8)
expect Files.decoded(Ok([0xc3])) == Err(NotUtf8)
expect Files.decoded(Ok([])) == Ok("")
expect Files.decoded(Err(Missing)) == Err(Missing)
expect Files.decoded(Err(Failed)) == Err(Failed)

# listing: names decoded, multibyte included; a name that is not UTF-8 is
# left out and kept apart.
expect Files.listing([{ kind: File, name: Str.to_utf8("caf\u(e9).md") }, { kind: File, name: [0x61, 0xff] }, { kind: Dir, name: Str.to_utf8("👍") }]) == { entries: [{ kind: File, name: "caf\u(e9).md" }, { kind: Dir, name: "👍" }], not_utf8: [[0x61, 0xff]] }

# read!'s answers: bytes found, empty bytes found (an empty file is there),
# nothing there, a failed read; never one for another.
expect Files.answer(Found, Str.to_utf8("hi")) == Ok(Str.to_utf8("hi"))
expect Files.answer(Found, []) == Ok([])
expect Files.answer(Missing, Str.to_utf8("hi")) == Err(Missing)
expect Files.answer(Failed, Str.to_utf8("hi")) == Err(Failed)
expect Files.answer(Missing, []) != Err(Failed)
expect Files.answer(Failed, []) != Err(Missing)

# list!'s: an empty folder is Ok([]), never Missing; Missing and Failed
# stay apart.
expect Files.answer(Found, [{ kind: File, name: Str.to_utf8("a.md") }]) == Ok([{ kind: File, name: Str.to_utf8("a.md") }])
expect Files.answer(Found, List.drop_first([{ kind: Dir, name: [] }], 1)) == Ok(List.drop_first([{ kind: Dir, name: [] }], 1))
expect Files.answer(Missing, [{ kind: Dir, name: Str.to_utf8("x") }]) == Err(Missing)
expect Files.answer(Failed, [{ kind: Dir, name: Str.to_utf8("x") }]) == Err(Failed)
