Http := [].{
	Header : { name : Str, value : Str }
	Request : {
		method : Str,
		target : Str,
		headers : List(Header),
		body : List(U8),
		at_unix_ms : I64,
		peer : Str,
		user : [Nobody, Member({ id : Str, name : Str })],
	}
	Response : { kind : U8, status : U16, headers : List(Header), body : List(U8) }
}
