# hunt.shale positional_lists' plants: every `fires_` definition must be
# found, and no `quiet_` one. Parsed, never compiled.

fires_positional : List(List(U8)) -> List(U8)
fires_positional = |fields| List.get(fields, 3) ?? []

fires_method : List(List(U8)), U64 -> List(U8)
fires_method = |fields, i| fields.get(i + 2) ?? []

quiet_walked : List(List(U8)) -> U64
quiet_walked = |lines| List.len(lines)

quiet_bytes : List(U8) -> U8
quiet_bytes = |b| List.get(b, 3) ?? 0

fires_in_a_helper : List(List(U8)), U64 -> List(U8)
fires_in_a_helper = |fields, i| {
	at = |k| List.get(fields, i + k) ?? []
	at(2)
}
