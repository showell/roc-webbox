## THE CHAT'S PLATFORM (docs/ROC-CHAT.md §5): the Roc chat answers each
## /chat and /channel request angry-gopher hands it. Its host is
## angry-gopher's Zig (roc-webbox src/chat_abi.zig the seam): the app
## provides `handle!`, called as `roc_chat_handle`; its effects are hosted
## functions (Host.roc), prefixed `roc_chat_` so they cannot meet another
## Roc app's in one binary.
platform ""
	requires {
		handle! : Chat.Request => Chat.Answer
	}
	exposes [Chat, Host]
	packages {}
	provides { "roc_chat_handle": handle_for_host! }
	hosted {
		"roc_chat_admit": Host.admit!,
		"roc_chat_append_entry": Host.append_entry!,
		"roc_chat_append_line": Host.append_line!,
		"roc_chat_append_message": Host.append_message!,
		"roc_chat_aside": Host.aside!,
		"roc_chat_check_hostile": Host.check_hostile!,
		"roc_chat_check_member": Host.check_member!,
		"roc_chat_check_online": Host.check_online!,
		"roc_chat_count_dropped": Host.count_dropped!,
		"roc_chat_count_malformed_channel": Host.count_malformed_channel!,
		"roc_chat_count_presence": Host.count_presence!,
		"roc_chat_fail": Host.fail!,
		"roc_chat_index_message": Host.index_message!,
		"roc_chat_list": Host.list!,
		"roc_chat_list_accounts": Host.list_accounts!,
		"roc_chat_me": Host.me!,
		"roc_chat_now": Host.now!,
		"roc_chat_presence_unspent": Host.presence_unspent!,
		"roc_chat_publish": Host.publish!,
		"roc_chat_read": Host.read!,
		"roc_chat_read_at": Host.read_at!,
		"roc_chat_read_body": Host.read_body!,
		"roc_chat_read_header": Host.read_header!,
		"roc_chat_read_query": Host.read_query!,
		"roc_chat_remove": Host.remove!,
		"roc_chat_render": Host.render!,
		"roc_chat_report_fanout_failure": Host.report_fanout_failure!,
		"roc_chat_search_messages": Host.search_messages!,
		"roc_chat_search_words": Host.search_words!,
		"roc_chat_serve_file": Host.serve_file!,
		"roc_chat_serve_rendered": Host.serve_rendered!,
		"roc_chat_srcs": Host.srcs!,
		"roc_chat_stat": Host.stat!,
		"roc_chat_welcome_done": Host.welcome_done!,
		"roc_chat_welcome_pending": Host.welcome_pending!,
		"roc_chat_write": Host.write!,
		"roc_chat_write_cache": Host.write_cache!,
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
	}

import Chat
import Host

handle_for_host! : Chat.Request => Chat.Answer
handle_for_host! = |request| handle!(request)
