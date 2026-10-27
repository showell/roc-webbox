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
		match got.status {
			Found => Found(got.bytes)
			Missing => Missing
			Failed => Failed
		}
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

	## Host.list!'s answer as one tag: the folder's entries, nothing there,
	## or a listing that failed (the request has failed). **MISSING AND
	## FAILED ARE NEVER ONE ANSWER** here; a caller may hold both empty.
	list! : Paths.ChatPath => [Found(List(Paths.Entry)), Missing, Failed]
	list! = |path| {
		got = Host.list!(Paths.bytes(path))
		match got.status {
			Found => Found(got.entries)
			Missing => Missing
			Failed => Failed
		}
	}
}
