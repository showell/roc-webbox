## ZIG'S TEXT, BYTE FOR BYTE (docs/ROC-CHAT.md R2): what the Roc chat must
## read and write exactly as the Zig chat does, so the files and frames the
## two make are the same bytes. Pure.
ZigText := [].{
	## angry-gopher decimal.zig `parseInt` at u64: one or more digits and
	## nothing else, no sign, no `_`, and it fits. Never `U64.from_str`,
	## which reads `0x10` and `1e3` too.
	parse_u64 : List(U8) -> Try(U64, [None])
	parse_u64 = |s|
		if s == [] {
			Err(None)
		} else {
			List.fold(s, Ok(0), |acc, c|
				match acc {
					Err(None) => Err(None)
					Ok(n) =>
						if c < 48 or c > 57 {
							Err(None)
						} else {
							match U64.times_try(n, 10) {
								Ok(m) =>
									match U64.plus_try(m, U8.to_u64(c - 48)) {
										Ok(v) => Ok(v)
										Err(_) => Err(None)
									}
								Err(_) => Err(None)
							}
						}
				})
		}

	## Zig's `std.json.fmt` of a string: in quotes, `"` and `\` escaped, the
	## bytes below 0x20 as `\u00xx` but for the five with short forms, DEL,
	## `/` and the rest as they are. Bytes that are not UTF-8 are no string
	## to Zig: it writes them as an array of byte numbers.
	json_string : List(U8) -> List(U8)
	json_string = |s|
		match Str.from_utf8(s) {
			Ok(_) => List.concat(List.append(List.fold(s, [34], |out, c| List.concat(out, escaped(c))), 34), [])
			Err(_) => {
				(out, _) = List.fold(s, ([91], Bool.True), |(acc, first), c|
					(List.concat(if first acc else List.append(acc, 44), Str.to_utf8(U8.to_str(c))), Bool.False))
				List.append(out, 93)
			}
		}

	escaped : U8 -> List(U8)
	escaped = |c|
		if c == 34 {
			[92, 34]
		} else if c == 92 {
			[92, 92]
		} else if c == 8 {
			[92, 98]
		} else if c == 12 {
			[92, 102]
		} else if c == 10 {
			[92, 110]
		} else if c == 13 {
			[92, 114]
		} else if c == 9 {
			[92, 116]
		} else if c < 32 {
			List.concat(Str.to_utf8("\\u00"), [hex(c // 16), hex(c % 16)])
		} else {
			[c]
		}

	hex : U8 -> U8
	hex = |d| if d < 10 d + 48 else d - 10 + 97

	## `std.mem.trim(u8, s, " \t\r\n")`, as the sidecars' readers trim.
	trim : List(U8) -> List(U8)
	trim = |s| {
		ws = |c| c == 32 or c == 9 or c == 13 or c == 10
		front = List.drop_first(s, count_while(s, ws, 0))
		List.drop_last(front, count_while(reverse(front), ws, 0))
	}

	reverse : List(U8) -> List(U8)
	reverse = |l| List.fold(l, [], |acc, c| List.prepend(acc, c))

	count_while : List(U8), (U8 -> Bool), U64 -> U64
	count_while = |l, keep, n| match List.get(l, n) {
		Ok(c) if keep(c) => count_while(l, keep, n + 1)
		_ => n
	}
}
