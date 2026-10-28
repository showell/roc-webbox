# hunt.shale magic_numbers' plants: every `fires_` definition must be found,
# and no `quiet_` one. Parsed, never compiled.

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

# A known miss, kept so a change to it is seen: 0 and 1 are never numbers
# here, so status codes that are only 0 and 1 go unflagged.
quiet_status_codes = |status| match status {
	0 => "ok"
	1 => "bad"
	_ => "unknown"
}
