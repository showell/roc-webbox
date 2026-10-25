app [handle!] { pf: platform "../platform/main.roc" }

import pf.Http
import pf.Markdown

handle! : Http.Request => Http.Response
handle! = |req| {
	html = List.map(["a", "b"], |b| Markdown.render!(b))
	{ kind: 0, status: 200, headers: [], body: Str.to_utf8(Str.join_with(html, "")) }
}
