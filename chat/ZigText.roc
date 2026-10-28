## ZIG'S TEXT, BYTE FOR BYTE (docs/ROC-CHAT.md R2): what the Roc chat must
## read and write exactly as the Zig chat does, so the files and frames the
## two make are the same bytes. Pure.
import Ascii
ZigText := [].{

	## angry-gopher decimal.zig `parseInt` at u64: one or more digits and
	## nothing else, no sign, no `_`, and it fits. **Kept on purpose:**
	## `U64.from_str` takes `+1`, `1_000`, `0x10` and `1e3` too. A text that is
	## both too long and not all digits is `NotANumber`, where the Zig says
	## which it met first; no caller tells the two apart.
	parse_u64 : List(U8) -> Try(U64, [NotANumber, TooBig])
	parse_u64 = |s|
		if s == [] or !List.all(s, Ascii.is_digit) {
			Err(NotANumber)
		} else {
			U64.from_int_digits(List.map(s, |c| c - '0')).map_err(|_| TooBig)
		}

	## `std.fmt.parseInt(u64, s, 10)`, as webbox's resume cursor reads a
	## number (sse.resumeAt): an optional `+` or `-`, then digits with any
	## `_` among them passed over (never first or last), and it fits; behind
	## a `-` only zeros (`-0` is 0, `-1` too big). **Kept on purpose:**
	## `parse_u64` is decimal.zig's, which takes neither a sign nor a `_`.
	std_parse_u64 : List(U8) -> Try(U64, [NotANumber, TooBig])
	std_parse_u64 = |s| {
		(sign, body) = match s {
			['-', .. as rest] => (Minus, rest)
			['+', .. as rest] => (Plus, rest)
			_ => (Plus, s)
		}
		digits = List.keep_if(body, |c| c != '_')
		if body == [] or List.first(body) == Ok('_') or List.last(body) == Ok('_') or !List.all(digits, Ascii.is_digit) {
			Err(NotANumber)
		} else if sign == Minus {
			if List.all(digits, |c| c == '0') Ok(0) else Err(TooBig)
		} else {
			U64.from_int_digits(List.map(digits, |c| c - '0')).map_err(|_| TooBig)
		}
	}

	## `std.mem.trim(u8, s, " \t\r\n")` on text, as the sidecars' readers trim
	## (`Bytes.trim` with `Bytes.zig_spaces`, on bytes). **Kept on purpose:**
	## `Str.trim` takes Unicode's spaces off, and the Zig only these four.
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

}
