## ZIG'S TEXT, BYTE FOR BYTE (docs/ROC-CHAT.md R2): what the Roc chat must
## read and write exactly as the Zig chat does, so the files and frames the
## two make are the same bytes. Pure.
ZigText := [].{

	## angry-gopher decimal.zig `parseInt` at u64: one or more digits and
	## nothing else, no sign, no `_`, and it fits. Never `U64.from_str`,
	## which reads `0x10` and `1e3` too.
	parse_u64 : List(U8) -> Try(U64, [NotANumber, TooBig])
	parse_u64 = |s|
		if s == [] {
			Err(NotANumber)
		} else {
			List.fold(
				s,
				Ok(0),
				|acc, c|
					match acc {
						Err(why) => Err(why)
						Ok(n) =>
							if c < '0' or c > '9' {
								Err(NotANumber)
							} else {
								match U64.times_try(n, 10) {
									Ok(m) =>
										match U64.plus_try(m, U8.to_u64(c - '0')) {
											Ok(v) => Ok(v)
											Err(_) => Err(TooBig)
										}
									Err(_) => Err(TooBig)
								}
							}
					},
			)
		}

	## Zig's `std.json.fmt` of a string: in quotes, `"` and `\` escaped, the
	## bytes below 0x20 as `\u00xx` but for the five with short forms, DEL,
	## `/` and the rest, a character past ASCII included, as they are. The
	## escapes are all ASCII, so they go byte by byte over the UTF-8.
	json_string : Str -> List(U8)
	json_string = |s| List.append(
		List.fold(
			Str.to_utf8(s),
			['"'],
			|out, c| List.concat(out, escaped(c)),
		),
		'"',
	)

	## `std.mem.trim(u8, s, " \t\r\n")`, as the sidecars' readers trim.
	## trim's, on text: the same four ASCII spaces off each end (Str.trim's
	## are Unicode's, and the Zig's are not).
	trim_str : Str -> Str
	trim_str = |s| {
		ws = [
			" ",
			"\t",
			"\r",
			"\n",
		]
		front = List.find_first(ws, |w| s.starts_with(w))
		back = List.find_first(ws, |w| s.ends_with(w))
		match (front, back) {
			(Ok(w), _) => trim_str(s.drop_prefix(w))
			(_, Ok(w)) => trim_str(s.drop_suffix(w))
			_ => s
		}
	}

	trim : List(U8) -> List(U8)
	trim = |s| {
		ws = |c| c == ' ' or c == '\t' or c == '\r' or c == '\n'
		front = List.drop_first(
			s,
			count_while(
				s,
				ws,
				0,
			),
		)
		List.drop_last(
			front,
			count_back_while(
				front,
				ws,
				0,
			),
		)
	}

	## How many bytes from the end of `l` keep `keep`.
	count_back_while : List(U8), (U8 -> Bool), U64 -> U64
	count_back_while = |
		l,
		keep,
		n,
	|
		if n >= List.len(l) {
			n
		} else {
			match List.get(l, List.len(l) - 1 - n) {
				Ok(c) if keep(c) => count_back_while(
					l,
					keep,
					n + 1,
				)
				_ => n
			}
		}

	count_while : List(U8), (U8 -> Bool), U64 -> U64
	count_while = |
		l,
		keep,
		n,
	| match List.get(l, n) {
		Ok(c) if keep(c) => count_while(
			l,
			keep,
			n + 1,
		)
		_ => n
	}
}

## Backspace (8) and form feed (12) stay numbers: Roc's character
## literals have no escape for either.
escaped : U8 -> List(U8)
escaped = |c|
	match c {
		'"' => ['\\', '"']
		'\\' => ['\\', '\\']
		8 => ['\\', 'b']
		12 => ['\\', 'f']
		'\n' => ['\\', 'n']
		'\r' => ['\\', 'r']
		'\t' => ['\\', 't']
		_ if c < 0x20 => List.concat(Str.to_utf8("\\u00"), [hex(c // 16), hex(c % 16)])
		_ => [c]
	}

hex : U8 -> U8
hex = |d| if d < 10 d + '0' else d - 10 + 'a'
