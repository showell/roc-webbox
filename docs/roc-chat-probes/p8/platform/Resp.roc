Resp := { z : U8, body : List(U8), a : U16 }.{
	new : List(U8) -> Resp
	new = |b| { z: 7, body: b, a: 513 }
}
