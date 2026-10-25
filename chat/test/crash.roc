## A PLANTED CRASH, FOR THE TESTS ONLY (src/chat_crash_test.zig): an app on
## the chat's platform that crashes on `/crash` and answers anything else,
## so the host's answer to a Roc crash (a 500, the call's memory dropped,
## the next request served) is seen. Never linked into a server.
app [handle!] { pf: platform "../platform/main.roc" }

import pf.Chat
import pf.Host

handle! : Chat.Request => Chat.Answer
handle! = |req|
	if req.sub == Str.to_utf8("/crash") {
		crash "a planted crash"
	} else if req.sub == Str.to_utf8("/crash-after-asking") {
		if Host.member!({}) crash "a planted crash, after asking" else Chat.zig(Chat.family(0), Bool.False)
	} else {
		Chat.zig(Chat.family(2), Bool.True)
	}
