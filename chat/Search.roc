## **SEARCH'S WORDS, THE ROC'S** (angry-gopher chat_search.zig `handle` and
## search_tokens.zig `key` as they were, metal-vmm QUEUE 281): what was
## typed made a key as the index holds words, and the answer's JSON. The
## index and the rate limit are the host's (Host.search_words!,
## Host.admit!); which conversations a search walks is the Roc's
## (`scope`). Pure.
import JsonOut
import Ascii
import Bytes
import Paths
import Uid

Search := [].{

	## **WHAT A MEMBER'S SEARCH WALKS** (angry-gopher chat_paths.zig
	## `visibleConvs`, which /admin/search walks still): a DM with every
	## other one the roster lists (`roster`, Accounts.authorized's: every
	## member and the agent, by id), then each of the member's channels
	## (`channels`, Paths.member_channels's: sorted by bytes) whose name is a
	## channel's, in that order. **NARROWER THAN THE ROUTES, ON PURPOSE**, as
	## the sidebar lists them: never the DM with oneself, nor one with a
	## guest, an account with no password or one retired, which the DM route
	## would open. The host walks exactly these (Host.search_scope_add!).
	scope : {
		me : Uid,
		roster : List({ id : Uid, name : Str }),
		channels : List(Str),
	} -> List(Paths.ConvKey)
	scope = |
		{
			me,
			roster,
			channels,
		},
	|
		List.concat(
			List.keep_if(roster, |u| u.id != me)
				|> List.map(|u| Dm(Paths.pair_key(me, u.id))),
			List.keep_oks(
				channels,
				|name| Paths.channel_name_from_str(name).map_ok(|valid| Channel(valid)),
			),
		)

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
		t = trim_word(Bytes.trim(typed, Bytes.zig_spaces))
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

	## A message the index found, as the host hands it: its conversation by
	## its place in the scope (`conv`), and its excerpt's window
	## (Host.search_messages!).
	Hit : {
		at : U64,
		conv : U64,
		length : U64,
		start : U64,
		date : List(U8),
		from : List(U8),
		id : List(U8),
		sid : List(U8),
		window : List(U8),
		found : [Found, Missing],
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
				start = U64.min(edge_fwd(h, U64.minus_saturated(at, excerpt_pad)), at)
				end = U64.max(edge_back(h, U64.min(len, at + key_len + excerpt_pad)), at + key_len)
				{
					before: List.concat(if start > 0 ellipsis else [], slice(start, at)),
					mark: slice(at, at + key_len),
					after: List.concat(slice(at + key_len, end), trail(end)),
				}
			}
			Missing => {
				end = edge_back(h, U64.min(len, 2 * excerpt_pad))
				{
					before: [],
					mark: [],
					after: List.concat(slice(0, end), trail(end)),
				}
			}
		}
	}

	## The answer: `{"word":…,"matched":N,"unreadable":N,"messages":[{"conv":…,"kind":…,"sid":…,"id":…,"from":…,"date":…,"before":…,"mark":…,"after":…},…]}`,
	## each hit's conversation (its URL base and kind) the one at its place
	## in `scope`, the list the host walked.
	messages_json : List(U8),
	{
		matched : U64,
		unreadable : U64,
		hits : List(Hit),
		scope : List(Paths.ConvKey),
	} -> List(U8)
	messages_json = |
		word,
		{
			matched,
			unreadable,
			hits,
			scope: walked,
		},
	|
		JsonOut.object([
			("word", JsonOut.lossy(word)),
			("matched", JsonOut.number(matched)),
			("unreadable", JsonOut.number(unreadable)),
			(
				"messages",
				JsonOut.array(
					List.map(
						hits,
						|h| hit_json(h, { key_len: List.len(word), key: in_scope(walked, h.conv) }),
					),
				),
			),
		]).bytes()

	## The answer: `{"prefix":…,"most":20,"unreadable":N,"words":[{"word":…,"count":N},…]}`.
	words_json : List(U8),
	{
		unreadable : U64,
		words : List({ count : U64, word : List(U8) }),
	} -> List(U8)
	words_json = |prefix, { unreadable, words }|
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

## The conversation at place `at` of the scope the host walked. **A PLACE
## PAST IT IS THE HOST'S BUG**: a crash (a 500), never a hit shown under
## another conversation.
in_scope : List(Paths.ConvKey), U64 -> Paths.ConvKey
in_scope = |scope, at|
	match List.get(scope, at) {
		Ok(key) => key
		Err(_) => crash "Search: a hit's conversation past the scope the host was handed"
	}

hit_json : Search.Hit, { key_len : U64, key : Paths.ConvKey } -> JsonOut
hit_json = |h, { key_len, key }| {
	ex = Search.excerpt(h, key_len)
	JsonOut.object([
		("conv", JsonOut.string(key.base())),
		("kind", JsonOut.string(if key.kind() == Dm "dm" else "channel")),
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
		(Ok(c), _) if Ascii.is_punctuation(c) => trim_word(List.drop_first(w, 1))
		(_, Ok(c)) if Ascii.is_punctuation(c) => trim_word(List.drop_last(w, 1))
		_ =>
			match List.find_first(trimmed, |t| List.starts_with(w, t) or List.ends_with(w, t)) {
				Ok(t) => trim_word(
					if List.starts_with(w, t) List.drop_first(
						w,
						List.len(t),
					) else List.drop_last(w, List.len(t)),
				)
				Err(_) => w
			}
	}

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

# scope: a DM with each other one on the roster, in its order, never with
# oneself; then each channel whose name is a channel's, in the order given;
# each conversation's folder as the index knows it.
expect {
	roster = List.keep_oks(
		[
			"3",
			"7",
			"10",
		],
		|id| Uid.from_str(id).map_ok(|uid| { id: uid, name: "" }),
	)
	match Uid.from_str("7") {
		Ok(me) => {
			walked = Search.scope({
				me,
				roster,
				channels: [
					"Zed",
					"9lives",
					"ops",
				],
			})
			List.map(walked, |k| Paths.conv_folder(k).bytes())
				== List.map(
					[
						"3_7",
						"7_10",
						"channels/Zed",
						"channels/ops",
					],
					Str.to_utf8,
				)
		}
		Err(_) => Bool.False
	}
}

# key: spaces and edge punctuation trimmed, ASCII folded, a curly quote gone.
expect Search.key(Str.to_utf8(" \"La\u(201D)! ")) == Str.to_utf8("la") and Search.key(Str.to_utf8("CAF\u(C9)")) == Str.to_utf8("caf\u(C9)") and Search.key(
	List.repeat(
		'a',
		257,
	),
) == []
