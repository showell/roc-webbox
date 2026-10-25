app [handle!] { pf: platform "../platform/main.roc" }

import pf.Http
import pf.Markdown

page : Str -> Str
page = |md| "<div>${Markdown.render!(md)}</div>"

handle! : Http.Request => Http.Response
handle! = |req| { kind: 0, status: 200, headers: [], body: Str.to_utf8(page("x")) }
