## A request as the host hands it to the app, and the answer it sends back.
## Each crosses to the host as a C struct (src/roc_abi.zig lays them out).
Http := [].{
	## `path` is the target's path, the query with it; `body` the request's
	## body, read by the host up to its cap.
	Request : { method : Str, path : Str, body : Str }

	Response : { status : U16, content_type : Str, body : Str }

	## A JSON answer.
	json : U16, Str -> Response
	json = |status, body| { status, content_type: "application/json", body }

	## A plain-text answer.
	text : U16, Str -> Response
	text = |status, body| { status, content_type: "text/plain; charset=utf-8", body }
}
