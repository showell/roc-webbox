# hunt.shale bools' plants: every `fires_` definition must be found, and no
# `quiet_` one. Parsed, never compiled.

fires_argument : Bool, U8 -> U8

fires_field : { on : Bool } -> U8

quiet_question : U8 -> Bool

quiet_tag : [On, Off], U8 -> U8
