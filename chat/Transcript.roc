## A TRANSCRIPT'S BLOCKS, DECODED AND ENCODED (angry-gopher chat_codec.zig):
## blocks joined by `sep` (a blank line, 13 hyphens, a newline), each an
## `MSG_<id>` line, `key: value` headers to a blank line, then the body,
## with a body line that would read as the separator escaped by one
## backslash. Pure, on bytes.
import Bytes
import Uid

Transcript := [].{

	## A message: every field but its author the bytes they were.
	Msg : {
		id : List(U8),
		from : List(U8),
		at : List(U8),
		uid : Author,
		markdown : List(U8),
	}

	## Who sent a message: a block from before `uid:` was written, or one
	## whose `uid:` line is empty, is `Unattributed`.
	Author : [By(Uid), Unattributed]

	## A block as it reads, its `uid:` the bytes after it, empty when none.
	Block : {
		id : List(U8),
		from : List(U8),
		at : List(U8),
		uid : List(U8),
		markdown : List(U8),
	}

	## decodeChatFile: the messages, and how many blocks were refused (not
	## messages: no id, author or date). A piece that is only whitespace is
	## no block and not counted. **A MESSAGE WHOSE `uid:` IS NOT EMPTY AND
	## NOT A CANONICAL UID FAILS THE FILE** (`CorruptUid`, its bytes): the
	## store writes only canonical uids, so such a line is damaged data, and
	## skipping its block would renumber every message after it.
	decode_file : List(U8) -> Try({ messages : List(Msg), refused : U64 }, [CorruptUid(List(U8))])
	decode_file = |data| {
		d = decode_blocks(data)
		messages = List.map_try(d.blocks, message_of)?
		Ok({ messages, refused: List.len(d.refused) })
	}

	## decodeChatFile's reading, before any author is decoded: each message
	## block as it reads (its `uid:` the bytes there, whatever they are),
	## and the first line of each block refused. A piece that is only
	## whitespace is neither. **A STREAM'S BACKLOG READS THESE** (main.roc
	## `replay!`): it sends what the transcript holds, as the Zig did.
	decode_blocks : List(U8) -> { blocks : List(Block), refused : List(List(U8)) }
	decode_blocks = |data|
		List.fold(
			List.split_on_list(data, sep),
			{ blocks: [], refused: [] },
			|acc, piece|
				if Bytes.trim(piece, Bytes.zig_spaces) == [] {
					acc
				} else {
					b = decode_block(piece)
					if is_message(b) {
						{ ..acc, blocks: List.append(acc.blocks, b) }
					} else {
						{ ..acc, refused: List.append(acc.refused, line_at(piece, 0)) }
					}
				},
		)

	## chatStoredForm: what message `index` adds to the file, its block after
	## `sep` for every message but the first.
	stored_form : U64, Msg -> List(U8)
	stored_form = |index, m| if index == 0 encode_block(m) else List.concat(sep, encode_block(m))

	## The separator, and the 13 hyphens a body line must not be alone.
	sep : List(U8)
	sep = Str.to_utf8("\n\n-------------\n")

	## A body's lines escaped as a block's are (chat_codec escapeBodyLine),
	## so none is the 13 hyphens alone; the Code feed's bodies too.
	escape_body : List(U8) -> List(U8)
	escape_body = |body| if Bytes.find(
		body,
		{ needle: dashes },
	) == Err(NotFound) body else Bytes.join_lines(
		List.map(
			List.split_on(body, '\n'),
			escape_line,
		),
	)

	## `escape_body` undone (chat_codec unescapeBodyLine). A body with no
	## backslash before the dashes has no escaped line, and is the bytes it
	## was.
	unescape_body : List(U8) -> List(U8)
	unescape_body = |body| if Bytes.find(
		body,
		{ needle: escaped_dashes },
	) == Err(NotFound) body else Bytes.join_lines(
		List.map(
			List.split_on(body, '\n'),
			unescape_line,
		),
	)
}

## A message block with its author decoded: an empty `uid:` is nobody.
message_of : Block -> Try(Msg, [CorruptUid(List(U8))])
message_of = |b| {
	uid = if b.uid == [] Unattributed else By(Uid.from_utf8(b.uid).map_err(|_| CorruptUid(b.uid))?)
	Ok({
		id: b.id,
		from: b.from,
		at: b.at,
		uid,
		markdown: b.markdown,
	})
}

is_message : Block -> Bool
is_message = |m| m.id != [] and m.from != [] and m.at != []

## One block: an optional `MSG_` line, headers to the first blank line
## (`from`, `date`, `uid` kept, the last of each, the rest passed over),
## then the body, each line unescaped. Lines are found by offset and
## kept as slices of the piece: nothing is copied but an escaped body.
decode_block : List(U8) -> Block
decode_block = |piece| {
	first = line_at(piece, 0)
	(id, start) = match Bytes.strip_prefix(first, msg_prefix) {
		Ok(rest) => (rest, List.len(first) + 1)
		Err(NoMatch) => ([], 0)
	}
	headers(
		piece,
		{
			at: start,
			block: {
				id,
				from: [],
				at: [],
				uid: [],
				markdown: [],
			},
		},
	)
}

msg_prefix : List(U8)
msg_prefix = Str.to_utf8("MSG_")

## The line of `piece` that begins at `at`, without its newline.
line_at : List(U8), U64 -> List(U8)
line_at = |piece, at| List.sublist(
	piece,
	{
		start: at,
		len: Bytes.count_while(piece, { keep: |c| c != '\n', at: at + 0 }) - at,
	},
)

## The header lines from offset `at` to the blank one, then the body:
## everything after the blank line (none when there is no blank line).
headers : List(U8), { at : U64, block : Block } -> Block
headers = |piece, { at, block: m }|
	if at > List.len(piece) {
		m
	} else {
		l = line_at(piece, at)
		if l == [] {
			{ ..m, markdown: Transcript.unescape_body(List.drop_first(piece, at + 1)) }
		} else {
			next = match Bytes.cut_seq(l, Str.to_utf8(": ")) {
				Ok((k, v)) =>
					match k {
						[
							'f',
							'r',
							'o',
							'm',
						] => { ..m, from: v }
						[
							'd',
							'a',
							't',
							'e',
						] => { ..m, at: v }
						[
							'u',
							'i',
							'd',
						] => { ..m, uid: v }
						_ => m
					}
				Err(NotFound) => m
			}
			headers(piece, { at: at + List.len(l) + 1, block: next })
		}
	}

escaped_dashes : List(U8)
escaped_dashes = List.prepend(dashes, '\\')

## encodeChatBlock: `MSG_`, `from:`, `date:`, `uid:` when known, a blank
## line, the body with each line escaped.
encode_block : Msg -> List(U8)
encode_block = |m| {
	body = Transcript.escape_body(m.markdown)
	head = List.join([
		Str.to_utf8("MSG_"),
		m.id,
		Str.to_utf8("\nfrom: "),
		m.from,
		Str.to_utf8("\ndate: "),
		m.at,
	])
	uid = match m.uid {
		By(u) => Str.to_utf8("\nuid: ${u.to_str()}")
		Unattributed => []
	}
	List.join([
		head,
		uid,
		Str.to_utf8("\n\n"),
		body,
	])
}

dashes : List(U8)
dashes = Str.to_utf8("-------------")

## A line of one or more backslashes then exactly the dashes loses one.
unescape_line : List(U8) -> List(U8)
unescape_line = |line| {
	k = Bytes.count_while(line, { keep: |x| x == '\\', at: 0 })
	if k >= 1 and List.drop_first(line, k) == dashes List.drop_first(line, 1) else line
}

## A line of any backslashes then exactly the dashes gains one.
escape_line : List(U8) -> List(U8)
escape_line = |line| {
	k = Bytes.count_while(line, { keep: |x| x == '\\', at: 0 })
	if List.drop_first(line, k) == dashes List.prepend(line, '\\') else line
}

# An empty `uid:` line is nobody; a canonical one its author; any other
# fails the file, never skipped.
expect Transcript.decode_file(Str.to_utf8("MSG_t_1\nfrom: S\ndate: d\nuid: \n\nhi")).map_ok(|d| d.messages.map(|m| m.uid)) == Ok([Unattributed])
expect Transcript.decode_file(Str.to_utf8("MSG_t_1\nfrom: S\ndate: d\n\nhi")).map_ok(|d| d.messages.map(|m| m.uid)) == Ok([Unattributed])
expect Transcript.decode_file(Str.to_utf8("MSG_t_1\nfrom: S\ndate: d\nuid: 17\n\nhi")).map_ok(|d| d.messages.map(|m| m.uid)) == Uid.from_str("17").map_ok(|u| [By(u)]).map_err(|_| CorruptUid([]))
expect Transcript.decode_file(Str.to_utf8("MSG_t_1\nfrom: S\ndate: d\nuid: 07\n\nhi")) == Err(CorruptUid(Str.to_utf8("07")))
