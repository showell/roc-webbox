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

	## The answer: `{"prefix":…,"most":20,"unreadable":N,"words":[{"word":…,"count":N},…]}`.
	words_json : List(U8), U64, List({ count : U64, word : List(U8) }) -> List(U8)
	words_json = |prefix, unreadable, words|
		JsonOut.object([
			("prefix", JsonOut.lossy(prefix)),
			("most", JsonOut.number(most_words)),
			("unreadable", JsonOut.number(unreadable)),
			("words", JsonOut.array(List.map(words, |w| JsonOut.object([("word", JsonOut.lossy(w.word)), ("count", JsonOut.number(w.count))])))),
		]).bytes()
}

## search_tokens `trim`: from both ends, until neither is ASCII punctuation
## or one of `trimmed`, each tried at the front, then the back, in order.
trim_word : List(U8) -> List(U8)
trim_word = |w|
	match (List.first(w), List.last(w)) {
		(Ok(c), _) if is_ascii_punct(c) => trim_word(List.drop_first(w, 1))
		(_, Ok(c)) if is_ascii_punct(c) => trim_word(List.drop_last(w, 1))
		_ =>
			match List.find_first(trimmed, |t| has_prefix(w, t) or has_suffix(w, t)) {
				Ok(t) => trim_word(if has_prefix(w, t) List.drop_first(w, List.len(t)) else List.drop_last(w, List.len(t)))
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
	["\u(2018)", "\u(2019)", "\u(201A)", "\u(201B)", "\u(201C)", "\u(201D)", "\u(201E)", "\u(201F)", "\u(00AB)", "\u(00BB)", "\u(2039)", "\u(203A)", "\u(2026)", "\u(2013)", "\u(2014)", "\u(2015)", "\u(00A1)", "\u(00BF)", "\u(2032)", "\u(2033)", "\u(00A0)"],
	Str.to_utf8,
)

# key: spaces and edge punctuation trimmed, ASCII folded, a curly quote gone.
expect Search.key(Str.to_utf8(" \"La\u(201D)! ")) == Str.to_utf8("la") and Search.key(Str.to_utf8("CAF\u(C9)")) == Str.to_utf8("caf\u(C9)") and Search.key(List.repeat('a', 257)) == []
