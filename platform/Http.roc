## A request as the host hands it to the app, and the answer it sends back.
## Each crosses to the host as a C struct (src/roc_abi.zig lays them out).
Http := [].{
	## `path` is the target's path, the query with it; `body` the request's
	## body, read by the host up to its cap; `user` who is asking: the
	## visitor's id the host's signed cookie names (16 hex digits), a new
	## one on a first visit.
	Request : { method : Str, path : Str, body : Str, user : Str }

	Response : { status : U16, content_type : Str, body : Str }

	## A JSON answer.
	json : U16, Str -> Response
	json = |status, body| { status, content_type: "application/json", body }

	## A plain-text answer.
	text : U16, Str -> Response
	text = |status, body| { status, content_type: "text/plain; charset=utf-8", body }
}
