## A PLANTED CRASH, FOR THE TESTS ONLY (src/chat_crash_test.zig): an app on
## the chat's platform that crashes on `/crash` and answers anything else,
## so the host's answer to a Roc crash (a 500, the call's memory dropped,
## the next request served) is seen. It also names any path a test likes
## to the file primitives (`/read/<path>`, `/write/<path>`,
## `/remove/<path>`), as the chat's own Roc never would, so the seam's
## check of each is seen. Never linked into a server.
app [handle!] { pf: platform "../platform/main.roc" }

import pf.Chat
import pf.Host

handle! : Chat.Request => Chat.Answer
handle! = |req|
	if starts(req.sub, "/read/") {
		got = Host.read!(List.drop_first(req.sub, 6))
		said = match got.status {
			Found => "found "
			Missing => "missing"
			Failed => "failed"
		}
		Chat.respond(200, [], List.concat(Str.to_utf8(said), got.bytes))
	} else if starts(req.sub, "/write/") {
		Chat.respond(200, [], done(Host.write!(List.drop_first(req.sub, 7), Str.to_utf8("bytes"))))
	} else if starts(req.sub, "/remove/") {
		Chat.respond(200, [], done(Host.remove!(List.drop_first(req.sub, 8))))
	} else if req.sub == Str.to_utf8("/crash") {
		crash "a planted crash"
	} else if req.sub == Str.to_utf8("/crash-after-asking") {
		if Host.member!({}) crash "a planted crash, after asking" else Chat.zig(Chat.family(NotFound), Bool.False)
	} else if req.sub == Str.to_utf8("/crash-after-asking-big") {
		# A list grown a byte at a time, through many allocations, then a
		# crash: each allocation is one a test can make fail. Bytes, said:
		# an unannotated 7 is a Dec (16 bytes), and the pinned Roc lays a
		# constant list of those out with only its refcount 16-aligned, then
		# reads the elements with aligned loads (a fault, where the linker
		# happens to put it on a 16-byte boundary).
		big : List(U8)
		big = List.fold(List.repeat(7, 20000), [], |acc, b| List.append(acc, b))
		if Host.member!({}) and List.len(big) == 20000 crash "a planted crash, after a big list" else Chat.zig(Chat.family(NotFound), Bool.False)
	} else {
		Chat.zig(Chat.family(Default), Bool.True)
	}

starts : List(U8), Str -> Bool
starts = |l, p| {
	pre = Str.to_utf8(p)
	List.take_first(l, List.len(pre)) == pre
}

done : Bool -> List(U8)
done = |ok| Str.to_utf8(if ok "done" else "failed")
