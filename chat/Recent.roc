## THE MEMBER'S RECENT FEED (angry-gopher recent.zig, recent_feed.zig): the
## rows the host gathered, each named for the viewer, dated, excerpted and
## put newest first, as the JSON /chat/recent boots with, byte for byte.
## Pure; angry-gopher's chat_twin_test.zig holds it to the Zig.
import JsonText
import Bytes
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
			rows_from(f, i + 9, List.append(out, { doc: at(0) == ['1'], secs: signed(at(1)), uid: at(2), name: at(3), key: at(4), label: at(5), topic: at(6), markdown: at(7), dm: at(8) == ['1'] }))
		}

	## A signed decimal, as the host writes one.
	signed : List(U8) -> I64
	signed = |digits| match digits {
		['-', .. as rest] => 0 - List.fold(rest, 0, |n, c| n * 10 + U8.to_i64(c - '0'))
		_ => List.fold(digits, 0, |n, c| n * 10 + U8.to_i64(c - '0'))
	}

	## The page's JSON: every row newest first (a tie by its URL or slug,
	## else as gathered), each as recent_feed's encoders write it.
	json : List(U8), List(Row) -> List(U8)
	json = |me, rs| JsonText.arr(List.map(sort(rs), |r| event(me, r)))

	## A row as recent_feed's encoders write it: empty fields left out.
	event : List(U8), Row -> List(U8)
	event = |me, r| {
		at = JsonText.str(Str.to_utf8(Time.rfc3339(r.secs)))
		if r.doc {
			JsonText.obj(List.join([[("kind", JsonText.str(Str.to_utf8("doc"))), ("at", at)], JsonText.opt("who", Str.to_utf8("You")), JsonText.opt("slug", r.key), JsonText.opt("title", r.label)]))
		} else {
			who = if r.uid == [] [] else if r.uid == me Str.to_utf8("You") else r.name
			chat_event({ at: Str.to_utf8(Time.rfc3339(r.secs)), url: r.key, who, label: r.label, topic: r.topic, excerpt: excerpt(r.markdown), dm: if r.dm Dm else Channel })
		}
	}

	## One chat message's row, its fields as written (`at` already a stamp).
	ChatEvent : { at : List(U8), url : List(U8), who : List(U8), label : List(U8), topic : List(U8), excerpt : List(U8), dm : [Dm, Channel] }

	## recent_feed `encodeChatEvent`: `kind` and `at`, then url, who, where,
	## topic and excerpt each left out when empty, then `"dm":true` for a
	## DM. The page's backlog and the live stream (`rec:<uid>`) send it.
	chat_event : ChatEvent -> List(U8)
	chat_event = |e|
		JsonText.obj(List.join([
			[("kind", JsonText.str(Str.to_utf8("chat"))), ("at", JsonText.str(e.at))],
			JsonText.opt("url", e.url),
			JsonText.opt("who", e.who),
			JsonText.opt("where", e.label),
			JsonText.opt("topic", e.topic),
			JsonText.opt("excerpt", e.excerpt),
			if e.dm == Dm [("dm", JsonText.bool(Bool.True))] else [],
		]))

	## recent.zig `newestFirst`, stably, as std.mem.sort is: newest first, a
	## tie by the URL or slug, and rows equal in both in the order gathered
	## (each row's index is its last key, so the sort need not be stable).
	sort : List(Row) -> List(Row)
	sort = |rs|
		List.map_with_index(rs, |row, i| { row, i })
		|> List.sort_with(|a, b|
			if before(a.row, b.row) {
				Before
			} else if before(b.row, a.row) {
				After
			} else if a.i < b.i {
				Before
			} else if a.i > b.i {
				After
			} else {
				Same
			})
		|> List.map(|x| x.row)

	before : Row, Row -> Bool
	before = |x, y| if x.secs != y.secs x.secs > y.secs else Bytes.less(x.key, y.key)

	## recent_feed `recentExcerpt`: a quote fence becomes "[quoted text]",
	## an image "[image]", whitespace one space, cut at 350 codepoints.
	excerpt : List(U8) -> List(U8)
	excerpt = |md| cap(collapse_ws(md_images(html_images(quotes(md)))), 350)

	## `collapseQuotes`: line by line, a quote fence's span to "[quoted
	## text]", another fence's lines as they are, each line ended.
	quotes : List(U8) -> List(U8)
	quotes = |md| quotes_from(Bytes.split_byte(md, '\n'), 0, [])

	quotes_from : List(List(U8)), U64, List(U8) -> List(U8)
	quotes_from = |ls, i, out|
		match List.get(ls, i) {
			Err(_) => out
			Ok(line) =>
				match Feeds.fence_open(line) {
					Err(None) => quotes_from(ls, i + 1, List.append(List.concat(out, line), '\n'))
					Ok(fo) => {
						j = Feeds.close_at(ls, fo.char, fo.count, i + 1)
						kept =
							if fo.lang == Str.to_utf8("quote") {
								Str.to_utf8("[quoted text]\n")
							} else {
								List.join(List.map(List.sublist(ls, { start: i, len: j + 1 - i }), |l| List.append(l, '\n')))
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
				opens = i + 4 <= List.len(s) and Feeds.lower(List.sublist(s, { start: i, len: 4 })) == Str.to_utf8("<img") and !word(List.get(s, i + 4) ?? ' ')
				match (if opens Feeds.find_byte(s, '>', i + 4) else Err(None)) {
					Ok(gt) => html_from(s, gt + 1, List.concat(out, Str.to_utf8("[image]")))
					Err(None) => html_from(s, i + 1, List.append(out, c))
				}
			}
		}

	word : U8 -> Bool
	word = |c| (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_'

	## `replaceImgMarkdown`: `![…](…)`.
	md_images : List(U8) -> List(U8)
	md_images = |s| md_from(s, 0, [])

	md_from : List(U8), U64, List(U8) -> List(U8)
	md_from = |s, i, out|
		match List.get(s, i) {
			Err(_) => out
			Ok(c) => {
				end = if c == '!' and List.get(s, i + 1) == Ok('[') md_image(s, i) else Err(None)
				match end {
					Ok(e) => md_from(s, e, List.concat(out, Str.to_utf8("[image]")))
					Err(None) => md_from(s, i + 1, List.append(out, c))
				}
			}
		}

	md_image : List(U8), U64 -> Try(U64, [None])
	md_image = |s, start|
		match Feeds.find_byte(s, ']', start + 2) {
			Err(None) => Err(None)
			Ok(alt_end) =>
				if List.get(s, alt_end + 1) != Ok('(') {
					Err(None)
				} else {
					match Feeds.find_byte(s, ')', alt_end + 2) {
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
				(List.append(if in_ws and acc != [] List.append(acc, ' ') else acc, c), Bool.False)
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
			List.concat(List.drop_last(head, Feeds.count_back(head, |c| c == ' ', 0)), Str.to_utf8("…"))
		} else {
			b = List.get(s, i) ?? 0
			n = if b < 128 1 else if b >= 192 and b < 224 2 else if b >= 224 and b < 240 3 else if b >= 240 and b < 248 4 else 1
			cap_from(s, most, i + n, count + 1)
		}
}
