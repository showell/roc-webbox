## **JSON BUILT, NOT SPLICED** (metal-vmm QUEUE 269): a value is made only
## by this module's builders (string, number, bool, array, object), so a
## JSON field's bytes are always a whole value, escaped as Zig's std.json
## writes them (the builtin `Json.to_str` of a Str, byte for byte; its
## records' fields come out sorted, so a record goes through `object`, never
## `Json.to_str`): no spaces, fields and items in the
## order given. Opaque (`::`); `bytes` is the only way out. Pure.

JsonOut :: List(U8).{

	## A string, escaped.
	string : Str -> JsonOut
	string = |s| JsonOut.(Json.to_str(s).to_utf8())

	## Bytes as a string, as chat_search.zig's `str` writes them: each byte
	## that does not begin a whole UTF-8 sequence is U+FFFD (a word the
	## index read from a transcript, a key typed as `%FF`). **Kept on purpose:**
	## `Str.from_utf8_lossy` gives one U+FFFD per bad sequence, not per byte.
	lossy : List(U8) -> JsonOut
	lossy = |b| string(
		whole_or_replaced(b, { at: 0, out: "" }),
	)

	## Bytes as std.json writes a `[]const u8` (a backlog frame's fields,
	## Frame.stored): a string when they are UTF-8, else an array of their
	## numbers. **Kept on purpose:** `lossy` is chat_search's, a U+FFFD for
	## each bad byte.
	zig_bytes : List(U8) -> JsonOut
	zig_bytes = |b|
		match Str.from_utf8(b) {
			Ok(s) => string(s)
			Err(_) => array(List.map(b, |c| number(U8.to_u64(c))))
		}

	## A whole number, in decimal.
	number : U64 -> JsonOut
	number = |n| JsonOut.(Str.to_utf8(U64.to_str(n)))

	## A signed whole number, in decimal.
	signed : I64 -> JsonOut
	signed = |n| JsonOut.(Str.to_utf8(I64.to_str(n)))

	## `true` or `false`.
	bool : Bool -> JsonOut
	bool = |b| JsonOut.(Str.to_utf8(if b "true" else "false"))

	## The values in order: `[a,b]`.
	array : List(JsonOut) -> JsonOut
	array = |items| JsonOut.(
		List.join([
			['['],
			comma(List.map(items, bytes)),
			[']'],
		]),
	)

	## The fields in order, each a name and a value: `{"name":value,...}`.
	## A name is escaped as a string is.
	object : List((Str, JsonOut)) -> JsonOut
	object = |fields| JsonOut.(
		List.join([
			['{'],
			comma(
				List.map(
					fields,
					|(name, value)| List.join([
						Json.to_str(name).to_utf8(),
						[':'],
						bytes(value),
					]),
				),
			),
			['}'],
		]),
	)

	## A string field, or none when `s` is empty (an encoder that leaves an
	## empty field out): for `object(List.join([..., optional("url", key), ...]))`.
	optional : Str, Str -> List((Str, JsonOut))
	optional = |name, s| if s == "" [] else [(name, string(s))]

	## The value's bytes.
	bytes : JsonOut -> List(U8)
	bytes = |JsonOut.(b)| b
}

whole_or_replaced : List(U8), { at : U64, out : Str } -> Str
whole_or_replaced = |b, { at: i, out }|
	match List.get(b, i) {
		Err(_) => out
		Ok(c) => {
			n = sequence_length(c)
			whole = if n > 0 and i + n <= List.len(b) Str.from_utf8(
				List.sublist(
					b,
					{ start: i, len: n },
				),
			) else Err(Short)
			match whole {
				Ok(text) => whole_or_replaced(b, { at: i + n, out: Str.concat(out, text) })
				Err(_) => whole_or_replaced(b, { at: i + 1, out: Str.concat(out, "\u(fffd)") })
			}
		}
	}

## std.unicode.utf8ByteSequenceLength: from a sequence's first byte, or 0
## for a byte no sequence begins with.
sequence_length : U8 -> U64
sequence_length = |c|
	if c < 0x80 {
		1
	} else if c >= 0xC0 and c < 0xE0 {
		2
	} else if c >= 0xE0 and c < 0xF0 {
		3
	} else if c >= 0xF0 and c < 0xF8 {
		4
	} else {
		0
	}

comma : List(List(U8)) -> List(U8)
comma = |items| List.join(List.intersperse(items, [',']))

expect JsonOut.object([
	("a", JsonOut.number(1)),
	("b", JsonOut.array([JsonOut.string("x\"y"), JsonOut.bool(Bool.False)])),
]).bytes() == Str.to_utf8("{\"a\":1,\"b\":[\"x\\\"y\",false]}")
expect JsonOut.object([]).bytes() == Str.to_utf8("{}")
expect JsonOut.array([]).bytes() == Str.to_utf8("[]")
expect JsonOut.signed(-3).bytes() == Str.to_utf8("-3")
# zig_bytes: text is a string; bytes that are not are their numbers.
expect JsonOut.zig_bytes(Str.to_utf8("a\"b")).bytes() == Str.to_utf8("\"a\\\"b\"")
expect JsonOut.zig_bytes([0x42, 0xFF]).bytes() == Str.to_utf8("[66,255]")
expect JsonOut.zig_bytes([]).bytes() == Str.to_utf8("\"\"")
# lossy: a torn sequence is one U+FFFD a byte; a whole one passes.
expect JsonOut.lossy([
	0x6C,
	0x61,
	0xFF,
	0xE2,
	0x82,
]).bytes() == Str.to_utf8("\"la\u(fffd)\u(fffd)\u(fffd)\"") and JsonOut.lossy(Str.to_utf8("caf\u(e9)")).bytes() == Str.to_utf8("\"caf\u(e9)\"")
