## FILES, AS EFFECTS: each call happens when it is made, on the host's store
## (webbox's: FAT's rules for names on every host), under the host's data
## root. A path is relative to that root; one that would leave it fails.
##
## A file that is not there and a file that could not be read are two
## answers, never one: a list read as empty because the disk failed would be
## written back empty.
File := [].{
	## What the host answers for a read: `status` 0 with the file's text,
	## 1 when there is no such file, 2 when it could not be read (`text` the
	## host's reason).
	read_raw! : Str => { status : U8, text : Str }

	## Writes the whole file, its folders made as needed: "" when it was,
	## else the host's reason.
	write_raw! : Str, Str => Str

	## Removes the file (one not there is gone already): "" when it is,
	## else the host's reason.
	delete_raw! : Str => Str

	## The file's text, or why not.
	read! : Str => Try(Str, [NotFound(Str), ReadFailed(Str)])
	read! = |path| {
		got = File.read_raw!(path)
		if got.status == 0 {
			Ok(got.text)
		} else if got.status == 1 {
			Err(NotFound(path))
		} else {
			Err(ReadFailed("${path}: ${got.text}"))
		}
	}

	## Writes the whole file, or says why it could not.
	write! : Str, Str => Try({}, [WriteFailed(Str)])
	write! = |path, text| {
		why = File.write_raw!(path, text)
		if Str.is_empty(why) Ok({}) else Err(WriteFailed("${path}: ${why}"))
	}

	## Removes the file, or says why it could not.
	delete! : Str => Try({}, [DeleteFailed(Str)])
	delete! = |path| {
		why = File.delete_raw!(path)
		if Str.is_empty(why) Ok({}) else Err(DeleteFailed("${path}: ${why}"))
	}
}
