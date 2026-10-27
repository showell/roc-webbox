## **THE CHAT'S ONE WAY TO THE DISK**: every file primitive the chat calls
## is called here, on a path Paths.roc made (tools/roc_hunt's `fs_bypass`
## flags a call anywhere else).
import pf.Host
import Paths

Files := [].{

	## Host.read!'s answer: the file's bytes, or nothing there (`Missing`), or
	## a read that failed (`Failed`: the request has failed, and what follows
	## writes nothing).
	read! : Paths.ChatPath => Try(List(U8), [Missing, Failed])
	read! = |path| {
		got = Host.read!(Paths.bytes(path))
		answer(got.status, got.bytes)
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

	## Host.raw!: whether the file is there, the host holding its bytes for
	## the answer (Chat.held_plain); false when the read failed, too.
	held_raw! : Paths.ChatPath => Bool
	held_raw! = |path| Host.raw!(Paths.bytes(path))

	## Host.links!: whether the file is there, the host holding it rendered
	## as the server's own markdown for the answer (Chat.held_html); false
	## when the read or the render failed, too.
	held_rendered! : Paths.ChatPath => Bool
	held_rendered! = |path| Host.links!(Paths.bytes(path))

	## Host.list!'s answer as one tag: the folder's entries, nothing there,
	## or a listing that failed (the request has failed). **MISSING AND
	## FAILED ARE NEVER ONE ANSWER** here; a caller may hold both empty.
	list! : Paths.ChatPath => Try(List(Paths.Entry), [Missing, Failed])
	list! = |path| {
		got = Host.list!(Paths.bytes(path))
		answer(got.status, got.entries)
	}
}

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
