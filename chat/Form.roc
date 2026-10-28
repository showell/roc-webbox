## A FORM'S FIELDS (zig-webbox http.zig's formField and formDecode, the one
## decoder every form on the site reads with): `a=b&c=d`, `+` a space and
## `%XX` a byte. A `%` that is not two hex digits, or a field sent twice, is
## malformed: the client's mistake, which the site answers 400.
##
## **A FORM IS TEXT AT THE DOOR**: a value that is not UTF-8 once decoded
## is malformed too, so no field past here is bytes.
import Bytes
import Ascii

Form := [].{
	Field : [
		Found(Str),
		Missing,
		Malformed,
	]

	## A query's or a form's value, as written, decoded (formDecode: `+` a
	## space, `%XX` a byte), or `BadEscape`.
	value : List(U8) -> Try(List(U8), [BadEscape])
	value = |raw| decode(raw)

	## formField: the value of field `name`. A pair with no `=` is passed
	## over.
	field : List(U8), Str -> Field
	field = |body, name| {
		key = Str.to_utf8(name)
		values = List.keep_oks(
			List.split_on(body, '&'),
			|pair|
				match Bytes.cut_seq(pair, ['=']) {
					Ok((k, v)) if k == key => Ok(v)
					_ => Err(OtherField)
				},
		)
		match values {
			[] => Missing
			[raw] =>
				match decode(raw).map_ok(Str.from_utf8) {
					Ok(Ok(v)) => Found(v)
					Ok(Err(_)) | Err(BadEscape) => Malformed
				}
			_ => Malformed
		}
	}
}

## formDecode, or `BadEscape` for a `%` that is not two hex digits.
decode : List(U8) -> Try(List(U8), [BadEscape])
decode = |raw| decode_from(raw, { at: 0, out: [] })

decode_from : List(U8), { at : U64, out : List(U8) } -> Try(List(U8), [BadEscape])
decode_from = |raw, { at: i, out }| match List.get(raw, i) {
	Err(_) => Ok(out)
	Ok('+') => decode_from(raw, { at: i + 1, out: List.append(out, ' ') })
	Ok('%') =>
		match (List.get(raw, i + 1), List.get(raw, i + 2)) {
			(Ok(h), Ok(l)) =>
				match (hex(h), hex(l)) {
					(Ok(hi), Ok(lo)) => decode_from(
						raw,
						{ at: i + 3, out: List.append(out, hi * 16 + lo) },
					)
					_ => Err(BadEscape)
				}
			_ => Err(BadEscape)
		}
	Ok(c) => decode_from(raw, { at: i + 1, out: List.append(out, c) })
}

hex : U8 -> Try(U8, [NotHex])
hex = |c|
	match c {
		_ if Ascii.is_digit(c) => Ok(c - '0')
		_ if c >= 'a' and c <= 'f' => Ok(c - 'a' + 10)
		_ if c >= 'A' and c <= 'F' => Ok(c - 'A' + 10)
		_ => Err(NotHex)
	}

# The door: `é` and an emoji decode; a lone `%E9` or `%FF` is malformed.
expect Form.field(Str.to_utf8("t=caf%C3%A9"), "t") == Found("café")
expect Form.field(Str.to_utf8("t=%F0%9F%91%8D"), "t") == Found("👍")
expect Form.field(Str.to_utf8("t=caf%E9"), "t") == Malformed
expect Form.field(Str.to_utf8("t=%FF&u=1"), "t") == Malformed
expect Form.field(Str.to_utf8("t=a+b"), "t") == Found("a b")
expect Form.field(Str.to_utf8("t=a"), "u") == Missing
