# hunt.shale bools' plants: every `fires_` definition must be found, and no
# `quiet_` one. Parsed, never compiled.

fires_argument : Bool, U8 -> U8

fires_field : { on : Bool } -> U8

quiet_question : U8 -> Bool

quiet_tag : [On, Off], U8 -> U8

# A Bool inside a tuple argument.
fires_tuple : (Bool, U64) -> U64

# An unannotated helper, called with a bare tag: the call is the finding.
decode = |bytes, little_endian| if little_endian { bytes } else { List.reverse(bytes) }

fires_literal = |bytes| decode(bytes, True)

fires_method_literal = |bytes| bytes.decode(False)

fires_qualified_literal = |bytes| decode(bytes, Bool.True)

# A predicate's Bool is its answer, not a flag.
quiet_predicate : (U8 -> Bool), U8 -> U8

# A tag wrapping a Bool is no call to a function.
quiet_ok_true = |_| Ok(True)
