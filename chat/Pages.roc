## THE CHAT'S PAGES (angry-gopher chat_page.zig): the conversation page and
## the sidebar it boots with, the first-topic shell, a 404 that says why, and
## the empty /chat. Each from what the host read; the chrome is Chrome.roc's.
import Bytes
import Chrome
import Html
import JsonText
import Paths
import ZigText

Pages := [].{
	## The server's limits the conversation page tells its client (the
	## client's only copy).
	Limits : { image_max : U64, video_max : U64, accept : List(U8), search_min : U64 }

	## What the conversation page shows: the conversation's key and URL base,
	## the topic, its title, the viewer, and the sidebar's JSON.
	View : { key : List(U8), base : List(U8), sid : List(U8), title : List(U8), uid : List(U8), viewer : List(U8), sidebar_json : List(U8) }

	## What the sidebar shows: the viewer, the conversation (`dm` its kind
	## or a channel's), the topic, every other member, the viewer's channels,
	## their pins in this conversation, and its topics.
	Sidebar : { uid : List(U8), dm : Bool, key : List(U8), base : List(U8), sid : List(U8), others : List({ id : List(U8), name : List(U8), online : Bool }), channels : List(List(U8)), pins : List(List(U8)), topics : List(List(U8)) }

	shell : (List(U8) -> List(U8)), List(U8), List(U8), List(U8) -> Chrome.Shell
	shell = |src, title, viewer, active| { tab: Str.to_utf8("Chat"), title, viewer, active, src }

	## noTopicsHtml: an addressable conversation with no topics, its
	## first-topic widget mounted on `base`.
	no_topics : (List(U8) -> List(U8)), List(U8), List(U8), List(U8) -> List(U8)
	no_topics = |src, viewer, base, title| {
		s = shell(src, title, viewer, Str.to_utf8("chat"))
		Chrome.page(s, List.join([
			Str.to_utf8("<div id=\"chat-first-topic\" data-conv-base=\""),
			Html.escape(base),
			Str.to_utf8("\"></div>"),
			Chrome.script(s, "chat_add_topic.js"),
			Chrome.script(s, "chat_first_topic.js"),
		]))
	}

	## notFoundHtml: `what` is not here, and `back` is where to go.
	not_found : (List(U8) -> List(U8)), List(U8), List(U8), List(U8) -> List(U8)
	not_found = |src, viewer, what, back|
		Chrome.page(shell(src, Str.to_utf8("Not here"), viewer, Str.to_utf8("chat")), List.join([
			Str.to_utf8("<p>"),
			Html.escape(what),
			Str.to_utf8("</p><p><a href=\""),
			Html.escape(back),
			Str.to_utf8("\">Go back</a></p>"),
		]))

	## chat_links.zig's /chat/links: the member's curated links, `rendered`
	## (none when they have none: a stub that says who curates them), in a
	## readable column of its own.
	links : (List(U8) -> List(U8)), List(U8), List(List(U8)) -> List(U8)
	links = |src, viewer, rendered|
		Chrome.page({ tab: Str.to_utf8("Links"), title: Str.to_utf8("Links"), viewer, active: Str.to_utf8("links"), src }, List.join([
			Str.to_utf8(links_css),
			Str.to_utf8("<div class=\"links-page\">"),
			match rendered {
				[html] => html
				_ => Str.to_utf8("<p>No links yet — ask Steve to curate links.</p>")
			},
			Str.to_utf8("</div>"),
		]))

	## The links page cut where the rendered links go: the host holds them
	## (a curated page can be long), and answers before, them, after.
	links_around : (List(U8) -> List(U8)), List(U8) -> (List(U8), List(U8))
	links_around = |src, viewer|
		match Bytes.cut_seq(links(src, viewer, [[0]]), [0]) {
			Ok(parts) => parts
			Err(None) => crash "Pages.links_around: the page lost its mark"
		}

	links_css : Str
	links_css = "<style>\n.links-page { max-width: 46rem; margin: 0 auto; line-height: 1.55; }\n.links-page h2 { margin-top: 1.6rem; }\n.links-page li { margin: 3px 0; }\n</style>"

	## images.zig's and code.zig's pages: the attention strip, the feed's
	## mount, its JSON (`json`, script-safe) and its scripts.
	feed : (List(U8) -> List(U8)), List(U8), Str, List(U8), List(Str) -> List(U8)
	feed = |src, viewer, name, json, scripts| {
		title = Str.to_utf8(if name == "images" "Images" else "Code")
		s = { tab: title, title, viewer, active: Str.to_utf8(name), src }
		Chrome.page(s, List.join([
			Str.to_utf8("<div class=\"chat-notify\" id=\"chat-notify\"></div><div id=\"${name}-mount\"></div><script id=\"${name}-data\" type=\"application/json\">"),
			Html.script_safe(json),
			Str.to_utf8("</script>"),
			List.join(List.map(scripts, |js| Chrome.script(s, js))),
		]))
	}

	## recent.zig's /chat/recent: the attention strip, the feed's mount, its
	## JSON (script-safe) and its two scripts.
	recent : (List(U8) -> List(U8)), List(U8), List(U8) -> List(U8)
	recent = |src, viewer, json| {
		s = { tab: Str.to_utf8("Recent"), title: Str.to_utf8("Recent"), viewer, active: Str.to_utf8("recent"), src }
		Chrome.page(s, List.join([
			Str.to_utf8("<div class=\"chat-notify\" id=\"chat-notify\"></div><div id=\"recent-mount\"></div><script id=\"recent-data\" type=\"application/json\">"),
			Html.script_safe(json),
			Str.to_utf8("</script>"),
			Chrome.script(s, "recent.js"),
			Chrome.script(s, "notify.js"),
		]))
	}

	## /chat/images: the newest entries of the member's images.md.
	images : (List(U8) -> List(U8)), List(U8), List(U8) -> List(U8)
	images = |src, viewer, json| feed(src, viewer, "images", json, ["styles.js", "chat_image_popup.js", "images.js", "notify.js"])

	## /chat/code: every entry of the member's code.md.
	code : (List(U8) -> List(U8)), List(U8), List(U8) -> List(U8)
	code = |src, viewer, json| feed(src, viewer, "code", json, ["styles.js", "chat_code_popup.js", "code.js", "notify.js"])

	## noConversationsHtml: /chat for a viewer with nothing to resume.
	no_conversations : (List(U8) -> List(U8)), List(U8) -> List(U8)
	no_conversations = |src, viewer|
		Chrome.page(shell(src, Str.to_utf8("Chat"), viewer, Str.to_utf8("chat")), Str.to_utf8("<p>You do not have any conversations.</p>"))

	## conversationHtml: the page that boots the chat's client.
	conversation : (List(U8) -> List(U8)), Limits, View -> List(U8)
	conversation = |src, limits, v| {
		s = shell(src, v.title, v.viewer, [])
		attr = |name, value| List.join([Str.to_utf8(" ${name}=\""), value, ['"']])
		num = |n| Str.to_utf8(U64.to_str(n))
		Chrome.page(s, List.join([
			Str.to_utf8(Chrome.chat_css),
			Str.to_utf8("<div id=\"chat-root\""),
			attr("data-conv", Html.escape(v.key)),
			attr("data-conv-base", Html.escape(v.base)),
			attr("data-session", Html.escape(v.sid)),
			attr("data-me", Html.escape(v.uid)),
			attr("data-me-name", Html.escape(v.viewer)),
			attr("data-upload-image-max", num(limits.image_max)),
			attr("data-upload-video-max", num(limits.video_max)),
			attr("data-upload-accept", limits.accept),
			attr("data-search-min", num(limits.search_min)),
			Str.to_utf8("><div class=\"chat-notify\" id=\"chat-notify\"></div><div class=\"chat-layout\"><div id=\"chat-left-sidebar\"></div><script type=\"application/json\" id=\"chat-sidebar-data\">"),
			v.sidebar_json,
			Str.to_utf8("</script><div id=\"chat-feed\"></div><div id=\"chat-right-sidebar\"></div></div></div>"),
			List.join(List.map(page_scripts, |name| Chrome.script(s, name))),
		]))
	}

	## The bundles the conversation page loads, in document order.
	page_scripts : List(Str)
	page_scripts = ["chat_image_popup.js", "chat_code_popup.js", "chat_time_popup.js", "chat_save_popup.js", "message.js", "message_view.js", "nav_stack.js", "middle_pane.js", "chat_search.js", "chat_drag_to_pin.js", "chat_add_topic.js", "chat_left_sidebar.js", "chat_right_sidebar.js", "chat_emoji.js", "chat_reactions.js", "chat_compose.js", "chat_help.js", "chat_responsive.js", "chat.js", "notify.js"]

	## sidebarJSON: every other member (a DM each) and the viewer's channels,
	## then this conversation's topics, pinned and not; made safe inside the
	## page's `<script>`.
	sidebar_json : Sidebar -> List(U8)
	sidebar_json = |sb| {
		prefixed = |prefix, s| List.concat(Str.to_utf8(prefix), s)
		person = |u| {
			pk = Paths.pair_key(sb.uid, u.id)
			online = if u.online [("online", JsonText.bool(Bool.True))] else []
			JsonText.obj(List.concat([("id", JsonText.str(prefixed("uid:", u.id))), ("label", JsonText.str(u.name)), ("url", JsonText.str(prefixed("/chat/c/", pk))), ("active", JsonText.bool(sb.dm and pk == sb.key))], online))
		}
		room = |name|
			JsonText.obj([("id", JsonText.str(prefixed("ch:", name))), ("label", JsonText.str(prefixed("# ", name))), ("url", JsonText.str(prefixed("/channel/", name))), ("active", JsonText.bool(!sb.dm and name == sb.key))])
		topic = |s|
			JsonText.obj([("id", JsonText.str(s)), ("label", JsonText.str(s)), ("url", JsonText.str(List.join([sb.base, ['/'], s]))), ("active", JsonText.bool(s == sb.sid))])
		pinned = List.keep_if(sb.topics, |s| List.contains(sb.pins, s))
		rest = List.drop_if(sb.topics, |s| List.contains(sb.pins, s))
		Html.script_safe(JsonText.obj([
			("conversations", JsonText.arr(List.concat(List.map(sb.others, person), List.map(sb.channels, room)))),
			("pinned_sessions", JsonText.arr(List.map(pinned, topic))),
			("topics", JsonText.arr(List.map(rest, topic))),
		]))
	}

	## The sidebar as the twin hands it (angry-gopher chat_twin_test.zig, to
	## chat/twin.roc): the viewer, "1" for a DM, the key, base and topic,
	## then each list counted: the others (id, name, "1" when online), the
	## channels, the pins, the topics. The chat's own page reads its sidebar
	## itself (chat/main.roc `sidebar!`).
	decode_sidebar : List(List(U8)) -> Sidebar
	decode_sidebar = |fields| {
		at = |i| List.get(fields, i) ?? []
		n_others = ZigText.parse_u64(at(5)) ?? 0
		others = List.sublist(fields, { start: 6, len: n_others }) |> List.map_with_index(|_, k| { id: at(6 + 3 * k), name: at(7 + 3 * k), online: at(8 + 3 * k) == ['1'] })
		(channels, after_channels) = counted(fields, 6 + 3 * n_others)
		(pins, after_pins) = counted(fields, after_channels)
		(topics, _) = counted(fields, after_pins)
		{ uid: at(0), dm: at(1) == ['1'], key: at(2), base: at(3), sid: at(4), others, channels, pins, topics }
	}

	## A count at `i`, then that many: the items, and where the next begins.
	counted : List(List(U8)), U64 -> (List(List(U8)), U64)
	counted = |fields, i| {
		n = ZigText.parse_u64(List.get(fields, i) ?? []) ?? 0
		(List.sublist(fields, { start: i + 1, len: n }), i + 1 + n)
	}
}
