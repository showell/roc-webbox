## TIMES AS CHAT WRITES THEM (angry-gopher timefmt.zig): a message's
## `date:` (RFC 3339, UTC, to the second), a dated topic's name, and the
## reading back of a date another writer may have made. Howard Hinnant's
## civil-date algorithm, as the Zig has it. Pure.
Time := [].{

	## `2026-06-19T14:34:07Z` for `unix_secs`.
	rfc3339 : I64 -> Str
	rfc3339 = |unix_secs| {
		days = div_floor(unix_secs, 86400)
		tod = unix_secs - days * 86400
		c = civil_from_days(days)
		"${year_text(c.year)}-${two(c.month)}-${two(c.day)}T${two(div_floor(tod, 3600))}:${two(div_floor(mod_floor(tod, 3600), 60))}:${two(mod_floor(tod, 60))}Z"
	}

	## `2026-06-19` for `unix_secs`: a topic named for its day.
	date : I64 -> Str
	date = |unix_secs| {
		c = civil_from_days(div_floor(unix_secs, 86400))
		"${year_text(c.year)}-${two(c.month)}-${two(c.day)}"
	}

	## What `rfc3339` wrote, read back, or none. Also a fraction of a second
	## (dropped) and a `+hh:mm` or `-hh:mm` offset in place of `Z`, so a
	## transcript another writer made still carries its own date.
	unix_from_rfc3339 : List(U8) -> Try(I64, [NotADate])
	unix_from_rfc3339 = |t| {
		at = |i| List.get(t, i) ?? 0
		if List.len(t) < 20 or at(4) != '-' or at(7) != '-' or (at(10) != 'T' and at(10) != 't') or at(13) != ':' or at(16) != ':' {
			Err(NotADate)
		} else {
			match (digits(t, 0, 4), digits(t, 5, 2), digits(t, 8, 2), digits(t, 11, 2), digits(t, 14, 2), digits(t, 17, 2)) {
				(Ok(year), Ok(month), Ok(day), Ok(hour), Ok(minute), Ok(second)) =>
					if month < 1 or month > 12 or day < 1 or day > 31 or hour > 23 or minute > 59 or second > 60 {
						Err(NotADate)
					} else {
						offset = offset_of(List.drop_first(t, 19))?
						Ok(days_from_civil(year, month, day) * 86400 + hour * 3600 + minute * 60 + second - offset)
					}
				_ => Err(NotADate)
			}
		}
	}

	Civil : { year : I64, month : I64, day : I64 }
}

offset_of : List(U8) -> Try(I64, [NotADate])
offset_of = |rest0| {
	rest = match rest0 {
		['.', .. as frac] => {
			n = count_digits(frac, 0)
			if n == 0 Err(NotADate) else Ok(List.drop_first(frac, n))
		}
		_ => Ok(rest0)
	}
	match rest {
		Err(NotADate) => Err(NotADate)
		Ok(['Z']) | Ok(['z']) => Ok(0)
		Ok([sign, _, _, ':', _, _]) if sign == '+' or sign == '-' => {
			r = rest ?? []
			match (digits(r, 1, 2), digits(r, 4, 2)) {
				(Ok(oh), Ok(om)) =>
					if oh > 23 or om > 59 {
						Err(NotADate)
					} else {
						Ok((oh * 3600 + om * 60) * (if sign == '+' 1 else -1))
					}
				_ => Err(NotADate)
			}
		}
		_ => Err(NotADate)
	}
}

count_digits : List(U8), U64 -> U64
count_digits = |l, n| match List.get(l, n) {
	Ok(c) if c >= '0' and c <= '9' => count_digits(l, n + 1)
	_ => n
}

## `len` decimal digits at `start`, as a number, or none.
digits : List(U8), U64, U64 -> Try(I64, [NotDigits])
digits = |t, start, len| {
	piece = List.sublist(t, { start, len })
	if List.len(piece) != len or !List.all(piece, |c| c >= '0' and c <= '9') {
		Err(NotDigits)
	} else {
		Ok(List.fold(piece, 0, |n, c| n * 10 + U8.to_i64(c - '0')))
	}
}

civil_from_days : I64 -> Civil
civil_from_days = |days| {
	z = days + 719468
	era = div_floor(z, 146097)
	doe = z - era * 146097
	yoe = div_floor(doe - div_floor(doe, 1460) + div_floor(doe, 36524) - div_floor(doe, 146096), 365)
	y = yoe + era * 400
	doy = doe - (365 * yoe + div_floor(yoe, 4) - div_floor(yoe, 100))
	mp = div_floor(5 * doy + 2, 153)
	d = doy - div_floor(153 * mp + 2, 5) + 1
	m = if mp < 10 mp + 3 else mp - 9
	{ year: y + (if m <= 2 1 else 0), month: m, day: d }
}

days_from_civil : I64, I64, I64 -> I64
days_from_civil = |year, month, day| {
	y = year - (if month <= 2 1 else 0)
	era = div_floor(y, 400)
	yoe = y - era * 400
	mp = if month > 2 month - 3 else month + 9
	doy = div_floor(153 * mp + 2, 5) + day - 1
	doe = yoe * 365 + div_floor(yoe, 4) - div_floor(yoe, 100) + doy
	era * 146097 + doe - 719468
}

## Zig's `@divFloor` and `@mod`: rounding toward minus infinity.
div_floor : I64, I64 -> I64
div_floor = |a, b| {
	q = a // b
	if (a % b != 0) and ((a < 0) != (b < 0)) q - 1 else q
}

mod_floor : I64, I64 -> I64
mod_floor = |a, b| a - div_floor(a, b) * b

## `{d:0>2}`: at least two digits.
two : I64 -> Str
two = |n| if n >= 0 and n < 10 "0${I64.to_str(n)}" else I64.to_str(n)

## `{d}` of a year: as many digits as it has, a sign when negative.
year_text : I64 -> Str
year_text = |y| I64.to_str(y)
