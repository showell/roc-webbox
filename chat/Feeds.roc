## THE MEMBER'S IMAGES AND CODE FEEDS (angry-gopher images_store.zig,
## code_store.zig, markdown_fence.zig): each member's images.md and code.md
## read as the Zig reads them, and the JSON their pages boot with, byte for
## byte. Pure; angry-gopher's chat_twin_test.zig holds each to its Zig.
import JsonText
import Bytes
import Paths
import ZigText

Feeds := [].{
	## The member's feed file under the chat root: users/<uid>/images.md or
	## code.md, where images_store and code_store keep them.
	path : List(U8), [Images, Code] -> List(U8)
	path = |uid, which| {
		name = match which {
			Images => "images.md"
			Code => "code.md"
		}
		Paths.join([Str.to_utf8("users"), uid, Str.to_utf8(name)])
	}

	## One entry's header line: `Sent by <from> at <at>, source MSG_<source_id> in <conv>:`.
	Header : { from : List(U8), at : List(U8), source_id : List(U8), conv : List(U8) }

	## A fenced block of a message, as the Code feed keeps it.
	Block : { lang : List(U8), body : List(U8) }

	## images_store `parseHeader`: `at` after the last " at " before the first
	## ", source MSG_", `conv` after the first " in " after it.
	header : List(U8) -> Try(Header, [None])
	header = |line|
		if !Bytes.starts_with(line, Str.to_utf8("Sent by ")) or List.last(line) != Ok(58) {
			Err(None)
		} else {
			inner = List.drop_last(List.drop_first(line, 8), 1)
			match Bytes.cut_seq(inner, Str.to_utf8(", source MSG_")) {
				Err(None) => Err(None)
				Ok((left, right)) =>
					match (last_find(left, Str.to_utf8(" at ")), Bytes.cut_seq(right, Str.to_utf8(" in "))) {
						(Ok(a), Ok((source_id, conv))) => Ok({ from: List.take_first(left, a), at: List.drop_first(left, a + 4), source_id, conv })
						_ => Err(None)
					}
			}
		}

	## Where `needle` last starts in `s`.
	last_find : List(U8), List(U8) -> Try(U64, [None])
	last_find = |s, needle| {
		n = List.len(needle)
		if List.len(s) < n {
			Err(None)
		} else {
			last_find_from(s, needle, List.len(s) - n)
		}
	}

	last_find_from : List(U8), List(U8), U64 -> Try(U64, [None])
	last_find_from = |s, needle, i|
		if List.sublist(s, { start: i, len: List.len(needle) }) == needle {
			Ok(i)
		} else if i == 0 {
			Err(None)
		} else {
			last_find_from(s, needle, i - 1)
		}

	## The file's blocks between separators, trimmed, the empty ones gone.
	blocks_of : List(U8) -> List(List(U8))
	blocks_of = |text|
		if ZigText.trim(text) == [] {
			[]
		} else {
			List.keep_if(List.map(Bytes.split_seq(text, sep), ZigText.trim), |b| b != [])
		}

	sep : List(U8)
	sep = Str.to_utf8("\n\n-------------\n\n")

	## images_store `parseImagesFile`: every block whose header reads, with
	## its `<img` tags (none is still an entry).
	images : List(U8) -> List((Header, List(List(U8))))
	images = |text|
		List.fold(blocks_of(text), [], |out, block| {
			(line, body) = match find_byte(block, 10, 0) {
				Ok(nl) => (List.take_first(block, nl), List.drop_first(block, nl + 1))
				Err(None) => (block, [])
			}
			match header(line) {
				Ok(h) => List.append(out, (h, img_tags(body)))
				Err(None) => out
			}
		})

	## images_store `extractImageTags`: every `<img` (any case) followed by
	## whitespace, to the next `>`.
	img_tags : List(U8) -> List(List(U8))
	img_tags = |s| img_tags_from(s, 0, [])

	img_tags_from : List(U8), U64, List(List(U8)) -> List(List(U8))
	img_tags_from = |s, i, out|
		if i >= List.len(s) {
			out
		} else if i + 4 < List.len(s) and lower(List.sublist(s, { start: i, len: 4 })) == Str.to_utf8("<img") and is_space(List.get(s, i + 4) ?? 0) {
			match find_byte(s, 62, i + 4) {
				Ok(gt) => img_tags_from(s, gt + 1, List.append(out, List.sublist(s, { start: i, len: gt + 1 - i })))
				Err(None) => img_tags_from(s, i + 1, out)
			}
		} else {
			img_tags_from(s, i + 1, out)
		}

	find_byte : List(U8), U8, U64 -> Try(U64, [None])
	find_byte = |s, b, i| match List.get(s, i) {
		Ok(c) => if c == b Ok(i) else find_byte(s, b, i + 1)
		Err(_) => Err(None)
	}

	smaller : U64, U64 -> U64
	smaller = |a, b| if a < b a else b

	lower : List(U8) -> List(U8)
	lower = |s| List.map(s, |c| if c >= 65 and c <= 90 c + 32 else c)

	is_space : U8 -> Bool
	is_space = |c| c == 32 or c == 9 or c == 10 or c == 13 or c == 12 or c == 11

	## code_store `parseCodeFile`: every block with a header line and a body
	## holding at least one fence that is not a quote.
	code : List(U8) -> List((Header, List(Block)))
	code = |text|
		List.fold(blocks_of(text), [], |out, block|
			match find_byte(block, 10, 0) {
				Err(None) => out
				Ok(nl) =>
					match header(List.take_first(block, nl)) {
						Err(None) => out
						Ok(h) => {
							bs = code_blocks(List.drop_first(block, nl + 1))
							if bs == [] out else List.append(out, (h, bs))
						}
					}
			})

	## code_store `extractCodeBlocks`: each fence's lines to the first close
	## of its character at least as long, or to the end; a `quote` fence's
	## lines skipped.
	code_blocks : List(U8) -> List(Block)
	code_blocks = |body| blocks_from(Bytes.split_byte(body, 10), 0, [])

	blocks_from : List(List(U8)), U64, List(Block) -> List(Block)
	blocks_from = |ls, i, out|
		match List.get(ls, i) {
			Err(_) => out
			Ok(line) =>
				match fence_open(line) {
					Err(None) => blocks_from(ls, i + 1, out)
					Ok(fo) => {
						j = close_at(ls, fo.char, fo.count, i + 1)
						body = Bytes.join_lines(List.sublist(ls, { start: i + 1, len: j - (i + 1) }))
						blocks_from(ls, j + 1, if fo.lang == Str.to_utf8("quote") out else List.append(out, { lang: fo.lang, body }))
					}
				}
		}

	close_at : List(List(U8)), U8, U64, U64 -> U64
	close_at = |ls, char, count, j| match List.get(ls, j) {
		Err(_) => j
		Ok(line) => if is_close(line, char, count) j else close_at(ls, char, count, j + 1)
	}

	## markdown_fence `parseOpen`: up to three spaces, 3 to 10 of '`' or '~',
	## and an info string whose first word is the language (no '`' in a
	## backtick fence's).
	fence_open : List(U8) -> Try({ char : U8, count : U64, lang : List(U8) }, [None])
	fence_open = |line| {
		indent = smaller(Bytes.leading(line, 32, 0), 4)
		match List.get(line, indent) {
			Err(_) => Err(None)
			Ok(f) =>
				if indent >= 4 or (f != 96 and f != 126) {
					Err(None)
				} else {
					count = Bytes.leading(List.drop_first(line, indent), f, 0)
					info = trim_info(List.drop_first(line, indent + count))
					if count < 3 or count > 10 or (f == 96 and List.contains(info, 96)) {
						Err(None)
					} else {
						lang = List.take_first(info, count_while(info, |c| c != 32 and c != 9, 0))
						Ok({ char: f, count, lang })
					}
				}
		}
	}

	## markdown_fence `isClose`: up to three spaces, at least `count` of
	## `char`, then only whitespace.
	is_close : List(U8), U8, U64 -> Bool
	is_close = |line, char, count| {
		indent = smaller(Bytes.leading(line, 32, 0), 4)
		if indent >= 4 {
			Bool.False
		} else {
			n = Bytes.leading(List.drop_first(line, indent), char, 0)
			n >= count and trim_info(List.drop_first(line, indent + n)) == []
		}
	}

	## `std.mem.trim(u8, s, " \t\r")`.
	trim_info : List(U8) -> List(U8)
	trim_info = |s| {
		ws = |c| c == 32 or c == 9 or c == 13
		front = List.drop_first(s, count_while(s, ws, 0))
		List.drop_last(front, count_back(front, ws, 0))
	}

	## How many bytes from `i` on keep `keep`.
	count_while : List(U8), (U8 -> Bool), U64 -> U64
	count_while = |s, keep, i| match List.get(s, i) {
		Ok(c) if keep(c) => count_while(s, keep, i + 1)
		_ => i
	}

	## How many bytes from the end keep `keep`.
	count_back : List(U8), (U8 -> Bool), U64 -> U64
	count_back = |s, keep, n|
		if n >= List.len(s) {
			n
		} else {
			match List.get(s, List.len(s) - 1 - n) {
				Ok(c) if keep(c) => count_back(s, keep, n + 1)
				_ => n
			}
		}

	## chat_fanout `convKeyBaseURL` then images_store `imagesSourceURL`: the
	## source message's link, or its conversation's when its id has no
	## topic part.
	source_url : List(U8), List(U8) -> List(U8)
	source_url = |conv, source_id| {
		base = List.concat(Str.to_utf8(if List.contains(conv, 95) "/chat/c/" else "/channel/"), conv)
		cut = List.len(source_id) - count_back(source_id, |c| c != 95, 0)
		# `cut` is one past the last '_' (0 when there is none).
		if cut > 1 {
			List.join([base, [47], List.take_first(source_id, cut - 1), Str.to_utf8("#msg-"), source_id])
		} else {
			base
		}
	}

	## The fields every feed entry starts with, from its header.
	head_fields : Header -> List((Str, List(U8)))
	head_fields = |h| [("source_id", JsonText.str(h.source_id)), ("from", JsonText.str(h.from)), ("conv", JsonText.str(h.conv)), ("at", JsonText.str(h.at))]

	## The Images page's JSON: the newest `most` entries, each as
	## images_store `encodeImagesEvent` writes it.
	images_json : List((Header, List(List(U8)))), U64 -> List(U8)
	images_json = |entries, most| {
		tail = List.drop_first(entries, List.len(entries) - smaller(most, List.len(entries)))
		JsonText.arr(List.map(tail, |(h, tags)|
			JsonText.obj(List.concat(head_fields(h), [("images", JsonText.arr(List.map(tags, JsonText.str))), ("source_url", JsonText.str(source_url(h.conv, h.source_id)))]))))
	}

	## The Code page's JSON: every entry, as code_store `encodeCodeEvent`
	## writes it.
	code_json : List((Header, List(Block))) -> List(U8)
	code_json = |entries|
		JsonText.arr(List.map(entries, |(h, bs)| {
			blocks = JsonText.arr(List.map(bs, |b| JsonText.obj([("lang", JsonText.str(b.lang)), ("body", JsonText.str(b.body))])))
			JsonText.obj(List.concat(head_fields(h), [("blocks", blocks), ("source_url", JsonText.str(source_url(h.conv, h.source_id)))]))
		}))
}
