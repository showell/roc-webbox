## THE MEMBER'S IMAGES AND CODE FEEDS (angry-gopher images_store.zig,
## code_store.zig, markdown_fence.zig): each member's images.md and code.md
## read as the Zig reads them, and the JSON their pages boot with, byte for
## byte. Text in and out; the scanning is over its bytes, cut only at ASCII
## ones. Pure; angry-gopher's chat_twin_test.zig holds each to its Zig.
import JsonOut
import Bytes
import Fence
import ChatUrl
import SafeImg
import Transcript
import Ascii

Feeds := [].{

	## One entry's header line: `Sent by <from> at <at>, source MSG_<source_id> in <conv>:`.
	Header : {
		from : Str,
		at : Str,
		source_id : Str,
		conv : Str,
	}

	## A fenced block of a message, as the Code feed keeps it.
	Block : { lang : Str, body : Str }

	## images_store `parseHeader`: `at` after the last " at " before the first
	## ", source MSG_", `conv` after the first " in " after it.
	header : Str -> Try(Header, [NotAHeader])
	header = |line| {
		inner = if line.starts_with("Sent by ") and line.ends_with(":") Ok(line.drop_prefix("Sent by ").drop_suffix(":")) else Err(NotAHeader)
		{
			before: left,
			after: right,
		} = inner?.split_first(", source MSG_").map_err(|_| NotAHeader)?
		{ before: from, after: at } = left.split_last(" at ").map_err(|_| NotAHeader)?
		{ before: source_id, after: conv } = right.split_first(" in ").map_err(|_| NotAHeader)?
		Ok({
			from,
			at,
			source_id,
			conv,
		})
	}

	sep : List(U8)
	sep = Str.to_utf8("\n\n-------------\n\n")

	## images_store `parseImagesFile`: every block whose header reads, with
	## its `<img` tags (none is still an entry).
	images : Str -> List((Header, List(Str)))
	images = |text|
		List.fold(
			blocks_of(text.to_utf8()),
			[],
			|out, block| {
				(line, body) = match Bytes.find_byte(block, { byte: '\n', at: 0 }) {
					Ok(nl) => (List.take_first(block, nl), List.drop_first(block, nl + 1))
					Err(NotFound) => (block, [])
				}
				match header(text_of(line)) {
					Ok(h) => List.append(out, (h, tags_in(body)))
					Err(NotAHeader) => out
				}
			},
		)

	## `images`, from the file's bytes as stored: **ONE DAMAGED ENTRY IS ITS
	## OWN** (metal-vmm QUEUE 267). An entry whose bytes are not UTF-8 (one
	## torn mid-character) is skipped and counted in `damaged`, and the rest
	## read as `images` reads them, so the member's page is served.
	images_of : List(U8) -> { entries : List((Header, List(Str))), damaged : U64 }
	images_of = |bytes| {
		(text, damaged) = text_blocks(bytes)
		{ entries: images(text), damaged }
	}

	## `code`, from the file's bytes as stored, as `images_of` reads them.
	code_of : List(U8) -> { entries : List((Header, List(Block))), damaged : U64 }
	code_of = |bytes| {
		(text, damaged) = text_blocks(bytes)
		{ entries: code(text), damaged }
	}

	## images_store `extractImageTags`: every `<img` (any case) followed by
	## whitespace, to the next `>`.
	img_tags : Str -> List(Str)
	img_tags = |s| tags_in(s.to_utf8())

	## code_store `parseCodeFile`: every block with a header line and a body
	## holding at least one fence that is not a quote.
	code : Str -> List((Header, List(Block)))
	code = |text|
		List.fold(
			blocks_of(text.to_utf8()),
			[],
			|out, block|
				match Bytes.find_byte(block, { byte: '\n', at: 0 }) {
					Err(NotFound) => out
					Ok(nl) =>
						match header(text_of(List.take_first(block, nl))) {
							Err(NotAHeader) => out
							Ok(h) => {
								bs = List.map(
									blocks_in(List.drop_first(block, nl + 1)),
									|b| {
										..b,
										body: text_of(Transcript.unescape_body(b.body.to_utf8())),
									},
								)
								if bs == [] out else List.append(out, (h, bs))
							}
						}
				},
		)

	## code_store `extractCodeBlocks`: each fence's lines to the first close
	## of its character at least as long, or to the end; a `quote` fence's
	## lines skipped.
	code_blocks : Str -> List(Block)
	code_blocks = |body| blocks_in(body.to_utf8())

	## The Images page's JSON: the newest `most` entries, each as
	## images_store `encodeImagesEvent` writes it.
	images_json : List((Header, List(Str))), U64 -> List(U8)
	images_json = |entries, most| {
		tail = List.drop_first(entries, List.len(entries) - U64.min(most, List.len(entries)))
		JsonOut.array(List.map(tail, |(h, tags)| images_event(h, tags))).bytes()
	}

	## The Code page's JSON: every entry, as code_store `encodeCodeEvent`
	## writes it.
	code_json : List((Header, List(Block))) -> List(U8)
	code_json = |entries| JsonOut.array(List.map(entries, |(h, bs)| code_event(h, bs))).bytes()

	## images_store `encodeImagesEvent`: one entry as its page and its live
	## stream (`img:<uid>`) send it, fields in its order, none left out.
	## **NO STORED TAG REACHES THE PAGE AS WRITTEN** (metal-vmm QUEUE 266):
	## the tags are spans of a member's raw markdown, and images.js parses
	## them as HTML into the live page, so each is rebuilt by the renderer's
	## rule (SafeImg) and one it refuses is dropped. Here, where the page's
	## backlog and the live event both pass, so the entries already on disk
	## are rebuilt too.
	images_event : Header, List(Str) -> JsonOut
	images_event = |h, tags| {
		safe = List.keep_oks(tags, SafeImg.rebuild)
		JsonOut.object(
			List.concat(
				head_fields(h),
				[
					("images", JsonOut.array(List.map(safe, JsonOut.string))),
					("source_url", JsonOut.string(ChatUrl.source(h.conv, h.source_id).to_str())),
				],
			),
		)
	}

	## code_store `encodeCodeEvent`: one entry as its page and its live
	## stream (`code:<uid>`) send it.
	code_event : Header, List(Block) -> JsonOut
	code_event = |h, bs| {
		blocks = JsonOut.array(
			List.map(
				bs,
				|b| JsonOut.object([
					("lang", JsonOut.string(b.lang)),
					("body", JsonOut.string(b.body)),
				]),
			),
		)
		JsonOut.object(
			List.concat(
				head_fields(h),
				[
					("blocks", blocks),
					("source_url", JsonOut.string(ChatUrl.source(h.conv, h.source_id).to_str())),
				],
			),
		)
	}

	## images_store `formatImagesEntry`: the header, then each tag on a line
	## of its own. **A TAG IS ONE LINE** (metal-vmm QUEUE 185): a CR or LF in
	## one is a space, so no tag carries the separator and a forged header.
	## The entry's bytes are the file's (Files.append_entry!).
	images_entry : Header, List(Str) -> List(U8)
	images_entry = |h, tags|
		List.fold(
			tags,
			header_line(h),
			|out, tag| "${out}\n${tag.replace_each("\n", " ").replace_each("\r", " ")}",
		).to_utf8()

	## code_store `formatCodeEntry`: the header, then each block as a
	## backtick fence (whatever its opener was), one newline between them.
	## **NO BODY HOLDS THE SEPARATOR** (metal-vmm QUEUE 266): each body line
	## is escaped as a transcript's are (Transcript.escape_body), so a body
	## holding `sep` and a `Sent by …` header is no entry of its own, from a
	## sender who never sent it; `code` takes the escape off.
	code_entry : Header, List(Block) -> List(U8)
	code_entry = |h, bs|
		"${header_line(h)}${Str.join_with(List.map(bs, |b| "\n```${b.lang}\n${text_of(Transcript.escape_body(b.body.to_utf8()))}\n```"), "\n")}".to_utf8()
}

## **A CUT OF TEXT AT ASCII BYTES IS TEXT**: every slice the scanners
## below take of a feed's text or a message's markdown starts and ends
## at an ASCII byte (or the text's ends), so it decodes. One that does
## not is a bug here, and crashes (a 500).
text_of : List(U8) -> Str
text_of = |bytes|
	match Str.from_utf8(bytes) {
		Ok(t) => t
		Err(_) => crash "Feeds: a cut split a codepoint"
	}

## The file's blocks whose bytes are text, joined again by `sep`, and how
## many were not. A block is cut at the separator's ASCII bytes, so a torn
## character is its block's alone, and the blocks kept read as they were.
text_blocks : List(U8) -> (Str, U64)
text_blocks = |bytes| {
	(good, bad) = List.fold(
		blocks_of(bytes),
		([], 0),
		|(kept, n), b|
			match Str.from_utf8(b) {
				Ok(_) => (List.append(kept, b), n)
				Err(_) => (kept, n + 1)
			},
	)
	(text_of(List.join(List.intersperse(good, Feeds.sep))), bad)
}

## The file's blocks between separators, trimmed, the empty ones gone.
blocks_of : List(U8) -> List(List(U8))
blocks_of = |text|
	if Bytes.trim(text, Bytes.zig_spaces) == [] {
		[]
	} else {
		List.keep_if(
			List.map(List.split_on_list(text, Feeds.sep), |b| Bytes.trim(b, Bytes.zig_spaces)),
			|b| b != [],
		)
	}

tags_in : List(U8) -> List(Str)
tags_in = |s| List.map(
	img_tags_from(
		s,
		{
			at: 0,
			out: [],
			gt_seen: Unknown,
		},
	),
	text_of,
)

img_tags_from : List(U8),
{
	at : U64,
	out : List(List(U8)),
	gt_seen : Bytes.Seen,
} -> List(List(U8))
img_tags_from = |
	s,
	{
		at: i,
		out,
		gt_seen,
	},
|
	if i >= List.len(s) {
		out
	} else {
		match List.sublist(s, { start: i, len: 5 }) {
			[
				a,
				b,
				c,
				d,
				e,
			] if List.map(
				[
					a,
					b,
					c,
					d,
				],
				Ascii.to_lowercase,
			) == Str.to_utf8("<img") and Ascii.is_whitespace(e) =>
				match Bytes.find_seen(
					s,
					{
						byte: '>',
						from: i + 4,
						seen: gt_seen,
					},
				) {
					(Ok(gt), seen) => img_tags_from(
						s,
						{
							at: gt + 1,
							out: List.append(out, List.sublist(s, { start: i, len: gt + 1 - i })),
							gt_seen: seen,
						},
					)
					(Err(NotFound), seen) => img_tags_from(
						s,
						{
							at: i + 1,
							out,
							gt_seen: seen,
						},
					)
				}
			_ => img_tags_from(
				s,
				{
					at: i + 1,
					out,
					gt_seen,
				},
			)
		}
	}

blocks_in : List(U8) -> List(Block)
blocks_in = |body| blocks_from(List.split_on(body, '\n'), { at: 0, out: [] })

blocks_from : List(List(U8)), { at : U64, out : List(Block) } -> List(Block)
blocks_from = |ls, { at: i, out }|
	match List.get(ls, i) {
		Err(_) => out
		Ok(line) =>
			match Fence.fence_open(line) {
				Err(NotAFence) => blocks_from(ls, { at: i + 1, out })
				Ok(fo) => {
					j = Fence.close_at(
						ls,
						{
							char: fo.char,
							count: fo.count,
							at: i + 1,
						},
					)
					body = Bytes.join_lines(List.sublist(ls, { start: i + 1, len: j - (i + 1) }))
					blocks_from(
						ls,
						{
							at: j + 1,
							out: if fo.lang == Str.to_utf8("quote") out else List.append(
								out,
								{ lang: text_of(fo.lang), body: text_of(body) },
							),
						},
					)
				}
			}
	}

## The fields every feed entry starts with, from its header.
head_fields : Header -> List((Str, JsonOut))
head_fields = |h| [
	("source_id", JsonOut.string(h.source_id)),
	("from", JsonOut.string(h.from)),
	("conv", JsonOut.string(h.conv)),
	("at", JsonOut.string(h.at)),
]

## The header line every entry starts with, as `header` reads it back.
header_line : Header -> Str
header_line = |h| "Sent by ${h.from} at ${h.at}, source MSG_${h.source_id} in ${h.conv}:"

# header: the last " at " before the source, the first " in " after it.
expect Feeds.header("Sent by a at b at c, source MSG_x_1 in 1_2 in 3:") == Ok({
	from: "a at b",
	at: "c",
	source_id: "x_1",
	conv: "1_2 in 3",
})
expect Feeds.header("Sent by ann at t, source MSG_x_1 in 1_2") == Err(NotAHeader)
# code_entry and code: a body holding the separator and a forged header stays one entry, from its real sender, and reads back as sent.
expect {
	forged = "x\n\n-------------\n\nSent by Mallory at 2026-01-01T00:00:00Z, source MSG_f_1 in 1_2:\n\\-------------\ny"
	real = Feeds.code_entry(
		{
			from: "ann",
			at: "2026-10-27T00:00:00Z",
			source_id: "t_1",
			conv: "1_2",
		},
		[{ lang: "", body: forged }],
	)
	other = Feeds.code_entry(
		{
			from: "bob",
			at: "2026-10-27T00:00:01Z",
			source_id: "t_2",
			conv: "1_2",
		},
		[{ lang: "zig", body: "ok" }],
	)
	back = Feeds.code(
		text_of(
			List.join([
				real,
				Feeds.sep,
				other,
			]),
		),
	)
	List.map(
		back,
		|(h, bs)| (h.from, List.map(bs, |b| b.body)),
	) == [("ann", [forged]), ("bob", ["ok"])]
}
# images_of and code_of: an entry torn mid-character is skipped and counted, the others read.
expect {
	h = |id| Str.to_utf8("Sent by ann at t, source MSG_${id} in 1_2:\n")
	file = List.join([
		h("a_1"),
		Str.to_utf8("<img src=\"/a.png\">"),
		Feeds.sep,
		h("a_2"),
		[0xf0, 0x9f],
		Feeds.sep,
		h("a_3"),
		Str.to_utf8("<img src=\"/c.png\">"),
	])
	got = Feeds.images_of(file)
	got.damaged == 1 and List.map(got.entries, |(hd, _)| hd.source_id) == ["a_1", "a_3"]
}
expect {
	file = List.join([
		Str.to_utf8("Sent by ann at t, source MSG_c_1 in 1_2:\n```\nx\n```"),
		Feeds.sep,
		Str.to_utf8("Sent by ann at t, source MSG_c_2 in 1_2:\n```\n"),
		[0xff],
		Str.to_utf8("\n```"),
	])
	got = Feeds.code_of(file)
	got.damaged == 1 and List.map(got.entries, |(hd, _)| hd.source_id) == ["c_1"]
}
expect Feeds.images_of(Str.to_utf8("Sent by ann at t, source MSG_a_1 in 1_2:\n<img src=\"/a.png\">")).damaged == 0
# images_event: a stored tag rebuilt by the renderer's rule, a hostile one dropped (images_store's plants).
expect {
	json = Str.from_utf8(
		Feeds.images_event(
			{
				from: "ann",
				at: "2026-10-27T00:00:00Z",
				source_id: "t_1",
				conv: "1_2",
			},
			[
				"<img src=x onerror=\"alert(1)\">",
				"<img src=\"/up/a.png\" width=\"40\" onload=\"alert(2)\">",
				"<img src=\"https://evil.example/t.png\">",
			],
		).bytes(),
	)
	json == Ok("{\"source_id\":\"t_1\",\"from\":\"ann\",\"conv\":\"1_2\",\"at\":\"2026-10-27T00:00:00Z\",\"images\":[\"<img src=\\\"/up/a.png\\\" width=\\\"40\\\">\"],\"source_url\":\"/chat/c/1_2/t#msg-t_1\"}")
}
expect Feeds.images_entry(
	{
		from: "Zo\u(eb)",
		at: "t",
		source_id: "x_1",
		conv: "ops",
	},
	["<img\r\na>"],
) == Str.to_utf8("Sent by Zo\u(eb) at t, source MSG_x_1 in ops:\n<img  a>")
