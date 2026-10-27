## JSON AS THE ZIG WRITES IT: no spaces, fields in the order given, strings
## escaped as ZigText.json_string escapes them (angry-gopher's encoders).
## A value is its bytes, already written; an object is its fields in order,
## each a name and a value. Pure.
import ZigText

JsonText := [].{

	## A string value.
	str : Str -> List(U8)
	str = |s| ZigText.json_string(s)

	## TEMPORARY DOOR: moves out in a later run. A string value from bytes
	## not yet decoded: text as `str` writes it; bytes that are not UTF-8
	## are no string to Zig's std.json.fmt, which writes them as an array of
	## byte numbers.
	str_at_door : List(U8) -> List(U8)
	str_at_door = |s|
		match Str.from_utf8(s) {
			Ok(t) => str(t)
			Err(_) => arr(List.map(s, |c| Str.to_utf8(U8.to_str(c))))
		}

	bool : Bool -> List(U8)
	bool = |b| if b Str.to_utf8("true") else Str.to_utf8("false")

	## An object of `fields`, in order: `{"name":value,...}`.
	obj : List((Str, List(U8))) -> List(U8)
	obj = |fields| List.join([['{'], comma(List.map(fields, |(name, value)| List.concat(Str.to_utf8("\"${name}\":"), value))), ['}']])

	## An array of values, in order: `[a,b]`.
	arr : List(List(U8)) -> List(U8)
	arr = |items| List.join([['['], comma(items), [']']])

	## A string field, or none when `s` is empty (an encoder that leaves an
	## empty field out): for `obj(List.join([..., opt("url", key), ...]))`.
	opt : Str, Str -> List((Str, List(U8)))
	opt = |name, s| if s == "" [] else [(name, str(s))]

	## TEMPORARY DOOR: moves out in a later run. `opt` of bytes not yet
	## decoded, written as `str_at_door` writes them.
	opt_at_door : Str, List(U8) -> List((Str, List(U8)))
	opt_at_door = |name, s| if s == [] [] else [(name, str_at_door(s))]

	comma : List(List(U8)) -> List(U8)
	comma = |items| List.join(List.intersperse(items, [',']))
}

# str: text escaped, a character past ASCII as its own UTF-8.
expect JsonText.str("caf\u(e9) \"q\"\n") == Str.to_utf8("\"caf\u(e9) \\\"q\\\"\\n\"")
expect JsonText.str("👍") == Str.to_utf8("\"👍\"")
expect JsonText.opt("who", "") == []

# str_at_door: UTF-8 decodes, multibyte included; bytes that are not UTF-8
# are refused as text and written as Zig writes them, an array of numbers.
expect JsonText.str_at_door(Str.to_utf8("caf\u(e9)")) == Str.to_utf8("\"caf\u(e9)\"")
expect JsonText.str_at_door(Str.to_utf8("👍")) == Str.to_utf8("\"👍\"")
expect JsonText.str_at_door([0xc3]) == Str.to_utf8("[195]")
expect JsonText.str_at_door([0x61, 0xff]) == Str.to_utf8("[97,255]")
expect JsonText.str_at_door([]) == Str.to_utf8("\"\"")
expect JsonText.opt_at_door("who", [0xff]) == [("who", Str.to_utf8("[255]"))]
