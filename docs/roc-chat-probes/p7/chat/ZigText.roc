## Zig std.fmt.parseInt(u64, s, 10), reimplemented over bytes.
ZigText :: [].{
	parse_u64 : Str -> Try(U64, [Invalid, Overflow])
	parse_u64 = |s| {
		bytes = Str.to_utf8(s)
		(neg, digits) = match bytes {
			['+', .. as rest] => (Bool.False, rest)
			['-', .. as rest] => (Bool.True, rest)
			_ => (Bool.False, bytes)
		}
		match digits {
			[] => Err(Invalid)
			['_', ..] => Err(Invalid)
			[.., '_'] => Err(Invalid)
			_ => {
				r = List.fold_try(digits, 0, |acc, b|
					if b == '_' {
						Ok(acc)
					} else if b >= '0' and b <= '9' {
						match U64.times_try(acc, 10) {
							Ok(t) => match U64.plus_try(t, (b - '0').to_u64()) {
								Ok(v) => Ok(v)
								Err(_) => Err(Overflow)
							}
							Err(_) => Err(Overflow)
						}
					} else {
						Err(Invalid)
					})
				match r {
					Ok(v) => if neg and v != 0 Err(Overflow) else Ok(v)
					Err(e) => Err(e)
				}
			}
		}
	}
}

expect ZigText.parse_u64("+1") == Ok(1)
expect ZigText.parse_u64("-0") == Ok(0)
expect ZigText.parse_u64("1__0") == Ok(10)
expect ZigText.parse_u64("0x10") == Err(Invalid)
expect ZigText.parse_u64("1e3") == Err(Invalid)
expect ZigText.parse_u64("18446744073709551616") == Err(Overflow)
expect ZigText.parse_u64("-1") == Err(Overflow)
expect ZigText.parse_u64("_1") == Err(Invalid)
