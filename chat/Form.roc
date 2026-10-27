## A FORM'S FIELDS (zig-webbox http.zig's formField and formDecode, the one
## decoder every form on the site reads with): `a=b&c=d`, `+` a space and
## `%XX` a byte. A `%` that is not two hex digits, or a field sent twice, is
## malformed: the client's mistake, which the site answers 400.
import Bytes

Form := [].{
	Field : [Found(List(U8)), Missing, Malformed]

	## formField: the value of field `name`. A pair with no `=` is passed
	## over.
	field : List(U8), List(U8) -> Field
	field = |body, name| {
		values = List.keep_oks(
			Bytes.split_byte(body, '&'),
			|pair|
				match Bytes.cut_seq(pair, ['=']) {
					Ok((k, v)) if k == name => Ok(v)
					_ => Err(None)
				},
		)
		match values {
			[] => Missing
			[raw] =>
				match decode(raw) {
					Ok(v) => Found(v)
					Err(None) => Malformed
				}
			_ => Malformed
		}
	}

	## formDecode, or none for a `%` that is not two hex digits.
	decode : List(U8) -> Try(List(U8), [None])
	decode = |raw| decode_from(raw, 0, [])

	decode_from : List(U8), U64, List(U8) -> Try(List(U8), [None])
	decode_from = |raw, i, out| match List.get(raw, i) {
		Err(_) => Ok(out)
		Ok('+') => decode_from(raw, i + 1, List.append(out, ' '))
		Ok('%') =>
			match (List.get(raw, i + 1), List.get(raw, i + 2)) {
				(Ok(h), Ok(l)) =>
					match (hex(h), hex(l)) {
						(Ok(hi), Ok(lo)) => decode_from(raw, i + 3, List.append(out, hi * 16 + lo))
						_ => Err(None)
					}
				_ => Err(None)
			}
		Ok(c) => decode_from(raw, i + 1, List.append(out, c))
	}

	hex : U8 -> Try(U8, [None])
	hex = |c|
		if c >= '0' and c <= '9' {
			Ok(c - '0')
		} else if c >= 'a' and c <= 'f' {
			Ok(c - 'a' + 10)
		} else if c >= 'A' and c <= 'F' {
			Ok(c - 'A' + 10)
		} else {
			Err(None)
		}
}
