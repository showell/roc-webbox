## THE MEMBER'S RECENT FEED (angry-gopher recent.zig, recent_feed.zig): the
## rows the host gathered, each named for the viewer, dated, excerpted and
## put newest first, as the JSON /chat/recent boots with, byte for byte.
## Pure; angry-gopher's chat_twin_test.zig holds it to the Zig.
import JsonText
import Bytes
import Feeds
import Time
import Uid
import ZigText

Recent := [].{

	## One gathered row (recent.zig `Row`): `key` a chat row's URL or a doc's
	## slug, `label` its "to …"/"in …" or the doc's title; `dm` as
	## ChatEvent's.
	Row : { kind : [Doc, Message], secs : I64, uid : List(U8), name : List(U8), key : List(U8), label : List(U8), topic : List(U8), markdown : List(U8), dm : [Dm, Channel] }

	## A row as the host writes it (Host.recent!): `secs` a signed decimal.
	Written : { kind : [Doc, Message], secs : List(U8), uid : List(U8), name : List(U8), key : List(U8), label : List(U8), topic : List(U8), markdown : List(U8), dm : [Dm, Channel] }

	## The host's rows, read.
	rows : List(Written) -> List(Row)
	rows = |ws| List.map(ws, |w| { kind: w.kind, secs: signed(w.secs), uid: w.uid, name: w.name, key: w.key, label: w.label, topic: w.topic, markdown: w.markdown, dm: w.dm })

	## A signed decimal, as the host writes one.
	signed : List(U8) -> I64
	signed = |digits| match digits {
		['-', .. as rest] => 0 - List.fold(rest, 0, |n, c| n * 10 + U8.to_i64(c - '0'))
		_ => List.fold(digits, 0, |n, c| n * 10 + U8.to_i64(c - '0'))
	}

	## The page's JSON: every row newest first (a tie by its URL or slug,
	## else as gathered), each as recent_feed's encoders write it.
	json : Uid, List(Row) -> List(U8)
	json = |me, rs| JsonText.arr(List.map(sort(rs), |r| event(me, r)))

	## A row as recent_feed's encoders write it: empty fields left out.
	# TEMPORARY DOOR: moves out in a later run.
	event : Uid, Row -> List(U8)
	event = |me, r| {
		at = JsonText.str(Time.rfc3339(r.secs))
		if r.kind == Doc {
			JsonText.obj(List.join([[("kind", JsonText.str("doc")), ("at", at)], JsonText.opt("who", "You"), JsonText.opt_at_door("slug", r.key), JsonText.opt_at_door("title", r.label)]))
		} else {
			who = if r.uid == [] [] else if r.uid == me.to_str().to_utf8() Str.to_utf8("You") else r.name
			chat_event({ at: Str.to_utf8(Time.rfc3339(r.secs)), url: r.key, who, label: r.label, topic: r.topic, excerpt: excerpt(r.markdown), dm: r.dm })
		}
	}

	## One chat message's row, its fields as written (`at` already a stamp).
	ChatEvent : { at : List(U8), url : List(U8), who : List(U8), label : List(U8), topic : List(U8), excerpt : List(U8), dm : [Dm, Channel] }

	## recent_feed `encodeChatEvent`: `kind` and `at`, then url, who, where,
	## topic and excerpt each left out when empty, then `"dm":true` for a
	## DM. The page's backlog and the live stream (`rec:<uid>`) send it.
	# TEMPORARY DOOR: moves out in a later run.
	chat_event : ChatEvent -> List(U8)
	chat_event = |e|
		JsonText.obj(
			List.join([
				[("kind", JsonText.str("chat")), ("at", JsonText.str_at_door(e.at))],
				JsonText.opt_at_door("url", e.url),
				JsonText.opt_at_door("who", e.who),
				JsonText.opt_at_door("where", e.label),
				JsonText.opt_at_door("topic", e.topic),
				JsonText.opt_at_door("excerpt", e.excerpt),
				if e.dm == Dm [("dm", JsonText.bool(Bool.True))] else [],
			]),
		)

	## recent.zig `newestFirst`, stably, as std.mem.sort is: newest first, a
	## tie by the URL or slug, and rows equal in both in the order gathered
	## (each row's index is its last key, so the sort need not be stable).
	sort : List(Row) -> List(Row)
	sort = |rs|
		List.map_with_index(rs, |row, i| { row, i })
			|> List.sort_with(
				|a, b|
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
					},
			)
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
					Err(NotAFence) => quotes_from(ls, i + 1, List.append(List.concat(out, line), '\n'))
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
				match (if opens Feeds.find_byte(s, '>', i + 4) else Err(NotFound)) {
					Ok(gt) => html_from(s, gt + 1, List.concat(out, Str.to_utf8("[image]")))
					Err(NotFound) => html_from(s, i + 1, List.append(out, c))
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
				end = if c == '!' and List.get(s, i + 1) == Ok('[') md_image(s, i) else Err(NotAnImage)
				match end {
					Ok(e) => md_from(s, e, List.concat(out, Str.to_utf8("[image]")))
					Err(NotAnImage) => md_from(s, i + 1, List.append(out, c))
				}
			}
		}

	md_image : List(U8), U64 -> Try(U64, [NotAnImage])
	md_image = |s, start|
		match Feeds.find_byte(s, ']', start + 2) {
			Err(NotFound) => Err(NotAnImage)
			Ok(alt_end) =>
				if List.get(s, alt_end + 1) != Ok('(') {
					Err(NotAnImage)
				} else {
					match Feeds.find_byte(s, ')', alt_end + 2) {
						Ok(url_end) => Ok(url_end + 1)
						Err(NotFound) => Err(NotAnImage)
					}
				}
		}

	## `collapseWhitespace`: each run of whitespace one space, none at
	## either end.
	collapse_ws : List(U8) -> List(U8)
	collapse_ws = |s| {
		(out, _) = List.fold(
			s,
			([], Bool.False),
			|(acc, in_ws), c|
				if Feeds.is_space(c) {
					(acc, Bool.True)
				} else {
					(List.append(if in_ws and acc != [] List.append(acc, ' ') else acc, c), Bool.False)
				},
		)
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
			n = match b {
				_ if b < 128 => 1
				_ if b >= 192 and b < 224 => 2
				_ if b >= 224 and b < 240 => 3
				_ if b >= 240 and b < 248 => 4
				_ => 1
			}
			cap_from(s, most, i + n, count + 1)
		}
}
