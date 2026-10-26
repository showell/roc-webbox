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
		values = List.keep_oks(Bytes.split_byte(body, 38), |pair|
			match Bytes.cut_seq(pair, [61]) {
				Ok((k, v)) if k == name => Ok(v)
				_ => Err(None)
			})
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
		Ok(43) => decode_from(raw, i + 1, List.append(out, 32))
		Ok(37) =>
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
		if c >= 48 and c <= 57 {
			Ok(c - 48)
		} else if c >= 97 and c <= 102 {
			Ok(c - 87)
		} else if c >= 65 and c <= 70 {
			Ok(c - 55)
		} else {
			Err(None)
		}
}
