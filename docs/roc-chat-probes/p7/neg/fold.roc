app [handle!] { pf: platform "../platform/main.roc" }

import pf.Http
import pf.Markdown

handle! : Http.Request => Http.Response
handle! = |req| {
	n = List.fold(["a", "b"], 0, |acc, b| acc + Str.count_utf8_bytes(Markdown.render!(b)))
	{ kind: 0, status: 200, headers: [], body: Str.to_utf8(U64.to_str(n)) }
}
