## THE MEMBER'S RECENT FEED (angry-gopher recent.zig, recent_feed.zig): the
## rows the host gathered, each named for the viewer, dated, excerpted and
## put newest first, as the JSON /chat/recent boots with, byte for byte.
## Pure; angry-gopher's chat_twin_test.zig holds it to the Zig.
import Codec
import Feeds
import Time
import ZigText

Recent := [].{
	## One gathered row (recent.zig `Row`): `key` a chat row's URL or a doc's
	## slug, `label` its "to …"/"in …" or the doc's title.
	Row : { doc : Bool, secs : I64, uid : List(U8), name : List(U8), key : List(U8), label : List(U8), topic : List(U8), markdown : List(U8), dm : Bool }

	## The host's rows, nine fields each: doc, secs, uid, name, key, label,
	## topic, markdown, dm.
	rows : List(List(U8)) -> List(Row)
	rows = |fields| rows_from(fields, 0, [])

	rows_from : List(List(U8)), U64, List(Row) -> List(Row)
	rows_from = |f, i, out|
		if i + 9 > List.len(f) {
			out
		} else {
			at = |k| List.get(f, i + k) ?? []
			rows_from(f, i + 9, List.append(out, { doc: at(0) == [49], secs: signed(at(1)), uid: at(2), name: at(3), key: at(4), label: at(5), topic: at(6), markdown: at(7), dm: at(8) == [49] }))
		}

	## A signed decimal, as the host writes one.
	signed : List(U8) -> I64
	signed = |digits| match digits {
		[45, .. as rest] => 0 - List.fold(rest, 0, |n, c| n * 10 + U8.to_i64(c - 48))
		_ => List.fold(digits, 0, |n, c| n * 10 + U8.to_i64(c - 48))
	}

	## The page's JSON: every row newest first (a tie by its URL or slug,
	## else as gathered), each as recent_feed's encoders write it.
	json : List(U8), List(Row) -> List(U8)
	json = |me, rs| Feeds.array(List.map(sort(rs), |r| event(me, r)))

	event : List(U8), Row -> List(U8)
	event = |me, r| {
		at = Str.to_utf8(Time.rfc3339(r.secs))
		field = |name, v| if v == [] [] else List.join([Str.to_utf8(",\"${name}\":"), ZigText.json_string(v)])
		if r.doc {
			List.join([Str.to_utf8("{\"kind\":\"doc\",\"at\":"), ZigText.json_string(at), field("who", Str.to_utf8("You")), field("slug", r.key), field("title", r.label), [125]])
		} else {
			who = if r.uid == [] [] else if r.uid == me Str.to_utf8("You") else r.name
			List.join([
				Str.to_utf8("{\"kind\":\"chat\",\"at\":"),
				ZigText.json_string(at),
				field("url", r.key),
				field("who", who),
				field("where", r.label),
				field("topic", r.topic),
				field("excerpt", excerpt(r.markdown)),
				if r.dm Str.to_utf8(",\"dm\":true") else [],
				[125],
			])
		}
	}

	## recent.zig `newestFirst`, stably, as std.mem.sort is.
	sort : List(Row) -> List(Row)
	sort = |rs|
		if List.len(rs) < 2 {
			rs
		} else {
			half = List.len(rs) // 2
			merge(sort(List.take_first(rs, half)), sort(List.drop_first(rs, half)), [])
		}

	merge : List(Row), List(Row), List(Row) -> List(Row)
	merge = |a, b, out|
		match (List.first(a), List.first(b)) {
			(Ok(x), Ok(y)) => if before(y, x) merge(a, List.drop_first(b, 1), List.append(out, y)) else merge(List.drop_first(a, 1), b, List.append(out, x))
			(Ok(_), Err(_)) => List.concat(out, a)
			_ => List.concat(out, b)
		}

	before : Row, Row -> Bool
	before = |x, y| if x.secs != y.secs x.secs > y.secs else less(x.key, y.key)

	## std.mem.lessThan of bytes.
	less : List(U8), List(U8) -> Bool
	less = |a, b| match (a, b) {
		([x, .. as ra], [y, .. as rb]) => if x != y x < y else less(ra, rb)
		([], [_, ..]) => Bool.True
		_ => Bool.False
	}

	## recent_feed `recentExcerpt`: a quote fence becomes "[quoted text]",
	## an image "[image]", whitespace one space, cut at 350 codepoints.
	excerpt : List(U8) -> List(U8)
	excerpt = |md| cap(collapse_ws(md_images(html_images(quotes(md)))), 350)

	## `collapseQuotes`: line by line, a quote fence's span to "[quoted
	## text]", another fence's lines as they are, each line ended.
	quotes : List(U8) -> List(U8)
	quotes = |md| quotes_from(Codec.split_byte(md, 10), 0, [])

	quotes_from : List(List(U8)), U64, List(U8) -> List(U8)
	quotes_from = |ls, i, out|
		match List.get(ls, i) {
			Err(_) => out
			Ok(line) =>
				match Feeds.fence_open(line) {
					Err(None) => quotes_from(ls, i + 1, List.append(List.concat(out, line), 10))
					Ok(fo) => {
						j = Feeds.close_at(ls, fo.char, fo.count, i + 1)
						kept =
							if fo.lang == Str.to_utf8("quote") {
								Str.to_utf8("[quoted text]\n")
							} else {
								List.join(List.map(List.sublist(ls, { start: i, len: j + 1 - i }), |l| List.append(l, 10)))
							}
						quotes_from(ls, j + 1, List.concat(out, kept))
					}
				}
		}

	## `replaceImgHtml`: `<img` (any case) not followed by a word byte, to
	## the next `>`.
	html_images : List(U8) -> List(U8)
	html_images = |s| html_from(s, 0, [])

	html_from : List(U8), U64, List(U8) -> List(U8)
	html_from = |s, i, out|
		match List.get(s, i) {
			Err(_) => out
			Ok(c) => {
				opens = i + 4 <= List.len(s) and Feeds.lower(List.sublist(s, { start: i, len: 4 })) == Str.to_utf8("<img") and !word(List.get(s, i + 4) ?? 32)
				match (if opens Feeds.find_byte(s, 62, i + 4) else Err(None)) {
					Ok(gt) => html_from(s, gt + 1, List.concat(out, Str.to_utf8("[image]")))
					Err(None) => html_from(s, i + 1, List.append(out, c))
				}
			}
		}

	word : U8 -> Bool
	word = |c| (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95

	## `replaceImgMarkdown`: `![…](…)`.
	md_images : List(U8) -> List(U8)
	md_images = |s| md_from(s, 0, [])

	md_from : List(U8), U64, List(U8) -> List(U8)
	md_from = |s, i, out|
		match List.get(s, i) {
			Err(_) => out
			Ok(c) => {
				end = if c == 33 and List.get(s, i + 1) == Ok(91) md_image(s, i) else Err(None)
				match end {
					Ok(e) => md_from(s, e, List.concat(out, Str.to_utf8("[image]")))
					Err(None) => md_from(s, i + 1, List.append(out, c))
				}
			}
		}

	md_image : List(U8), U64 -> Try(U64, [None])
	md_image = |s, start|
		match Feeds.find_byte(s, 93, start + 2) {
			Err(None) => Err(None)
			Ok(alt_end) =>
				if List.get(s, alt_end + 1) != Ok(40) {
					Err(None)
				} else {
					match Feeds.find_byte(s, 41, alt_end + 2) {
						Ok(url_end) => Ok(url_end + 1)
						Err(None) => Err(None)
					}
				}
		}

	## `collapseWhitespace`: each run of whitespace one space, none at
	## either end.
	collapse_ws : List(U8) -> List(U8)
	collapse_ws = |s| {
		(out, _) = List.fold(s, ([], Bool.False), |(acc, in_ws), c|
			if Feeds.is_space(c) {
				(acc, Bool.True)
			} else {
				(List.append(if in_ws and acc != [] List.append(acc, 32) else acc, c), Bool.False)
			})
		out
	}

	## `capCodepoints`: at most `most` codepoints (a byte that starts none is
	## one), else the head with its trailing spaces gone and "…".
	cap : List(U8), U64 -> List(U8)
	cap = |s, most| cap_from(s, most, 0, 0)

	cap_from : List(U8), U64, U64, U64 -> List(U8)
	cap_from = |s, most, i, count|
		if i >= List.len(s) {
			s
		} else if count == most {
			head = List.take_first(s, i)
			List.concat(List.drop_last(head, Feeds.count_back(head, |c| c == 32, 0)), Str.to_utf8("…"))
		} else {
			b = List.get(s, i) ?? 0
			n = if b < 128 1 else if b >= 192 and b < 224 2 else if b >= 224 and b < 240 3 else if b >= 240 and b < 248 4 else 1
			cap_from(s, most, i + n, count + 1)
		}
}
