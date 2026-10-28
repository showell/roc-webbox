## THE MEMBER'S RECENT FEED (angry-gopher recent.zig, recent_feed.zig): the
## rows main.roc gathered, each named for the viewer, dated, excerpted and
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
	Row : { kind : [Doc, Message], secs : I64, uid : Str, name : Str, key : Str, label : Str, topic : Str, markdown : Str, dm : [Dm, Channel] }

	## A row as it is gathered (main.roc `load_recent!`), its text the
	## store's bytes: `secs` a signed decimal.
	Written : { kind : [Doc, Message], secs : List(U8), uid : List(U8), name : List(U8), key : List(U8), label : List(U8), topic : List(U8), markdown : List(U8), dm : [Dm, Channel] }

	## The host's rows, read. **EACH ROW'S TEXT DECODED HERE, AT THE
	## DOOR**: it is gathered from stored files and names, so a field
	## that is not UTF-8 is corrupt data, and `NotUtf8` with its bytes.
	rows : List(Written) -> Try(List(Row), [NotUtf8(List(U8))])
	rows = |ws| List.map_try(ws, decoded)

	## The host's rows, **ONE DAMAGED ROW ITS OWN** (metal-vmm QUEUE 267): a
	## row with a field that is not UTF-8 (a torn last transcript block) is
	## left out, its key's bytes in `damaged` for the host to count, and the
	## page served with the rest.
	rows_of : List(Written) -> { rows : List(Row), damaged : List(List(U8)) }
	rows_of = |ws|
		List.fold(
			ws,
			{ rows: [], damaged: [] },
			|got, w|
				match decoded(w) {
					Ok(r) => { ..got, rows: List.append(got.rows, r) }
					Err(NotUtf8(_)) => { ..got, damaged: List.append(got.damaged, w.key) }
				},
		)

	decoded : Written -> Try(Row, [NotUtf8(List(U8))])
	decoded = |w| {
		text = |bytes| Str.from_utf8(bytes).map_err(|_| NotUtf8(bytes))
		Ok({ kind: w.kind, secs: signed(w.secs), uid: text(w.uid)?, name: text(w.name)?, key: text(w.key)?, label: text(w.label)?, topic: text(w.topic)?, markdown: text(w.markdown)?, dm: w.dm })
	}

	## The page's JSON: every row newest first (a tie by its URL or slug,
	## else as gathered), each as recent_feed's encoders write it.
	json : Uid, List(Row) -> List(U8)
	json = |me, rs| JsonText.arr(List.map(sort(rs), |r| event(me, r)))

	## A row as recent_feed's encoders write it: empty fields left out.
	event : Uid, Row -> List(U8)
	event = |me, r| {
		at = JsonText.str(Time.rfc3339(r.secs))
		if r.kind == Doc {
			JsonText.obj(List.join([[("kind", JsonText.str("doc")), ("at", at)], JsonText.opt("who", "You"), JsonText.opt("slug", r.key), JsonText.opt("title", r.label)]))
		} else {
			who = if r.uid == "" "" else if r.uid == me.to_str() "You" else r.name
			chat_event({ at: Time.rfc3339(r.secs), url: r.key, who, label: r.label, topic: r.topic, excerpt: excerpt(r.markdown), dm: r.dm })
		}
	}

	## One chat message's row, its fields as written (`at` already a stamp).
	ChatEvent : { at : Str, url : Str, who : Str, label : Str, topic : Str, excerpt : Str, dm : [Dm, Channel] }

	## recent_feed `encodeChatEvent`: `kind` and `at`, then url, who, where,
	## topic and excerpt each left out when empty, then `"dm":true` for a
	## DM. The page's backlog and the live stream (`rec:<uid>`) send it.
	chat_event : ChatEvent -> List(U8)
	chat_event = |e|
		JsonText.obj(
			List.join([
				[("kind", JsonText.str("chat")), ("at", JsonText.str(e.at))],
				JsonText.opt("url", e.url),
				JsonText.opt("who", e.who),
				JsonText.opt("where", e.label),
				JsonText.opt("topic", e.topic),
				JsonText.opt("excerpt", e.excerpt),
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
					match order(a.row, b.row) {
						Same => if a.i < b.i Before else if a.i > b.i After else Same
						other => other
					},
			)
			|> List.map(|x| x.row)

	## `newestFirst`'s order of two rows: the newer first, a tie by the key's
	## bytes.
	order : Row, Row -> [Before, Same, After]
	order = |x, y| if x.secs > y.secs Before else if x.secs < y.secs After else Bytes.compare(x.key.to_utf8(), y.key.to_utf8())

	## docs_store `titleFromSlug`: hyphens to spaces, the first letter
	## upper-cased (a slug is ASCII: text in, text out).
	doc_title : Str -> Str
	doc_title = |slug| {
		spaced = List.map(slug.to_utf8(), |c| if c == '-' ' ' else c)
		titled = List.update(spaced, 0, |c| if c >= 'a' and c <= 'z' c - 32 else c) ?? spaced
		match Str.from_utf8(titled) {
			Ok(title) => title
			Err(_) => crash "Recent.doc_title: an ASCII edit split a codepoint"
		}
	}

	## recent_feed `recentExcerpt`: a quote fence becomes "[quoted text]",
	## an image "[image]", whitespace one space, cut at 350 codepoints.
	## **TEXT IN, TEXT OUT**: every edit below works on ASCII bytes alone
	## (a fence, `<img…>`, `![…](…)`, whitespace) and the cut falls where a
	## codepoint starts, so UTF-8 in is UTF-8 out; a failure to decode is a
	## bug here, and crashes (a 500).
	excerpt : Str -> Str
	excerpt = |text| {
		md = text.to_utf8()
		match Str.from_utf8(cap(collapse_ws(md_images(html_images(quotes(md)))), 350)) {
			Ok(cut) => cut
			Err(_) => crash "Recent.excerpt: an edit split a codepoint"
		}
	}
}

## A signed decimal, as the host writes one.
signed : List(U8) -> I64
signed = |digits| match digits {
	['-', .. as rest] => 0 - List.fold(rest, 0, |n, c| n * 10 + U8.to_i64(c - '0'))
	_ => List.fold(digits, 0, |n, c| n * 10 + U8.to_i64(c - '0'))
}

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
html_images = |s| html_from(s, 0, [], Unknown)

## Linear (metal-vmm QUEUE 268): where the next `>` is, or that there is
## none, is remembered across openers (Feeds.find_seen).
html_from : List(U8), U64, List(U8), Feeds.Seen -> List(U8)
html_from = |s, i, out, gt_seen|
	match List.get(s, i) {
		Err(_) => out
		Ok(c) => {
			opens = i + 4 <= List.len(s) and Feeds.lower(List.sublist(s, { start: i, len: 4 })) == Str.to_utf8("<img") and !is_word_byte(List.get(s, i + 4) ?? ' ')
			(found, seen) = if opens Feeds.find_seen(s, '>', i + 4, gt_seen) else (Err(NotFound), gt_seen)
			match found {
				Ok(gt) => html_from(s, gt + 1, List.concat(out, Str.to_utf8("[image]")), seen)
				Err(NotFound) => html_from(s, i + 1, List.append(out, c), seen)
			}
		}
	}

is_word_byte : U8 -> Bool
is_word_byte = |c| (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_'

## `replaceImgMarkdown`: `![…](…)`.
md_images : List(U8) -> List(U8)
md_images = |s| md_from(s, 0, [], { br: Unknown, pa: Unknown })

## Linear (metal-vmm QUEUE 268): where the next `]` and `)` are, or that
## there are none, is remembered across `![`s (Feeds.find_seen); every
## search from a later `![` starts at or after the one before it.
md_from : List(U8), U64, List(U8), { br : Feeds.Seen, pa : Feeds.Seen } -> List(U8)
md_from = |s, i, out, seen|
	match List.get(s, i) {
		Err(_) => out
		Ok(c) => {
			(end, after) = if c == '!' and List.get(s, i + 1) == Ok('[') md_image(s, i, seen) else (Err(NotAnImage), seen)
			match end {
				Ok(e) => md_from(s, e, List.concat(out, Str.to_utf8("[image]")), after)
				Err(NotAnImage) => md_from(s, i + 1, List.append(out, c), after)
			}
		}
	}

md_image : List(U8), U64, { br : Feeds.Seen, pa : Feeds.Seen } -> (Try(U64, [NotAnImage]), { br : Feeds.Seen, pa : Feeds.Seen })
md_image = |s, start, seen|
	match Feeds.find_seen(s, ']', start + 2, seen.br) {
		(Err(NotFound), br) => (Err(NotAnImage), { ..seen, br })
		(Ok(alt_end), br) =>
			if List.get(s, alt_end + 1) != Ok('(') {
				(Err(NotAnImage), { ..seen, br })
			} else {
				match Feeds.find_seen(s, ')', alt_end + 2, seen.pa) {
					(Ok(url_end), pa) => (Ok(url_end + 1), { br, pa })
					(Err(NotFound), pa) => (Err(NotAnImage), { br, pa })
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
	match List.get(s, i) {
		Err(OutOfBounds) => s
		Ok(_) if count == most => {
			head = List.take_first(s, i)
			List.concat(List.drop_last(head, Feeds.count_back(head, |c| c == ' ', 0)), Str.to_utf8("…"))
		}
		Ok(b) => {
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

# excerpt cuts at a codepoint: a multi-byte character at and past the cut
# (two bytes, four bytes) comes out whole or not at all, so its Str holds.
expect Recent.excerpt(Str.concat(Str.repeat("a", 349), "\u(e9)\u(e9)")) == Str.concat(Str.repeat("a", 349), "\u(e9)…")
expect Recent.excerpt(Str.repeat("👍", 351)) == Str.concat(Str.repeat("👍", 350), "…")
expect Recent.excerpt(Str.concat(Str.repeat("a", 348), " \u(e9)\u(e9)")) == Str.concat(Str.repeat("a", 348), " \u(e9)…")
expect Recent.excerpt(Str.repeat("\u(e9)", 350)) == Str.repeat("\u(e9)", 350)
expect Recent.excerpt("caf\u(e9) ![x](y.png)  <img src=a>\n```quote\nhi\n```") == "caf\u(e9) [image] [image] [quoted text]"
# rows_of: a row with a field torn mid-character is left out and its key kept for the count; the rest are read.
expect {
	w = |key, md| { kind: Message, secs: Str.to_utf8("1"), uid: Str.to_utf8("1"), name: Str.to_utf8("ann"), key: Str.to_utf8(key), label: Str.to_utf8("to x"), topic: Str.to_utf8("t"), markdown: md, dm: Dm }
	got = Recent.rows_of([w("/a", Str.to_utf8("hi")), w("/b", [0xe2, 0x82]), w("/c", Str.to_utf8("ok"))])
	List.map(got.rows, |r| r.key) == ["/a", "/c"] and got.damaged == [Str.to_utf8("/b")]
}
# doc_title: hyphens to spaces, the first letter up; a digit first stays.
expect Recent.doc_title("reading-list") == "Reading list" and Recent.doc_title("2026-plans") == "2026 plans" and Recent.doc_title("") == ""
