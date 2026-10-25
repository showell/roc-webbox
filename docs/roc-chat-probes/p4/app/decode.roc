app [run!] { pf: platform "../platform/main.roc" }

import pf.Host

Msg : { id : U64, from : Str, date : Str, body : Str }

sep : Str
sep = "\n\n-------------\n"

parse_block : Str -> Try(Msg, [Bad(Str)])
parse_block = |block| match Str.split_first(block, "\n\n") {
	Err(NotFound) => Err(Bad("no blank line"))
	Ok({ before: head, after: body }) => {
		lines = Str.split_on(head, "\n")
		match lines {
			[first, .. as rest] => {
				id = match U64.from_str(Str.drop_prefix(first, "MSG_")) {
					Ok(n) => n
					Err(_) => 0
				}
				init = { id, from: "", date: "", body }
				Ok(List.fold(rest, init, |m, line|
					match Str.split_first(line, ": ") {
						Ok({ before: "from", after }) => { ..m, from: after }
						Ok({ before: "date", after }) => { ..m, date: after }
						_ => m
					}))
			}
			[] => Err(Bad("empty"))
		}
	}
}

decode : Str -> List(Msg)
decode = |text| List.keep_oks(Str.split_on(text, sep), parse_block)

run! : U8, List(U8) => List(U8)
run! = |mode, input| {
	t0 = Host.now_ns!({})
	text = match Str.from_utf8(input) {
		Ok(s) => s
		Err(_) => ""
	}
	t1 = Host.now_ns!({})
	msgs = decode(text)
	t2 = Host.now_ns!({})
	total = List.fold(msgs, 0, |acc, m| acc + Str.count_utf8_bytes(m.body))
	ids = List.fold(msgs, 0, |acc, m| acc + m.id)
	froms = List.fold(msgs, 0, |acc, m| acc + Str.count_utf8_bytes(m.from) + Str.count_utf8_bytes(m.date))
	Host.log!("mode ${U8.to_str(mode)}: from_utf8 ${U64.to_str((t1 - t0) // 1000)} us; decode ${U64.to_str((t2 - t1) // 1000)} us")
	Str.to_utf8("msgs=${U64.to_str(List.len(msgs))} body_bytes=${U64.to_str(total)} id_sum=${U64.to_str(ids)} hdr_bytes=${U64.to_str(froms)}")
}
