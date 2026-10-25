app [run!] { pf: platform "../platform/main.roc" }

import pf.Host

show : Str -> Str
show = |s| match U64.from_str(s) {
	Ok(n) => "Ok(${U64.to_str(n)})"
	Err(e) => "Err(${Str.inspect(e)})"
}

showi : Str -> Str
showi = |s| match I64.from_str(s) {
	Ok(n) => "Ok(${I64.to_str(n)})"
	Err(e) => "Err(${Str.inspect(e)})"
}

run! : U8, List(U8) => List(U8)
run! = |mode, input| {
	if mode == 0 {
		cases = ["1", "+1", "-0", "-1", "1_0", "_1", "1_", "1__0", " 1", "1 ", "", "0x10", "007", "18446744073709551615", "18446744073709551616", "1e3", "١", "0b11", "0o17", "0X10", "1.0", "1.5e1", "1e-1", "1.", "0x", "0x_1", "1E3", "10e18", "1_0e1", "+-1", "--1", "-0x0", "00x1", "0xff_ff", "1e19", "1e20"]
		List.for_each!(cases, |c| Host.log!("U64.from_str(${Str.inspect(c)}) = ${show(c)}   I64: ${showi(c)}"))
		Str.to_utf8("ok")
	} else if mode == 1 {
		n = List.len(input)
		big : U64
		big = 18446744073709551615
		Host.log!("checked: ${Str.inspect(U64.plus_try(big, n))}")
		Host.log!("wrap: ${U64.to_str(U64.plus_wrap(big, n))}")
		Host.log!("about to overflow")
		x = big + n
		Host.log!("overflowed to ${U64.to_str(x)}")
		Str.to_utf8("ok")
	} else if mode == 2 {
		n = List.len(input)
		Host.log!("sub underflow: 0 - ${U64.to_str(n)}")
		x = 0 - n
		Host.log!("got ${U64.to_str(x)}")
		[]
	} else {
		n = List.len(input)
		Host.log!("div by ${U64.to_str(n - 1)}")
		x = 10 // (n - 1)
		Host.log!("got ${U64.to_str(x)}")
		y = List.get(input, 99)
		Host.log!("get oob ${Str.inspect(y)}")
		[]
	}
}
