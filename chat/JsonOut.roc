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
	array = |items| JsonOut.(List.join([['['], comma(List.map(items, bytes)), [']']]))

	## The fields in order, each a name and a value: `{"name":value,...}`.
	## A name is escaped as a string is.
	object : List((Str, JsonOut)) -> JsonOut
	object = |fields| JsonOut.(List.join([['{'], comma(List.map(fields, |(name, value)| List.join([ZigText.json_string(name), [':'], bytes(value)]))), ['}']]))

	## The value's bytes.
	bytes : JsonOut -> List(U8)
	bytes = |JsonOut.(b)| b
}

comma : List(List(U8)) -> List(U8)
comma = |items| List.join(List.intersperse(items, [',']))

expect JsonOut.object([("a", JsonOut.number(1)), ("b", JsonOut.array([JsonOut.string("x\"y"), JsonOut.bool(Bool.False)]))]).bytes() == Str.to_utf8("{\"a\":1,\"b\":[\"x\\\"y\",false]}")
expect JsonOut.object([]).bytes() == Str.to_utf8("{}")
expect JsonOut.array([]).bytes() == Str.to_utf8("[]")
expect JsonOut.signed(-3).bytes() == Str.to_utf8("-3")
