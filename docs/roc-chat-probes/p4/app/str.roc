app [run!] { pf: platform "../platform/main.roc" }

import pf.Host

show : Try(Str, [BadUtf8({ problem : Str.Utf8Problem, index : U64 })]) -> Str
show = |r| match r {
	Ok(s) => "Ok(${s})"
	Err(BadUtf8({ problem, index })) => "Err(BadUtf8 ${Str.inspect(problem)} at ${U64.to_str(index)})"
}

run! : U8, List(U8) => List(U8)
run! = |mode, input| {
	if mode == 0 {
		Host.log!("valid: ${show(Str.from_utf8([104, 105, 0xC3, 0xA9]))}")
		Host.log!("invalid ff: ${show(Str.from_utf8([104, 0xFF, 105]))}")
		Host.log!("truncated: ${show(Str.from_utf8([104, 0xC3]))}")
		Host.log!("overlong: ${show(Str.from_utf8([0xC0, 0xAF]))}")
		Host.log!("surrogate: ${show(Str.from_utf8([0xED, 0xA0, 0x80]))}")
		Host.log!("nul ok: ${show(Str.from_utf8([97, 0, 98]))}")
		lossy = Str.from_utf8_lossy([104, 0xFF, 0xFE, 105, 0xE2, 0x82, 33, 0xC3])
		Host.log!("lossy: ${lossy} bytes=${Str.inspect(Str.to_utf8(lossy))}")
		Host.log!("input as text: ${show(Str.from_utf8(input))}")
		Str.to_utf8("done")
	} else if mode == 1 {
		# build a big string by repeated Str.concat
		t0 = Host.now_ns!({})
		var $s = ""
		var $i = 0
		while $i < 20000 {
			$s = Str.concat($s, "line ${U64.to_str($i)} some text\n")
			$i = $i + 1
		}
		t1 = Host.now_ns!({})
		Host.log!("Str.concat x20000 -> ${U64.to_str(Str.count_utf8_bytes($s))} bytes in ${U64.to_str((t1 - t0) // 1000)} us")
		# List.concat of bytes
		var $b = []
		var $j = 0
		while $j < 20000 {
			$b = List.concat($b, Str.to_utf8("line ${U64.to_str($j)} some text\n"))
			$j = $j + 1
		}
		t2 = Host.now_ns!({})
		Host.log!("List.concat x20000 -> ${U64.to_str(List.len($b))} bytes in ${U64.to_str((t2 - t1) // 1000)} us")
		# join_with
		var $parts = List.with_capacity(20000)
		var $k = 0
		while $k < 20000 {
			$parts = List.append($parts, "line ${U64.to_str($k)} some text")
			$k = $k + 1
		}
		parts = $parts
		joined = Str.join_with(parts, "\n")
		t3 = Host.now_ns!({})
		Host.log!("map+join_with x20000 -> ${U64.to_str(Str.count_utf8_bytes(joined))} bytes in ${U64.to_str((t3 - t2) // 1000)} us")
		# to_utf8 of big string
		big = Str.to_utf8($s)
		t4 = Host.now_ns!({})
		Host.log!("Str.to_utf8 of ${U64.to_str(List.len(big))} bytes in ${U64.to_str((t4 - t3) // 1000)} us")
		Str.to_utf8("done")
	} else {
		[]
	}
}
