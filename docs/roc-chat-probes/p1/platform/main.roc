platform ""
	requires {
		handle! : Http.Request => Http.Response
	}
	exposes [Http, Memo, Markdown, Host]
	packages {}
	provides { "roc_handle": handle_for_host! }
	hosted {
		"roc_memo_get": Memo.get!,
		"roc_md_hostile": Markdown.hostile!,
		"roc_md_render": Markdown.render!,
		"roc_host_echo": Host.echo!,
		"roc_host_now_ns": Host.now_ns!,
		"roc_host_log": Host.log!,
	}
	targets: {
		x64musl: { inputs: [app], output: Archive },
	}

import Http
import Memo
import Markdown
import Host

handle_for_host! : Http.Request => Http.Response
handle_for_host! = |request| handle!(request)
