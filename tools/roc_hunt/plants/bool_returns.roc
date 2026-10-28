# hunt.shale bool_returns' plants: every `fires_` definition must be found,
# and no `quiet_` one. Parsed, never compiled.

# A failure said as false: wants a Try.
fires_stored : List(U8) => Bool

# A decision said as true: wants a tag.
fires_served_by_roc : U8 -> Bool

# Questions, named as questions.
quiet_is_open : U8 -> Bool

quiet_route_has_topic : U8 -> Bool

# Not a Bool at all.
quiet_stored : List(U8) => Try({}, [Failed])

# A decision said as a Bool, inside a Try.
fires_byte_order : List(U8) -> Try(Bool, [Missing])

# A Bool inside a tuple.
fires_pair : U8 -> (Bool, U64)

# A question inside a Try, named as a question.
quiet_is_even : List(U8) -> Try(Bool, [Missing])

# A Bool in the where clause is no result.
quiet_where : List(a) -> Str where [a.is_eq : a, a -> Bool]

# A predicate returned is a function, not a Bool.
quiet_predicate_maker : U8 -> (U8 -> Bool)
