# hunt.shale if_chains' plants: every `fires_` definition must be found, and
# no `quiet_` one. Parsed, never compiled.

fires_three = |n| if n == 2 "a" else if n == 3 "b" else if n == 4 "c" else "d"

quiet_two = |n| if n == 2 "a" else if n == 3 "b" else "c"

quiet_nested_in_then = |n| if n == 2 (if n == 3 "a" else "b") else "c"
