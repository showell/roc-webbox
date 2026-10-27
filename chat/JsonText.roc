## JSON AS THE ZIG WRITES IT: no spaces, fields in the order given, strings
## escaped as ZigText.json_string escapes them (angry-gopher's encoders).
## A value is its bytes, already written; an object is its fields in order,
## each a name and a value. Pure.
import ZigText

JsonText := [].{
	## A string value.
	str : List(U8) -> List(U8)
	str = |s| ZigText.json_string(s)

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
	opt : Str, List(U8) -> List((Str, List(U8)))
	opt = |name, s| if s == [] [] else [(name, str(s))]

	comma : List(List(U8)) -> List(U8)
	comma = |items| List.join(List.intersperse(items, [',']))
}
