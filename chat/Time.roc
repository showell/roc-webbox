## TIMES AS CHAT WRITES THEM (angry-gopher timefmt.zig): a message's
## `date:` (RFC 3339, UTC, to the second), a dated topic's name, and the
## reading back of a date another writer may have made. Howard Hinnant's
## civil-date algorithm, as the Zig has it. Pure.
import Ascii
import Bytes
Time := [].{

	## `2026-06-19T14:34:07Z` for `unix_secs`.
	rfc3339 : I64 -> Str
	rfc3339 = |unix_secs| {
		days = I64.div_floor_by(unix_secs, 86400)
		tod = unix_secs - days * 86400
		c = civil_from_days(days)
		hour = I64.div_floor_by(tod, 3600)
		minute = I64.div_floor_by(I64.mod_by(tod, 3600), 60)
		second = I64.mod_by(tod, 60)
		"${year_text(c.year)}-${two(c.month)}-${two(c.day)}T${two(hour)}:${two(minute)}:${two(second)}Z"
	}

	## `2026-06-19` for `unix_secs`: a topic named for its day.
	date : I64 -> Str
	date = |unix_secs| {
		c = civil_from_days(I64.div_floor_by(unix_secs, 86400))
		"${year_text(c.year)}-${two(c.month)}-${two(c.day)}"
	}

	## What `rfc3339` wrote, read back, or none. Also a fraction of a second
	## (dropped) and a `+hh:mm` or `-hh:mm` offset in place of `Z`, so a
	## transcript another writer made still carries its own date.
	unix_from_rfc3339 : List(U8) -> Try(I64, [NotADate])
	unix_from_rfc3339 = |t|
		match t {
			[
				_,
				_,
				_,
				_,
				'-',
				_,
				_,
				'-',
				_,
				_,
				sep,
				_,
				_,
				':',
				_,
				_,
				':',
				_,
				_,
				_,
				..,
			] if sep == 'T' or sep == 't' =>
				match (
					digits(t, { start: 0, len: 4 }),
					digits(t, { start: 5, len: 2 }),
					digits(t, { start: 8, len: 2 }),
					digits(t, { start: 11, len: 2 }),
					digits(t, { start: 14, len: 2 }),
					digits(t, { start: 17, len: 2 }),
				) {
					(
						Ok(year),
						Ok(month),
						Ok(day),
						Ok(hour),
						Ok(minute),
						Ok(second),
					) =>
						if month < 1 or month > 12 or day < 1 or day > 31 or hour > 23 or minute > 59 or second > 60 {
							Err(NotADate)
						} else {
							offset = offset_of(List.drop_first(t, 19))?
							Ok(
								days_from_civil(
									year,
									{ month, day },
								) * 86400 + hour * 3600 + minute * 60 + second - offset,
							)
						}
					_ => Err(NotADate)
				}
			_ => Err(NotADate)
		}

	Civil : {
		year : I64,
		month : I64,
		day : I64,
	}
}

offset_of : List(U8) -> Try(I64, [NotADate])
offset_of = |rest0| {
	rest = match rest0 {
		['.', .. as frac] => {
			n = Bytes.count_while(frac, { keep: Ascii.is_digit, at: 0 })
			if n == 0 Err(NotADate) else Ok(List.drop_first(frac, n))
		}
		_ => Ok(rest0)
	}
	match rest {
		Err(NotADate) => Err(NotADate)
		Ok(['Z']) | Ok(['z']) => Ok(0)
		Ok(
			[
				sign,
				h1,
				h2,
				':',
				m1,
				m2,
			],
		) if sign == '+' or sign == '-' => {
			match (
				digits([h1, h2], { start: 0, len: 2 }),
				digits([m1, m2], { start: 0, len: 2 }),
			) {
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

## `len` decimal digits at `start`, as a number, or none.
digits : List(U8), { start : U64, len : U64 } -> Try(I64, [NotDigits])
digits = |t, { start, len }| {
	piece = List.sublist(t, { start, len })
	if List.len(piece) != len or !List.all(piece, Ascii.is_digit) {
		Err(NotDigits)
	} else {
		Ok(
			List.fold(
				piece,
				0,
				|n, c| n * 10 + U8.to_i64(c - '0'),
			),
		)
	}
}

civil_from_days : I64 -> Civil
civil_from_days = |days| {
	z = days + 719468
	era = I64.div_floor_by(z, 146097)
	doe = z - era * 146097
	yoe = I64.div_floor_by(
		doe - I64.div_floor_by(doe, 1460) + I64.div_floor_by(doe, 36524) - I64.div_floor_by(
			doe,
			146096,
		),
		365,
	)
	y = yoe + era * 400
	doy = doe - (365 * yoe + I64.div_floor_by(yoe, 4) - I64.div_floor_by(yoe, 100))
	mp = I64.div_floor_by(5 * doy + 2, 153)
	d = doy - I64.div_floor_by(153 * mp + 2, 5) + 1
	m = if mp < 10 mp + 3 else mp - 9
	{
		year: y + (if m <= 2 1 else 0),
		month: m,
		day: d,
	}
}

days_from_civil : I64, { month : I64, day : I64 } -> I64
days_from_civil = |year, { month, day }| {
	y = year - (if month <= 2 1 else 0)
	era = I64.div_floor_by(y, 400)
	yoe = y - era * 400
	mp = if month > 2 month - 3 else month + 9
	doy = I64.div_floor_by(153 * mp + 2, 5) + day - 1
	doe = yoe * 365 + I64.div_floor_by(yoe, 4) - I64.div_floor_by(yoe, 100) + doy
	era * 146097 + doe - 719468
}

## `{d:0>2}`: at least two digits.
two : I64 -> Str
two = |n| if n >= 0 and n < 10 "0${I64.to_str(n)}" else I64.to_str(n)

## `{d}` of a year: as many digits as it has, a sign when negative.
year_text : I64 -> Str
year_text = |y| I64.to_str(y)
