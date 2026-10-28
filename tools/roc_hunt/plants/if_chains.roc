# hunt.shale if_chains' plants: every `fires_` definition must be found, and
# no `quiet_` one. Parsed, never compiled.

fires_three = |n| if n == 2 "a" else if n == 3 "b" else if n == 4 "c" else "d"

quiet_two = |n| if n == 2 "a" else if n == 3 "b" else "c"

quiet_nested_in_then = |n| if n == 2 (if n == 3 "a" else "b") else "c"

# Guards that return, three in a row.
fires_guards = |n| {
	if n < 10 {
		return Small
	}
	if n < 100 {
		return Medium
	}
	if n < 1000 {
		return Large
	}
	Huge
}

quiet_two_guards = |n| {
	if n < 10 {
		return Small
	}
	if n < 100 {
		return Medium
	}
	Large
}

# An else whose block holds just the next if.
fires_braced = |n| if n < 10 { Small } else { if n < 100 { Medium } else { if n < 1000 { Large } else { Huge } } }

# An else whose block holds more than the if is no chain.
quiet_braced_with_more = |n| if n < 10 { Small } else {
	m = n * 2
	if m < 100 { Medium } else { if m < 1000 { Large } else { Huge } }
}
