app [handle!] { pf: platform "../platform/main.roc" }

import pf.Http
import pf.Markdown

f : List U8 -> [Some (List U8), None]
f = |x| Some x

handle! : Http.Request => Http.Response
handle! = |req| { kind: 0, status: 200, headers: [], body: [] }
