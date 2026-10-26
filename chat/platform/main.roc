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
		"roc_chat_member": Host.member!,
		"roc_chat_presence": Host.presence!,
		"roc_chat_topic": Host.topic!,
		"roc_chat_body": Host.body!,
		"roc_chat_reactions": Host.reactions!,
		"roc_chat_react": Host.react!,
		"roc_chat_pin": Host.pin!,
		"roc_chat_landing": Host.landing!,
		"roc_chat_page": Host.page!,
		"roc_chat_srcs": Host.srcs!,
		"roc_chat_me": Host.me!,
		"roc_chat_viewer": Host.viewer!,
		"roc_chat_last_conv": Host.last_conv!,
		"roc_chat_resume_topic": Host.resume_topic!,
		"roc_chat_topics": Host.topics!,
		"roc_chat_channels": Host.channels!,
		"roc_chat_members": Host.members!,
		"roc_chat_conv": Host.conv!,
		"roc_chat_bookmark": Host.bookmark!,
		"roc_chat_append": Host.append!,
		"roc_chat_send_conv": Host.send_conv!,
		"roc_chat_header": Host.header!,
		"roc_chat_hostile": Host.hostile!,
		"roc_chat_raw": Host.raw!,
		"roc_chat_links": Host.links!,
		"roc_chat_feed": Host.feed!,
		"roc_chat_recent": Host.recent!,
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
