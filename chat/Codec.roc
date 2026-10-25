## A TRANSCRIPT'S BLOCKS, DECODED AND ENCODED (angry-gopher chat_codec.zig):
## blocks joined by `sep` (a blank line, 13 hyphens, a newline), each an
## `MSG_<id>` line, `key: value` headers to a blank line, then the body,
## with a body line that would read as the separator escaped by one
## backslash. Pure, on bytes.
import ZigText

Codec := [].{
	## A decoded block: every field the bytes they were, `uid` empty for a
	## block from before it was written.
	Msg : { id : List(U8), from : List(U8), at : List(U8), uid : List(U8), markdown : List(U8) }

	## decodeChatFile: the messages, and how many blocks were refused (not
	## messages: no id, author or date). A piece that is only whitespace is
	## no block and not counted.
	decode_file : List(U8) -> { messages : List(Msg), refused : U64 }
	decode_file = |data|
		List.fold(split_seq(data, sep), { messages: [], refused: 0 }, |acc, piece|
			if ZigText.trim(piece) == [] {
				acc
			} else {
				m = decode_block(piece)
				if is_message(m) {
					{ ..acc, messages: List.append(acc.messages, m) }
				} else {
					{ ..acc, refused: acc.refused + 1 }
				}
			})

	is_message : Msg -> Bool
	is_message = |m| m.id != [] and m.from != [] and m.at != []

	## One block: an optional `MSG_` line, headers to the first blank line
	## (`from`, `date`, `uid` kept, the last of each, the rest passed over),
	## then the body, each line unescaped. Lines are found by offset and
	## kept as slices of the piece: nothing is copied but an escaped body.
	decode_block : List(U8) -> Msg
	decode_block = |piece| {
		first = line_at(piece, 0)
		(id, start) = if starts_with(first, msg_prefix) (List.drop_first(first, 4), List.len(first) + 1) else ([], 0)
		headers(piece, start, { id, from: [], at: [], uid: [], markdown: [] })
	}

	msg_prefix : List(U8)
	msg_prefix = Str.to_utf8("MSG_")

	## The line of `piece` that begins at `at`, without its newline.
	line_at : List(U8), U64 -> List(U8)
	line_at = |piece, at| List.sublist(piece, { start: at, len: line_len(piece, at, 0) })

	line_len : List(U8), U64, U64 -> U64
	line_len = |piece, at, n| match List.get(piece, at + n) {
		Ok(c) if c != 10 => line_len(piece, at, n + 1)
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
				next = match cut_seq(l, Str.to_utf8(": ")) {
					Ok((k, v)) =>
						if k == Str.to_utf8("from") {
							{ ..m, from: v }
						} else if k == Str.to_utf8("date") {
							{ ..m, at: v }
						} else if k == Str.to_utf8("uid") {
							{ ..m, uid: v }
						} else {
							m
						}
					Err(None) => m
				}
				headers(piece, at + List.len(l) + 1, next)
			}
		}

	## A body with no backslash before the dashes has no escaped line, and
	## is the bytes it was.
	unescape_body : List(U8) -> List(U8)
	unescape_body = |body|
		if find(body, escaped_dashes, 0) == Err(None) body else join_lines(List.map(split_byte(body, 10), unescape_line))

	escaped_dashes : List(U8)
	escaped_dashes = List.prepend(dashes, 92)

	## chatStoredForm: what message `index` adds to the file, its block after
	## `sep` for every message but the first.
	stored_form : U64, Msg -> List(U8)
	stored_form = |index, m| if index == 0 encode_block(m) else List.concat(sep, encode_block(m))

	## encodeChatBlock: `MSG_`, `from:`, `date:`, `uid:` when known, a blank
	## line, the body with each line escaped.
	encode_block : Msg -> List(U8)
	encode_block = |m| {
		body = if find(m.markdown, dashes, 0) == Err(None) m.markdown else join_lines(List.map(split_byte(m.markdown, 10), escape_line))
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
		k = leading(line, 92, 0)
		if k >= 1 and List.drop_first(line, k) == dashes List.drop_first(line, 1) else line
	}

	## A line of any backslashes then exactly the dashes gains one.
	escape_line : List(U8) -> List(U8)
	escape_line = |line| {
		k = leading(line, 92, 0)
		if List.drop_first(line, k) == dashes List.prepend(line, 92) else line
	}

	leading : List(U8), U8, U64 -> U64
	leading = |l, c, n| match List.get(l, n) {
		Ok(x) if x == c => leading(l, c, n + 1)
		_ => n
	}

	join_lines : List(List(U8)) -> List(U8)
	join_lines = |lines| List.join(List.intersperse(lines, [10]))

	## std.mem.splitScalar: every piece, empty ones too, as slices.
	split_byte : List(U8), U8 -> List(List(U8))
	split_byte = |s, b| split_byte_from(s, b, 0, 0, [])

	split_byte_from : List(U8), U8, U64, U64, List(List(U8)) -> List(List(U8))
	split_byte_from = |s, b, start, i, out| match List.get(s, i) {
		Err(_) => List.append(out, List.drop_first(s, start))
		Ok(c) =>
			if c == b {
				split_byte_from(s, b, i + 1, i + 1, List.append(out, List.sublist(s, { start, len: i - start })))
			} else {
				split_byte_from(s, b, start, i + 1, out)
			}
	}

	## std.mem.splitSequence: every piece between non-overlapping matches
	## of `needle`, found left to right.
	split_seq : List(U8), List(U8) -> List(List(U8))
	split_seq = |s, needle| split_seq_from(s, needle, 0, 0, [])

	split_seq_from : List(U8), List(U8), U64, U64, List(List(U8)) -> List(List(U8))
	split_seq_from = |s, needle, start, i, out| {
		n = List.len(needle)
		if i + n > List.len(s) {
			List.append(out, List.drop_first(s, start))
		} else if List.get(s, i) == List.first(needle) and List.sublist(s, { start: i, len: n }) == needle {
			split_seq_from(s, needle, i + n, i + n, List.append(out, List.sublist(s, { start, len: i - start })))
		} else {
			split_seq_from(s, needle, start, i + 1, out)
		}
	}

	## The bytes before and after the first `needle`.
	cut_seq : List(U8), List(U8) -> Try((List(U8), List(U8)), [None])
	cut_seq = |s, needle| match find(s, needle, 0) {
		Ok(i) => Ok((List.take_first(s, i), List.drop_first(s, i + List.len(needle))))
		Err(None) => Err(None)
	}

	find : List(U8), List(U8), U64 -> Try(U64, [None])
	find = |s, needle, i|
		if i + List.len(needle) > List.len(s) {
			Err(None)
		} else if List.get(s, i) == List.first(needle) and List.sublist(s, { start: i, len: List.len(needle) }) == needle {
			Ok(i)
		} else {
			find(s, needle, i + 1)
		}

	starts_with : List(U8), List(U8) -> Bool
	starts_with = |l, p| List.len(l) >= List.len(p) and List.take_first(l, List.len(p)) == p
}
