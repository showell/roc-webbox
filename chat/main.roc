## THE ROC CHAT, ITS FIRST ROUTE (docs/ROC-CHAT.md, T1): the app the
## platform's host calls for each request angry-gopher hands it. It answers
## one route, so that a Roc archive linked into angry-gopher and gopher.elf
## can be seen answering; the router (A2) grows from here.
##
##   GET /ping    "roc chat: ok"
app [handle!] { pf: platform "../platform/main.roc" }

import pf.Http

handle! : Http.Request => Http.Response
handle! = |req| {
	parts = List.drop_if(Str.split_on(req.path, "/"), Str.is_empty)
	match parts {
		["ping"] =>
			if req.method == "GET" or req.method == "HEAD" {
				Http.text(200, "roc chat: ok\n")
			} else {
				Http.text(405, "GET\n")
			}
		_ => Http.text(404, "no such route: ${req.method} ${req.path}\n")
	}
}
