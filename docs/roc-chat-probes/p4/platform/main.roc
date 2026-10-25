platform ""
	requires {
		run! : U8, List(U8) => List(U8)
	}
	exposes [Host]
	packages {}
	provides { "roc_run": run_for_host! }
	hosted {
		"roc_host_now_ns": Host.now_ns!,
		"roc_host_log": Host.log!,
	}
	targets: {
		x64musl: { inputs: [app], output: Archive },
	}

import Host

run_for_host! : U8, List(U8) => List(U8)
run_for_host! = |mode, input| run!(mode, input)
