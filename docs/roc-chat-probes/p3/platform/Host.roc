Host := [].{
	echo! : { tag : U8, headers : List({ name : Str, value : Str }), body : List(U8) } => { tag : U8, headers : List({ name : Str, value : Str }), body : List(U8) }
	now_ns! : {} => U64
	log! : Str => {}
}
