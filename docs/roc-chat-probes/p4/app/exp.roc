app [run!] { pf: platform "../platform/main.roc" }

import pf.Host

bad : U64 -> U64
bad = |n| n + 1

expect bad(1) == 3

run! : U8, List(U8) => List(U8)
run! = |mode, input| {
	n = List.len(input)
	if mode == 0 {
		expect n == 999
		Host.log!("after failed inline expect, n=${U64.to_str(n)}")
		Str.to_utf8("survived")
	} else {
		if n < 1000 { crash "deliberate crash" } else {}
		[]
	}
}
