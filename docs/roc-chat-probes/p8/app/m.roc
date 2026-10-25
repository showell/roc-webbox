app [program] { pf: platform "../platform/main.roc" }

Model : { count : U64, seen : List(Str) }

program = {
	init!: |{}| { count: 0, seen: [] },
	handle!: |model, input| {
		s = Str.from_utf8_lossy(input)
		next = { count: model.count + 1, seen: List.append(model.seen, s) }
		(next, Str.to_utf8("call ${U64.to_str(next.count)}: ${Str.join_with(next.seen, ",")}"))
	},
}
