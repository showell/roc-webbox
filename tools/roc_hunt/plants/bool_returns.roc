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
