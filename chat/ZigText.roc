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
