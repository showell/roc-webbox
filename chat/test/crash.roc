## A PLANTED CRASH, FOR THE TESTS ONLY (src/chat_crash_test.zig): an app on
## the chat's platform that crashes on `/crash` and answers anything else,
## so the host's answer to a Roc crash (a 500, the call's memory dropped,
## the next request served) is seen. It also names any path a test likes
## to the file primitives (`/read/<path>`, `/stat/<path>`,
## `/read_at/<offset>/<max>/<path>`, `/write/<path>`,
## `/remove/<path>`, `/list/<path>`, `/append/<path>`, `/raw/<path>`,
## `/links/<path>`), as the chat's own
## Roc never would, so the seam's check of each is seen; it publishes
## (`/publish/<key>`), counts (`/count/<topic>`), renders (`/render/<md>`),
## stores a message (`/store/<topic>`), appends a feed's entry and says one that failed (`/entry/<path>`), and asks
## `fail!` (`/fail/<reason>/<whose>`),
## `count_malformed_channel!` (`/malformed/<name>`), `list_accounts!` (`/accounts`),
## and `check_online!` (`/online/<id>,<id>`). Never linked
## into a server.
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
	} else if starts(req.sub, "/stat/") {
		got = Host.stat!(List.drop_first(req.sub, 6))
		said = match got.status {
			Found => "found size=${U64.to_str(got.size)} mtime=${I64.to_str(got.mtime)}"
			Missing => "missing size=${U64.to_str(got.size)} mtime=${I64.to_str(got.mtime)}"
			Failed => "failed"
		}
		Chat.respond(200, [], Str.to_utf8(said))
	} else if starts(req.sub, "/read_at/") {
		# /read_at/<offset>/<max>/<path>: one digit each.
		rest = List.drop_first(req.sub, 9)
		offset = U8.to_u64((List.get(rest, 0) ?? '0') - '0')
		max = U8.to_u64((List.get(rest, 2) ?? '0') - '0')
		got = Host.read_at!(List.drop_first(rest, 4), offset, max)
		said = match got.status {
			Found => "found "
			Missing => "missing"
			Failed => "failed"
		}
		Chat.respond(200, [], List.concat(Str.to_utf8(said), got.bytes))
	} else if starts(req.sub, "/write/") {
		Chat.respond(200, [], done(Host.write!(List.drop_first(req.sub, 7), Str.to_utf8("bytes"))))
	} else if starts(req.sub, "/append/") {
		Chat.respond(200, [], done(Host.append_line!(List.drop_first(req.sub, 8), Str.to_utf8("{\"a\":1}"))))
	} else if starts(req.sub, "/publish/") {
		Host.publish!(List.drop_first(req.sub, 9), Str.to_utf8("event: reaction\ndata: x\n\n"))
		Chat.respond(200, [], Str.to_utf8("published"))
	} else if starts(req.sub, "/render/") {
		got = Host.render!(List.drop_first(req.sub, 8))
		said = match got.status {
			Rendered => "rendered "
			Failed => "failed"
		}
		Chat.respond(200, [], List.concat(Str.to_utf8(said), got.html))
	} else if starts(req.sub, "/store/") {
		# Message 9 of DM 1_2's topic `<topic>`: every field of the message a
		# different string, so a record laid out wrong shows.
		Chat.respond(200, [], done(Host.store_message!(dm12, List.drop_first(req.sub, 7), Str.to_utf8("the block"), 8, probe_message)))
	} else if starts(req.sub, "/entry/") {
		# An entry appended to `<path>`; one that failed is said for member 2
		# on 1_2/Plans with the fault it answered, the request never failed.
		got = Host.append_entry!(List.drop_first(req.sub, 7), Str.to_utf8("--"), Str.to_utf8("the entry"))
		match got.status {
			Appended => Chat.respond(200, [], Str.to_utf8("appended"))
			Failed => {
				Host.report_fanout_failure!(Images, Str.to_utf8("2"), Str.to_utf8("1_2"), Str.to_utf8("Plans"), got.fault)
				Chat.respond(200, [], Str.to_utf8("said"))
			}
		}
	} else if starts(req.sub, "/raw/") {
		Chat.respond(200, [], served(Host.serve_file!(List.drop_first(req.sub, 5))))
	} else if starts(req.sub, "/links/") {
		Chat.respond(200, [], served(Host.serve_rendered!(List.drop_first(req.sub, 7))))
	} else if starts(req.sub, "/remove/") {
		Chat.respond(200, [], done(Host.remove!(List.drop_first(req.sub, 8))))
	} else if starts(req.sub, "/list/") {
		got = Host.list!(List.drop_first(req.sub, 6))
		said = match got.status {
			Found => "found"
			Missing => "missing"
			Failed => "failed"
		}
		# Each entry as ` <kind>:<name>`, so a record laid out wrong shows.
		each = List.join(
			List.map(
				got.entries,
				|e| List.concat(
					Str.to_utf8(
						match e.kind {
							Dir => " d:"
							File => " f:"
							Other => " o:"
						},
					),
					e.name,
				),
			),
		)
		Chat.respond(200, [], List.concat(Str.to_utf8(said), each))
	} else if req.sub == Str.to_utf8("/accounts") {
		got = Host.list_accounts!({})
		said = match got.status {
			Found => "found"
			Failed => "failed"
		}
		# Each account as ` <kind>:<id>=<name>` (`=?` for a name that would
		# not read), so a record laid out wrong shows.
		each = List.join(
			List.map(
				got.accounts,
				|a| List.join([
					Str.to_utf8(
						match a.kind {
							Agent => " a:"
							Guest => " g:"
							Member => " m:"
							Unreadable => " u:"
						},
					),
					a.id,
					Str.to_utf8(
						match a.name_read {
							Found => "="
							Unreadable => "=?"
						},
					),
					a.name,
				]),
			),
		)
		Chat.respond(200, [], List.concat(Str.to_utf8(said), each))
	} else if starts(req.sub, "/fail/") {
		# `/fail/<reason>/<whose>`, the reason `malformed`, `kind` or `name`.
		rest = List.drop_first(req.sub, 6)
		if starts(rest, "malformed/") {
			Host.fail!(MalformedChannel, List.drop_first(rest, 10))
		} else if starts(rest, "kind/") {
			Host.fail!(KindUnreadable, List.drop_first(rest, 5))
		} else if starts(rest, "name/") {
			Host.fail!(NameUnreadable, List.drop_first(rest, 5))
		} else if starts(rest, "author/") {
			Host.fail!(NoAuthor, List.drop_first(rest, 7))
		} else {
			crash "crash.roc: /fail/ with no reason"
		}
		Chat.respond(200, [], Str.to_utf8("failed"))
	} else if starts(req.sub, "/online/") {
		# `/online/<id>,<id>,...`: each id's flag in its place, ` <id>:on` or
		# ` <id>:off`, so a list that crossed short, long or shifted shows.
		ids = split_on(List.drop_first(req.sub, 8), 44)
		flags = Host.check_online!(ids)
		said = List.map_with_index(
			flags,
			|f, i| List.join([
				[32],
				List.get(ids, i) ?? Str.to_utf8("?"),
				Str.to_utf8(
					match f {
						Online => ":on"
						Offline => ":off"
					},
				),
			]),
		)
		Chat.respond(200, [], List.concat(Str.to_utf8("flags ${U64.to_str(List.len(flags))}"), List.join(said)))
	} else if starts(req.sub, "/malformed/") {
		Host.count_malformed_channel!(List.drop_first(req.sub, 11))
		Chat.respond(200, [], Str.to_utf8("counted"))
	} else if req.sub == Str.to_utf8("/crash") {
		crash "a planted crash"
	} else if req.sub == Str.to_utf8("/crash-after-asking") {
		if Host.check_member!({}) == Member crash "a planted crash, after asking" else Chat.zig(Chat.family(NotFound), Uncounted)
	} else if req.sub == Str.to_utf8("/crash-after-asking-big") {
		# A list grown a byte at a time, through many allocations, then a
		# crash: each allocation is one a test can make fail. Bytes, said:
		# an unannotated 7 is a Dec (16 bytes), and the pinned Roc lays a
		# constant list of those out with only its refcount 16-aligned, then
		# reads the elements with aligned loads (a fault, where the linker
		# happens to put it on a 16-byte boundary).
		big : List(U8)
		big = List.fold(List.repeat(7, 20000), [], |acc, b| List.append(acc, b))
		if Host.check_member!({}) == Member and List.len(big) == 20000 crash "a planted crash, after a big list" else Chat.zig(Chat.family(NotFound), Uncounted)
	} else {
		Chat.zig(Chat.family(Default), Counted)
	}

starts : List(U8), Str -> Bool
starts = |l, p| {
	pre = Str.to_utf8(p)
	List.take_first(l, List.len(pre)) == pre
}

## `l` cut at each `sep`.
split_on : List(U8), U8 -> List(List(U8))
split_on = |l, sep|
	List.fold(
		l,
		[[]],
		|acc, b|
			if b == sep {
				List.append(acc, [])
			} else {
				List.update(acc, List.len(acc) - 1, |last| List.append(last, b)) ?? acc
			},
	)

dm12 : Chat.Conv
dm12 = { family: Dm, key: Str.to_utf8("1_2"), base: Str.to_utf8("/chat/c/1_2"), members: [Str.to_utf8("1"), Str.to_utf8("2")] }

probe_message : Chat.Message
probe_message = { id: Str.to_utf8("Plans_9"), from: Str.to_utf8("Steve"), at: Str.to_utf8("2026-10-26T00:00:00Z"), uid: Str.to_utf8("1"), markdown: Str.to_utf8("**hi**") }

done : Try({}, [Failed]) -> List(U8)
done = |got|
	Str.to_utf8(
		match got {
			Ok({}) => "done"
			Err(Failed) => "failed"
		},
	)

served : [Serving, NotServing] -> List(U8)
served = |got| Str.to_utf8(if got == Serving "done" else "failed")
