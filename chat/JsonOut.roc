## **JSON BUILT, NOT SPLICED** (metal-vmm QUEUE 269): a value is made only
## by this module's builders (string, number, bool, array, object), so a
## JSON field's bytes are always a whole value, escaped as Zig's std.json
## writes them (ZigText.json_string): no spaces, fields and items in the
## order given. Opaque (`::`); `bytes` is the only way out. Pure.
import ZigText

JsonOut :: List(U8).{

	## A string, escaped.
	string : Str -> JsonOut
	string = |s| JsonOut.(ZigText.json_string(s))

	## Bytes as a string, as chat_search.zig's `str` writes them: each byte
	## that does not begin a whole UTF-8 sequence is U+FFFD (a word the
	## index read from a transcript, a key typed as `%FF`).
	lossy : List(U8) -> JsonOut
	lossy = |b| string(
		whole_or_replaced(
			b,
			0,
			"",
		),
	)

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
						ZigText.json_string(name),
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

whole_or_replaced : List(U8), U64, Str -> Str
whole_or_replaced = |
	b,
	i,
	out,
|
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
				Ok(text) => whole_or_replaced(
					b,
					i + n,
					Str.concat(out, text),
				)
				Err(_) => whole_or_replaced(
					b,
					i + 1,
					Str.concat(out, "\u(fffd)"),
				)
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
# lossy: a torn sequence is one U+FFFD a byte; a whole one passes.
expect JsonOut.lossy([
	0x6C,
	0x61,
	0xFF,
	0xE2,
	0x82,
]).bytes() == Str.to_utf8("\"la\u(fffd)\u(fffd)\u(fffd)\"") and JsonOut.lossy(Str.to_utf8("caf\u(e9)")).bytes() == Str.to_utf8("\"caf\u(e9)\"")
