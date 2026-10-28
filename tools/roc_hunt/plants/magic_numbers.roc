# hunt.shale magic_numbers' plants: every `fires_` definition must be found,
# and no `quiet_` one. Parsed, never compiled.

# A number between 32 and 126 is most likely a byte, and marked so.
# finding: fires_byte: 95'?
fires_byte = |b| b == 95

fires_count = |n| n * 60

fires_pattern = |b| match b {
	13 => Carriage
	_ => Other
}

quiet_zero = |n| n + 0

quiet_one = |n| n - 1

quiet_character = |b| b == '_'

# A local's name recurs across definitions: the number is found as the
# second one's, not grouped under the first's.
quiet_local = |n| {
	id = n
	id
}

fires_local = |n| {
	id = n + 47
	id
}

fires_typed = |n| n.min(200.U8)

fires_fraction = |x| x * 0.75

fires_typed_fraction = |x| x * 0.5.F32

quiet_typed_zero = |n| n.max(0.U8)

# 0 and 1 compared in turn, a closed set a tag would name: a match over a
# status.
# finding: fires_status_codes: 0 (compared in turn), 1 (compared in turn)
fires_status_codes = |status| match status {
	0 => "ok"
	1 => "bad"
	_ => "unknown"
}

# The same: one expression compared to 0, then 1, in an if chain.
fires_status = |parsed| if parsed.err == 0 "ok" else if parsed.err == 1 "nan" else "range"

# Two different expressions, each compared to one of 0 and 1: no set.
quiet_apart = |a, b| if a.len == 0 "empty" else if b.len == 1 "one" else "more"

# One literal compared twice is no set either.
quiet_same = |a, b| if a == 0 "a" else if a == 0 "b" else "c"

# A definition whose whole value is one literal names it: naming is the
# fix, not the fault.
quiet_min_shifts = 32

quiet_typed_constant = 200.U8

# A shift's or mask's operand is a bit count or a mask, not a byte: no `'?`.
# finding: fires_shift: 56, 64
# finding: fires_qualified_shift: 48
# finding: fires_wrapped_shift: 56
fires_shift = |x| x.shift_left_by(56).bitwise_and(64)

fires_qualified_shift = |x| U64.shift_right_by(x, 48)

fires_wrapped_shift = |x| U64.shr_zf_wrap(x, 56)
