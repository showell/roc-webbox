## **SEARCH'S WORDS, THE ROC'S** (angry-gopher chat_search.zig `handle` and
## search_tokens.zig `key` as they were, metal-vmm QUEUE 281): what was
## typed made a key as the index holds words, and the answer's JSON. The
## index and the rate limit are the host's (Host.search_words!,
## Host.admit!). Pure.
import ZigText
import JsonOut

Search := [].{

	## The longest word a key can name, in bytes (search_tokens `max_word`).
	max_word : U64
	max_word = 256

	## The most words an answer suggests (chat_search `most_words`).
	most_words : U64
	most_words = 20

	## search_tokens `key`: `typed` trimmed of whitespace, then of a word's
	## edge punctuation, then ASCII-lowercased; empty past `max_word`.
	key : List(U8) -> List(U8)
	key = |typed| {
		t = trim_word(ZigText.trim(typed))
		if List.len(t) > max_word [] else List.map(t, |c| if c >= 'A' and c <= 'Z' c + 32 else c)
	}

	## The most messages an answer lists (chat_search `most_messages`).
	most_messages : U64
	most_messages = 500

	## The shortest word a search finds (search_tokens `min_len`).
	min_len : U64
	min_len = 2

	## Bytes of a message either side of the word in its excerpt
	## (chat_search `excerpt_pad`).
	excerpt_pad : U64
	excerpt_pad = 90

	## A message the index found, as the host hands it: its excerpt's window
	## (Host.search_messages!).
	Hit : {
		at : U64,
		length : U64,
		start : U64,
		base : List(U8),
		date : List(U8),
		from : List(U8),
		id : List(U8),
		sid : List(U8),
		window : List(U8),
		found : [Found, Missing],
		kind : [Channel, Dm],
	}

	## chat_search `excerptOf`: the word as written, where the index found
	## it, and up to `excerpt_pad` bytes either side, cut on a character's
	## edge, "…" where cut; **NEVER ACROSS THE WORD** (a word may begin or
	## end in stray continuation bytes). A hit whose word was not found is
	## its first bytes, unmarked.
	excerpt : Hit,
	U64 -> {
		before : List(U8),
		mark : List(U8),
		after : List(U8),
	}
	excerpt = |h, key_len| {
		len = h.length
		slice = |a, b| List.sublist(h.window, { start: a - h.start, len: b - a })
		trail = |end| if end < len ellipsis else []
		match h.found {
			Found => {
				at = h.at
				start = lesser(edge_fwd(h, sub_floor(at, excerpt_pad)), at)
				end = greater(edge_back(h, lesser(len, at + key_len + excerpt_pad)), at + key_len)
				{
					before: List.concat(if start > 0 ellipsis else [], slice(start, at)),
					mark: slice(at, at + key_len),
					after: List.concat(slice(at + key_len, end), trail(end)),
				}
			}
			Missing => {
				end = edge_back(h, lesser(len, 2 * excerpt_pad))
				{
					before: [],
					mark: [],
					after: List.concat(slice(0, end), trail(end)),
				}
			}
		}
	}

	## The answer: `{"word":…,"matched":N,"unreadable":N,"messages":[{"conv":…,"kind":…,"sid":…,"id":…,"from":…,"date":…,"before":…,"mark":…,"after":…},…]}`.
	messages_json : List(U8), U64, U64, List(Hit) -> List(U8)
	messages_json = |
		word,
		matched,
		unreadable,
		hits,
	|
		JsonOut.object([
			("word", JsonOut.lossy(word)),
			("matched", JsonOut.number(matched)),
			("unreadable", JsonOut.number(unreadable)),
			("messages", JsonOut.array(List.map(hits, |h| hit_json(h, List.len(word))))),
		]).bytes()

	## The answer: `{"prefix":…,"most":20,"unreadable":N,"words":[{"word":…,"count":N},…]}`.
	words_json : List(U8), U64, List({ count : U64, word : List(U8) }) -> List(U8)
	words_json = |
		prefix,
		unreadable,
		words,
	|
		JsonOut.object([
			("prefix", JsonOut.lossy(prefix)),
			("most", JsonOut.number(most_words)),
			("unreadable", JsonOut.number(unreadable)),
			(
				"words",
				JsonOut.array(
					List.map(
						words,
						|w| JsonOut.object([
							("word", JsonOut.lossy(w.word)),
							("count", JsonOut.number(w.count)),
						]),
					),
				),
			),
		]).bytes()
}

hit_json : Search.Hit, U64 -> JsonOut
hit_json = |h, key_len| {
	ex = Search.excerpt(h, key_len)
	JsonOut.object([
		("conv", JsonOut.lossy(h.base)),
		("kind", JsonOut.string(if h.kind == Dm "dm" else "channel")),
		("sid", JsonOut.lossy(h.sid)),
		("id", JsonOut.lossy(h.id)),
		("from", JsonOut.lossy(h.from)),
		("date", JsonOut.lossy(h.date)),
		("before", JsonOut.lossy(ex.before)),
		("mark", JsonOut.lossy(ex.mark)),
		("after", JsonOut.lossy(ex.after)),
	])
}

ellipsis : List(U8)
ellipsis = Str.to_utf8("\u(2026)")

lesser : U64, U64 -> U64
lesser = |a, b| if a < b a else b

greater : U64, U64 -> U64
greater = |a, b| if a > b a else b

## `a - b`, or 0 (Zig's `-|`).
sub_floor : U64, U64 -> U64
sub_floor = |a, b| if a > b a - b else 0

## Whether the message's byte at `p` continues a UTF-8 sequence (a byte past
## the window answers no).
is_continuation : Search.Hit, U64 -> Bool
is_continuation = |h, p|
	if p < h.start {
		Bool.False
	} else {
		match List.get(h.window, p - h.start) {
			Ok(b) => b >= 0x80 and b < 0xC0
			Err(_) => Bool.False
		}
	}

## charEdgeFwd: `i`, or the next character's start after it.
edge_fwd : Search.Hit, U64 -> U64
edge_fwd = |h, i| if i < h.length and is_continuation(h, i) edge_fwd(h, i + 1) else i

## charEdgeBack: `i`, or the start of the character it falls inside.
edge_back : Search.Hit, U64 -> U64
edge_back = |h, i| if i > 0 and i < h.length and is_continuation(h, i) edge_back(h, i - 1) else i

## search_tokens `trim`: from both ends, until neither is ASCII punctuation
## or one of `trimmed`, each tried at the front, then the back, in order.
trim_word : List(U8) -> List(U8)
trim_word = |w|
	match (List.first(w), List.last(w)) {
		(Ok(c), _) if is_ascii_punct(c) => trim_word(List.drop_first(w, 1))
		(_, Ok(c)) if is_ascii_punct(c) => trim_word(List.drop_last(w, 1))
		_ =>
			match List.find_first(trimmed, |t| has_prefix(w, t) or has_suffix(w, t)) {
				Ok(t) => trim_word(
					if has_prefix(w, t) List.drop_first(
						w,
						List.len(t),
					) else List.drop_last(w, List.len(t)),
				)
				Err(_) => w
			}
	}

is_ascii_punct : U8 -> Bool
is_ascii_punct = |c| (c >= '!' and c <= '/') or (c >= ':' and c <= '@') or (c >= '[' and c <= '`') or (c >= '{' and c <= '~')

has_prefix : List(U8), List(U8) -> Bool
has_prefix = |w, t| List.take_first(w, List.len(t)) == t

has_suffix : List(U8), List(U8) -> Bool
has_suffix = |w, t| List.len(w) >= List.len(t) and List.take_last(w, List.len(t)) == t

## search_tokens `trimmed`: quotes, guillemets, the ellipsis and dashes, the
## inverted marks, the primes, the no-break space.
trimmed : List(List(U8))
trimmed = List.map(
	[
		"\u(2018)",
		"\u(2019)",
		"\u(201A)",
		"\u(201B)",
		"\u(201C)",
		"\u(201D)",
		"\u(201E)",
		"\u(201F)",
		"\u(00AB)",
		"\u(00BB)",
		"\u(2039)",
		"\u(203A)",
		"\u(2026)",
		"\u(2013)",
		"\u(2014)",
		"\u(2015)",
		"\u(00A1)",
		"\u(00BF)",
		"\u(2032)",
		"\u(2033)",
		"\u(00A0)",
	],
	Str.to_utf8,
)

# key: spaces and edge punctuation trimmed, ASCII folded, a curly quote gone.
expect Search.key(Str.to_utf8(" \"La\u(201D)! ")) == Str.to_utf8("la") and Search.key(Str.to_utf8("CAF\u(C9)")) == Str.to_utf8("caf\u(C9)") and Search.key(
	List.repeat(
		'a',
		257,
	),
) == []
