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
