## A TOPIC'S `.count` SIDECAR, AND WHEN IT IS BELIEVED (angry-gopher
## chat_count.zig): "<count> <size>\n", then "<offset> <uid>\n" where the
## last message begins and who sent it. The sidecar is a cache and the
## transcript the truth: each rule here says when the cache may answer.
import ZigText
import Bytes
import Transcript

Count := [].{
	## Where the last message begins and who sent it, `uid` empty for nobody.
	Last : [Known({ offset : U64, uid : List(U8) }), Unknown]

	Counted : { count : U64, size : U64, last : Last }

	## countBlocks: every block that is not blank, refused ones included, so
	## that no number is given twice.
	count_blocks : List(U8) -> U64
	count_blocks = |raw| List.count_if(Bytes.split_seq(raw, Transcript.sep), |p| ZigText.trim(p) != [])

	## numberIn: the N of a `<sid>_<N>` id, or none when the id is not this
	## topic's.
	number_in : List(U8), List(U8) -> Try(U64, [None])
	number_in = |id, sid|
		match Bytes.strip_prefix(id, sid) {
			Ok(['_', .. as rest]) => ZigText.parse_u64(rest)
			_ => Err(None)
		}

	## indexOf: the number less one; message 0 is no message.
	index_of : List(U8), List(U8) -> Try(U64, [None])
	index_of = |id, sid| match number_in(id, sid) {
		Ok(n) if n > 0 => Ok(n - 1)
		_ => Err(None)
	}

	## parseCount: whole (ending in a newline) or not at all; a first line
	## of exactly two numbers; a second line that does not parse is no
	## last message, the count still good.
	parse : List(U8) -> Try(Counted, [None])
	parse = |raw|
		if List.last(raw) != Ok('\n') {
			Err(None)
		} else {
			lines = Bytes.split_byte(raw, '\n')
			match tokens(List.first(lines) ?? []) {
				[c, s] =>
					match (ZigText.parse_u64(c), ZigText.parse_u64(s)) {
						(Ok(count), Ok(size)) => Ok({ count, size, last: parse_last(List.get(lines, 1) ?? []) })
						_ => Err(None)
					}
				_ => Err(None)
			}
		}

	parse_last : List(U8) -> Last
	parse_last = |line| match tokens(line) {
		[o, uid] =>
			match ZigText.parse_u64(o) {
				Ok(offset) => Known({ offset, uid: if uid == no_uid [] else uid })
				Err(None) => Unknown
			}
		_ => Unknown
	}

	## std.mem.tokenizeScalar on a space: the runs between, none empty.
	tokens : List(U8) -> List(List(U8))
	tokens = |line| List.keep_if(Bytes.split_byte(line, ' '), |t| t != [])

	## countText: what a send writes, nobody as `-`.
	text : U64, U64, Last -> List(U8)
	text = |count, size, last| {
		head = Str.to_utf8("${U64.to_str(count)} ${U64.to_str(size)}\n")
		match last {
			Known(l) => List.join([head, Str.to_utf8(U64.to_str(l.offset)), [' '], if l.uid == [] no_uid else l.uid, ['\n']])
			Unknown => head
		}
	}

	no_uid : List(U8)
	no_uid = Str.to_utf8("-")

	## believedCount: the sidecar's count when the transcript is still the
	## size it was taken at.
	believed : Try(Counted, [None]), U64 -> Try(U64, [None])
	believed = |counted, size| match counted {
		Ok(c) if c.size == size => Ok(c.count)
		_ => Err(None)
	}

	## recordedAuthor: the record's author, nobody included, when it counted
	## exactly this transcript, in blocks and in bytes.
	recorded_author : Try(Counted, [None]), U64, U64 -> Try(List(U8), [None])
	recorded_author = |counted, blocks, size| match counted {
		Ok({ count, size: s, last: Known(l) }) if count == blocks and s == size => Ok(l.uid)
		_ => Err(None)
	}

	## windowLast: the last block of the window read at the record's offset,
	## believed when the window was not full and the block is a message of
	## `sid` numbered at least `count`; `current` when exactly that.
	window_last : U64, List(U8), Bool, List(U8) -> Try({ msg : Transcript.Msg, number : U64, current : Bool }, [None])
	window_last = |count, window, full, sid|
		if full {
			Err(None)
		} else {
			match List.last(Transcript.decode_file(window).messages) {
				Ok(msg) =>
					match number_in(msg.id, sid) {
						Ok(number) if number >= count => Ok({ msg, number, current: number == count })
						_ => Err(None)
					}
				Err(_) => Err(None)
			}
		}
}
