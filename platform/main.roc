## THE WEBBOX PLATFORM: a Roc app answers a web request, and its Zig host is
## a webbox site (src/roc_site.zig). The app provides `handle!`, which the
## host calls as `roc_handle` for each request it routes to Roc; the app's
## effects are hosted functions (File.roc), which the host performs as they
## are called, through webbox's store, the same on every webbox host.
platform ""
	requires {
		handle! : Http.Request => Http.Response
	}
	exposes [File, Http]
	packages {}
	provides { "roc_handle": handle_for_host! }
	hosted {
		"roc_file_read": File.read_raw!,
		"roc_file_write": File.write_raw!,
		"roc_file_delete": File.delete_raw!,
	}
	targets: {
		x64musl: {
			inputs: [app],
			output: Archive,
		},
		x64v1elf: {
			inputs: [app],
			output: Archive,
		},
		wasm32: {
			inputs: [app],
			output: Archive,
		},
	}

import File
import Http

handle_for_host! : Http.Request => Http.Response
handle_for_host! = |request| handle!(request)
