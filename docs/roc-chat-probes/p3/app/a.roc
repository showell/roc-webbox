app [handle!] { pf: platform "../platform/main.roc" }

import pf.Http
import pf.Memo
import pf.Markdown
import pf.Host

handle! : Http.Request => Http.Response
handle! = |req| {
	who = match req.user {
		Nobody => "nobody"
		Member({ id, name }) => "${id}:${name}"
	}
	memo = match Memo.get!(req.target) {
		Some(bytes) => bytes
		None => Str.to_utf8("none")
	}
	hostile = match Markdown.hostile(req.method) {
		Ok => "ok"
		Hostile(why) => "hostile:${why}"
	}
	html = Markdown.render(req.peer)
	echoed = Host.echo!({ tag: 7, headers: req.headers, body: req.body })
	extra = List.map(echoed.headers, |h| { name: Str.concat(h.name, "!"), value: h.value })
	line = "${who}|${hostile}|${html}|${I64.to_str(req.at_unix_ms)}|${U8.to_str(echoed.tag)}"
	body = List.concat(List.concat(Str.to_utf8(line), memo), echoed.body)
	{ kind: 1, status: 201, headers: List.append(extra, { name: "x-n", value: U64.to_str(List.len(req.headers)) }), body }
}
