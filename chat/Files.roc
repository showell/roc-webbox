## **THE CHAT'S ONE WAY TO THE DISK**: every file primitive the chat calls
## is called here, on a path Paths.roc made (tools/roc_hunt's `fs_bypass`
## flags a call anywhere else).
import pf.Host
import Paths

Files := [].{

	## Host.read!'s answer as one tag: the file's bytes, nothing there, or a
	## read that failed (the request has failed: what follows writes nothing).
	read! : Paths.ChatPath => [Found(List(U8)), Missing, Failed]
	read! = |path| {
		got = Host.read!(Paths.bytes(path))
		answer(got.status, got.bytes)
	}

	## **A HOST'S STATUS AND WHAT CAME WITH IT, AS ONE TAG**: `Found` carries
	## `got`; `Missing` and `Failed` carry nothing, and each stays itself.
	## read! and list! both answer by it.
	answer : [Found, Missing, Failed], a -> [Found(a), Missing, Failed]
	answer = |status, got|
		match status {
			Found => Found(got)
			Missing => Missing
			Failed => Failed
		}

	## Host.write!: the whole file as `bytes`; false when it failed.
	write! : Paths.ChatPath, List(U8) => Bool
	write! = |path, bytes| Host.write!(Paths.bytes(path), bytes)

	## Host.remove!: the file gone; false when it failed.
	remove! : Paths.ChatPath => Bool
	remove! = |path| Host.remove!(Paths.bytes(path))

	## Host.append_line!: `line` and a newline appended; false when it failed.
	append_line! : Paths.ChatPath, List(U8) => Bool
	append_line! = |path, line| Host.append_line!(Paths.bytes(path), line)

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
	list! : Paths.ChatPath => [Found(List(Paths.Entry)), Missing, Failed]
	list! = |path| {
		got = Host.list!(Paths.bytes(path))
		answer(got.status, got.entries)
	}
}

# read!'s answers: bytes found, empty bytes found (an empty file is there),
# nothing there, a failed read; never one for another.
expect Files.answer(Found, Str.to_utf8("hi")) == Found(Str.to_utf8("hi"))
expect Files.answer(Found, []) == Found([])
expect Files.answer(Missing, Str.to_utf8("hi")) == Missing
expect Files.answer(Failed, Str.to_utf8("hi")) == Failed
expect Files.answer(Missing, []) != Failed
expect Files.answer(Failed, []) != Missing

# list!'s: an empty folder is Found([]), never Missing; Missing and Failed
# stay apart.
expect Files.answer(Found, [{ kind: File, name: Str.to_utf8("a.md") }]) == Found([{ kind: File, name: Str.to_utf8("a.md") }])
expect Files.answer(Found, List.drop_first([{ kind: Dir, name: [] }], 1)) == Found(List.drop_first([{ kind: Dir, name: [] }], 1))
expect Files.answer(Missing, [{ kind: Dir, name: Str.to_utf8("x") }]) == Missing
expect Files.answer(Failed, [{ kind: Dir, name: Str.to_utf8("x") }]) == Failed
