# same_typed_args.shale's plants: every `fires_` annotation must be found,
# and no `quiet_` one. Parsed, never compiled.

fires_two_bytes : List(U8), List(U8) => Bool

fires_last_three : U64, Str, Str, Str -> Str

fires_records : { id : U8 }, { id : U8 } -> Bool

quiet_different : List(U8), U64 -> Bool

quiet_return_is_no_argument : List(U8) -> List(U8)

quiet_apart : Str, U64, Str -> Bool

quiet_lists_of_different_things : List(U8), List(Str) -> Bool

quiet_type_variables : a, a -> Bool

Plants := [].{
	fires_associated : I64, I64 -> I64

	quiet_associated : I64, Str -> I64
}
