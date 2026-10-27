## AN ACCOUNT'S ID: its decimal digits, a type of its own so that a pair
## key, a name or a path passed where a uid belongs is a type error.
## **A UID IS CANONICAL ASCII DIGITS, THE FIRST NOT ZERO** (allocateUser's):
## opaque (`::`), so only `from_str` makes one, and every uid in the chat
## is one an account could have.
Uid :: Str.{

	## The uid `text` spells, when it is digits, the first not zero.
	from_str : Str -> Try(Uid, [NotAUid])
	from_str = |text|
		match text.to_utf8() {
			[first, ..] if first != '0' and text.to_utf8().all(|c| c >= '0' and c <= '9') => Ok(Uid.(text))
			_ => Err(NotAUid)
		}

	## The uid bytes spell where the host hands them: bytes that are not
	## UTF-8 are no uid either.
	from_utf8 : List(U8) -> Try(Uid, [NotAUid])
	from_utf8 = |bytes|
		match Str.from_utf8(bytes) {
			Ok(text) => from_str(text)
			Err(_) => Err(NotAUid)
		}

	## The uid's digits.
	to_str : Uid -> Str
	to_str = |Uid.(s)| s

	is_eq : _
}

expect Uid.from_str("37").map_ok(Uid.to_str) == Ok("37")
expect Uid.from_str("9223372036854775808").map_ok(Uid.to_str) == Ok("9223372036854775808")
expect Uid.from_str("").is_err()
expect Uid.from_str("05").is_err()
expect Uid.from_str("0").is_err()
expect Uid.from_str("3a").is_err()
expect Uid.from_str("../3").is_err()
expect Uid.from_str("\u(663)").is_err()
expect Uid.from_utf8(Str.to_utf8("37")).map_ok(Uid.to_str) == Ok("37")
expect Uid.from_utf8([0x33, 0xff]).is_err()
expect Uid.from_utf8([]).is_err()
