## THE TWINS' PLATFORM, FOR TESTS ONLY (docs/ROC-CHAT.md C1, C2): one entry,
## `roc_twin_call`, that runs the pure Roc function `which` names on `args`
## and answers its results, every value as bytes. angry-gopher's twin tests
## (chat_twin_test.zig) call it beside the Zig function each Roc one
## replaces, on the same inputs. Never linked into a server.
platform ""
	requires {
		call : { which : U8, args : List(List(U8)) } -> List(List(U8))
	}
	exposes []
	packages {}
	provides { "roc_twin_call": call_for_host }
	targets: {
		x64musl: {
			inputs: [app],
			output: Archive,
		},
	}

call_for_host : { which : U8, args : List(List(U8)) } -> List(List(U8))
call_for_host = |request| call(request)
