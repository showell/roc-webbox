## A TRANSCRIPT'S BLOCKS, DECODED AND ENCODED (angry-gopher chat_codec.zig):
## blocks joined by `sep` (a blank line, 13 hyphens, a newline), each an
## `MSG_<id>` line, `key: value` headers to a blank line, then the body,
## with a body line that would read as the separator escaped by one
## backslash. Pure, on bytes.
import Bytes
import ZigText

Transcript := [].{

	## A decoded block: every field the bytes they were, `uid` empty for a
	## block from before it was written.
	Msg : { id : List(U8), from : List(U8), at : List(U8), uid : List(U8), markdown : List(U8) }

	## decodeChatFile: the messages, and how many blocks were refused (not
	## messages: no id, author or date). A piece that is only whitespace is
	## no block and not counted.
	decode_file : List(U8) -> { messages : List(Msg), refused : U64 }
	decode_file = |data|
		List.fold(
			Bytes.split_seq(data, sep),
			{ messages: [], refused: 0 },
			|acc, piece|
				if ZigText.trim(piece) == [] {
					acc
				} else {
					m = decode_block(piece)
					if is_message(m) {
						{ ..acc, messages: List.append(acc.messages, m) }
					} else {
						{ ..acc, refused: acc.refused + 1 }
					}
				},
		)

	is_message : Msg -> Bool
	is_message = |m| m.id != [] and m.from != [] and m.at != []

	## One block: an optional `MSG_` line, headers to the first blank line
	## (`from`, `date`, `uid` kept, the last of each, the rest passed over),
	## then the body, each line unescaped. Lines are found by offset and
	## kept as slices of the piece: nothing is copied but an escaped body.
	decode_block : List(U8) -> Msg
	decode_block = |piece| {
		first = line_at(piece, 0)
		(id, start) = match Bytes.strip_prefix(first, msg_prefix) {
			Ok(rest) => (rest, List.len(first) + 1)
			Err(NoMatch) => ([], 0)
		}
		headers(piece, start, { id, from: [], at: [], uid: [], markdown: [] })
	}

	msg_prefix : List(U8)
	msg_prefix = Str.to_utf8("MSG_")

	## The line of `piece` that begins at `at`, without its newline.
	line_at : List(U8), U64 -> List(U8)
	line_at = |piece, at| List.sublist(piece, { start: at, len: line_len(piece, at, 0) })

	line_len : List(U8), U64, U64 -> U64
	line_len = |piece, at, n| match List.get(piece, at + n) {
		Ok(c) if c != '\n' => line_len(piece, at, n + 1)
		_ => n
	}

	## The header lines from offset `at` to the blank one, then the body:
	## everything after the blank line (none when there is no blank line).
	headers : List(U8), U64, Msg -> Msg
	headers = |piece, at, m|
		if at > List.len(piece) {
			m
		} else {
			l = line_at(piece, at)
			if l == [] {
				{ ..m, markdown: unescape_body(List.drop_first(piece, at + 1)) }
			} else {
				next = match Bytes.cut_seq(l, Str.to_utf8(": ")) {
					Ok((k, v)) =>
						match k {
							['f', 'r', 'o', 'm'] => { ..m, from: v }
							['d', 'a', 't', 'e'] => { ..m, at: v }
							['u', 'i', 'd'] => { ..m, uid: v }
							_ => m
						}
					Err(NotFound) => m
				}
				headers(piece, at + List.len(l) + 1, next)
			}
		}

	## A body with no backslash before the dashes has no escaped line, and
	## is the bytes it was.
	unescape_body : List(U8) -> List(U8)
	unescape_body = |body|
		if Bytes.find(body, escaped_dashes, 0) == Err(NotFound) body else Bytes.join_lines(List.map(Bytes.split_byte(body, '\n'), unescape_line))

	escaped_dashes : List(U8)
	escaped_dashes = List.prepend(dashes, '\\')

	## chatStoredForm: what message `index` adds to the file, its block after
	## `sep` for every message but the first.
	stored_form : U64, Msg -> List(U8)
	stored_form = |index, m| if index == 0 encode_block(m) else List.concat(sep, encode_block(m))

	## encodeChatBlock: `MSG_`, `from:`, `date:`, `uid:` when known, a blank
	## line, the body with each line escaped.
	encode_block : Msg -> List(U8)
	encode_block = |m| {
		body = if Bytes.find(m.markdown, dashes, 0) == Err(NotFound) m.markdown else Bytes.join_lines(List.map(Bytes.split_byte(m.markdown, '\n'), escape_line))
		head = List.join([Str.to_utf8("MSG_"), m.id, Str.to_utf8("\nfrom: "), m.from, Str.to_utf8("\ndate: "), m.at])
		uid = if m.uid == [] [] else List.concat(Str.to_utf8("\nuid: "), m.uid)
		List.join([head, uid, Str.to_utf8("\n\n"), body])
	}

	## The separator, and the 13 hyphens a body line must not be alone.
	sep : List(U8)
	sep = Str.to_utf8("\n\n-------------\n")

	dashes : List(U8)
	dashes = Str.to_utf8("-------------")

	## A line of one or more backslashes then exactly the dashes loses one.
	unescape_line : List(U8) -> List(U8)
	unescape_line = |line| {
		k = Bytes.leading(line, '\\', 0)
		if k >= 1 and List.drop_first(line, k) == dashes List.drop_first(line, 1) else line
	}

	## A line of any backslashes then exactly the dashes gains one.
	escape_line : List(U8) -> List(U8)
	escape_line = |line| {
		k = Bytes.leading(line, '\\', 0)
		if List.drop_first(line, k) == dashes List.prepend(line, '\\') else line
	}

}
