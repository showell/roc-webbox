## THE CHAT'S PAGES (angry-gopher chat_page.zig): the conversation page and
## the sidebar it boots with, the first-topic shell, a 404 that says why, and
## the empty /chat. Each from what the host read; the chrome is Chrome.roc's.
import Chrome
import Html
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

	## noConversationsHtml: /chat for a viewer with nothing to resume.
	no_conversations : (List(U8) -> List(U8)), List(U8) -> List(U8)
	no_conversations = |src, viewer|
		Chrome.page(shell(src, Str.to_utf8("Chat"), viewer, Str.to_utf8("chat")), Str.to_utf8("<p>You do not have any conversations.</p>"))

	## conversationHtml: the page that boots the chat's client.
	conversation : (List(U8) -> List(U8)), Limits, View -> List(U8)
	conversation = |src, limits, v| {
		s = shell(src, v.title, v.viewer, [])
		attr = |name, value| List.join([Str.to_utf8(" ${name}=\""), value, [34]])
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
		people = List.map(sb.others, |u| {
			pk = Paths.pair_key(sb.uid, u.id)
			List.join([
				Str.to_utf8("{\"id\":\"uid:"),
				u.id,
				Str.to_utf8("\",\"label\":"),
				ZigText.json_string(u.name),
				Str.to_utf8(",\"url\":\"/chat/c/"),
				pk,
				Str.to_utf8("\",\"active\":"),
				bool(sb.dm and pk == sb.key),
				if u.online Str.to_utf8(",\"online\":true") else [],
				Str.to_utf8("}"),
			])
		})
		rooms = List.map(sb.channels, |name|
			List.join([
				Str.to_utf8("{\"id\":\"ch:"),
				name,
				Str.to_utf8("\",\"label\":"),
				ZigText.json_string(List.concat(Str.to_utf8("# "), name)),
				Str.to_utf8(",\"url\":\"/channel/"),
				name,
				Str.to_utf8("\",\"active\":"),
				bool(!sb.dm and name == sb.key),
				Str.to_utf8("}"),
			]))
		item = |s| {
			url = List.join([sb.base, [47], s])
			List.join([
				Str.to_utf8("{\"id\":"),
				ZigText.json_string(s),
				Str.to_utf8(",\"label\":"),
				ZigText.json_string(s),
				Str.to_utf8(",\"url\":"),
				ZigText.json_string(url),
				Str.to_utf8(",\"active\":"),
				bool(s == sb.sid),
				Str.to_utf8("}"),
			])
		}
		pinned = List.keep_if(sb.topics, |s| List.contains(sb.pins, s))
		rest = List.drop_if(sb.topics, |s| List.contains(sb.pins, s))
		comma = |items| List.join(List.intersperse(items, [44]))
		Html.script_safe(List.join([
			Str.to_utf8("{\"conversations\":["),
			comma(List.concat(people, rooms)),
			Str.to_utf8("],\"pinned_sessions\":["),
			comma(List.map(pinned, item)),
			Str.to_utf8("],\"topics\":["),
			comma(List.map(rest, item)),
			Str.to_utf8("]}"),
		]))
	}

	## The sidebar as it crosses from the host (angry-gopher chat_page.zig
	## `sidebarFields`): the viewer, "1" for a DM, the key, base and topic,
	## then each list counted: the others (id, name, "1" when online), the
	## channels, the pins, the topics.
	decode_sidebar : List(List(U8)) -> Sidebar
	decode_sidebar = |fields| {
		at = |i| List.get(fields, i) ?? []
		n_others = ZigText.parse_u64(at(5)) ?? 0
		others = List.sublist(fields, { start: 6, len: n_others }) |> List.map_with_index(|_, k| { id: at(6 + 3 * k), name: at(7 + 3 * k), online: at(8 + 3 * k) == [49] })
		(channels, after_channels) = counted(fields, 6 + 3 * n_others)
		(pins, after_pins) = counted(fields, after_channels)
		(topics, _) = counted(fields, after_pins)
		{ uid: at(0), dm: at(1) == [49], key: at(2), base: at(3), sid: at(4), others, channels, pins, topics }
	}

	## A count at `i`, then that many: the items, and where the next begins.
	counted : List(List(U8)), U64 -> (List(List(U8)), U64)
	counted = |fields, i| {
		n = ZigText.parse_u64(List.get(fields, i) ?? []) ?? 0
		(List.sublist(fields, { start: i + 1, len: n }), i + 1 + n)
	}

	## A number the host sent as its digits.
	number : List(U8) -> U64
	number = |digits| ZigText.parse_u64(digits) ?? 0

	bool : Bool -> List(U8)
	bool = |b| if b Str.to_utf8("true") else Str.to_utf8("false")
}
