## A TOPIC'S `.count` SIDECAR, AND WHEN IT IS BELIEVED (angry-gopher
## chat_count.zig): "<count> <size>\n", then "<offset> <uid>\n" where the
## last message begins and who sent it. The sidecar is a cache and the
## transcript the truth: each rule here says when the cache may answer (the
## flow that asks them is Last.roc's `messages!`).
import ZigText
import Bytes
import Transcript

Count := [].{

	## Where the last message begins and who sent it, `uid` empty for nobody.
	Last : [Known({ offset : U64, uid : List(U8) }), Unknown]

	Counted : {
		count : U64,
		size : U64,
		last : Last,
	}

	## countBlocks: every block that is not blank, refused ones included, so
	## that no number is given twice.
	count_blocks : List(U8) -> U64
	count_blocks = |raw| List.count_if(
		List.split_on_list(raw, Transcript.sep),
		|p| Bytes.trim(p, Bytes.zig_spaces) != [],
	)

	## numberIn: the N of a `<topic>_<N>` id, or none when the id is not this
	## topic's.
	number_in : List(U8),
	List(U8) -> Try(
		U64,
		[
			NotThisTopic,
			NotANumber,
			TooBig,
		],
	)
	number_in = |id, topic|
		match Bytes.strip_prefix(id, topic) {
			Ok(['_', .. as rest]) => ZigText.parse_u64(rest)
			_ => Err(NotThisTopic)
		}

	## indexOf: the number less one; message 0 is no message.
	index_of : List(U8), List(U8) -> Try(U64, [NoMessage])
	index_of = |id, topic| match number_in(id, topic) {
		Ok(n) if n > 0 => Ok(n - 1)
		_ => Err(NoMessage)
	}

	## parseCount: whole (ending in a newline) or not at all; a first line
	## of exactly two numbers; a second line that does not parse is no
	## last message, the count still good.
	parse : List(U8) -> Try(Counted, [Malformed])
	parse = |raw|
		if List.last(raw) != Ok('\n') {
			Err(Malformed)
		} else {
			match List.split_on(raw, '\n') {
				[
					first,
					second,
					..,
				] =>
					match tokens(first) {
						[c, s] =>
							match (ZigText.parse_u64(c), ZigText.parse_u64(s)) {
								(Ok(count), Ok(size)) => Ok({
									count,
									size,
									last: parse_last(second),
								})
								_ => Err(Malformed)
							}
						_ => Err(Malformed)
					}
				# Bytes that end in a newline split in two at least.
				_ => crash "Count.parse: bytes ending in a newline split into fewer than two lines"
			}
		}

	## countText: what a send writes, nobody as `-`.
	text : U64, U64, Last -> List(U8)
	text = |
		count,
		size,
		last,
	| {
		head = Str.to_utf8("${U64.to_str(count)} ${U64.to_str(size)}\n")
		match last {
			Known(l) => List.join([
				head,
				Str.to_utf8(U64.to_str(l.offset)),
				[' '],
				if l.uid == [] no_uid else l.uid,
				['\n'],
			])
			Unknown => head
		}
	}

	## believedCount: the sidecar's count when the transcript is still the
	## size it was taken at.
	believed : Try(Counted, [Malformed]), U64 -> Try(U64, [NotBelieved])
	believed = |counted, size| match counted {
		Ok(c) if c.size == size => Ok(c.count)
		_ => Err(NotBelieved)
	}

	## recordedAuthor: the record's author, nobody included, when it counted
	## exactly this transcript, in blocks and in bytes.
	recorded_author : Try(Counted, [Malformed]), U64, U64 -> Try(List(U8), [NotRecorded])
	recorded_author = |
		counted,
		blocks,
		size,
	| match counted {
		Ok(
			{
				count,
				size: s,
				last: Known(l),
			},
		) if count == blocks and s == size => Ok(l.uid)
		_ => Err(NotRecorded)
	}

	## Whether the window read filled its buffer (so its last block may be cut).
	Fill : [Full, Partial]

	## Whether the record's count is the window's last block's number.
	Freshness : [Current, Stale]

	## windowLast: the last block of the window read at the record's offset,
	## believed when the window was not full and the block is a message of
	## `topic` numbered at least `count`; the record `Current` when exactly
	## that, `Stale` when the block is past it. A window whose decode fails
	## (`CorruptUid`) fails with it: damaged data is never passed over.
	window_last : U64,
	List(U8),
	Fill,
	List(U8) -> Try(
		{
			msg : Transcript.Msg,
			number : U64,
			record : Freshness,
		},
		[NotBelieved, CorruptUid(List(U8))],
	)
	window_last = |
		count,
		window,
		fill,
		topic,
	|
		if fill == Full {
			Err(NotBelieved)
		} else {
			match List.last(Transcript.decode_file(window)?.messages) {
				Ok(msg) =>
					match number_in(msg.id, topic) {
						Ok(number) if number >= count => Ok({
							msg,
							number,
							record: if number == count Current else Stale,
						})
						_ => Err(NotBelieved)
					}
				Err(_) => Err(NotBelieved)
			}
		}

}

parse_last : List(U8) -> Last
parse_last = |line| match tokens(line) {
	[o, uid] =>
		match ZigText.parse_u64(o) {
			Ok(offset) => Known({ offset, uid: if uid == no_uid [] else uid })
			Err(NotANumber) | Err(TooBig) => Unknown
		}
	_ => Unknown
}

## std.mem.tokenizeScalar on a space: the runs between, none empty.
tokens : List(U8) -> List(List(U8))
tokens = |line| List.keep_if(List.split_on(line, ' '), |t| t != [])

no_uid : List(U8)
no_uid = Str.to_utf8("-")
