## AN ACCOUNT'S ID: its decimal digits, a type of its own so that a pair
## key, a name or a path passed where a uid belongs is a type error. Bytes
## only where a uid is read in or written out.
Uid := List(U8).{
	from_bytes : List(U8) -> Uid
	from_bytes = |b| Uid.(b)

	bytes : Uid -> List(U8)
	bytes = |Uid.(b)| b

	is_eq : _
}
