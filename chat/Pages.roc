## THE CHAT'S PAGES (angry-gopher chat_page.zig): the conversation page and
## the sidebar it boots with, the first-topic shell, a 404 that says why, and
## the empty /chat. Each from what the host read; the chrome is Chrome.roc's.
import Bytes
import Chrome
import Html
import JsonText
import Paths
import Uid
import ZigText

Pages := [].{

	## The server's limits the conversation page tells its client (the
	## client's only copy).
	Limits : { image_max : U64, video_max : U64, accept : List(U8), search_min : U64 }

	## What the conversation page shows: the conversation's key and URL base,
	## the topic, its title, the viewer, and the sidebar's JSON.
	View : { key : Str, base : Str, topic : Str, title : Str, uid : Uid, viewer : Str, sidebar_json : Html.ScriptJson }

	## What the sidebar shows: the viewer, the conversation (its kind), the
	## topic, every other member (each online or not), the viewer's channels,
	## their pins in this conversation, and its topics.
	Sidebar : { uid : Uid, kind : [Dm, Channel], key : Str, base : Str, topic : Str, others : List({ id : Uid, name : Str, presence : [Online, Offline] }), channels : List(Str), pins : List(Str), topics : List(Str) }

	## A chat page's heading: its `title`, the `viewer`, and the nav item
	## `active`. Named fields because all three are text.
	Heading : { title : Str, viewer : Str, active : Str }

	## A conversation with no topics yet: the `viewer`, its URL `base`, and
	## its `title`.
	Topicless : { viewer : Str, base : Str, title : Str }

	## noTopicsHtml: an addressable conversation with no topics, its
	## first-topic widget mounted on `base`.
	no_topics : (List(U8) -> Html), Topicless -> Html
	no_topics = |src, { viewer, base, title }| {
		s = shell(src, { title, viewer, active: "chat" })
		Chrome.page(
			s,
			Html.join([
				Html.trusted("<div id=\"chat-first-topic\" data-conv-base=\""),
				Html.text(base),
				Html.trusted("\"></div>"),
				Chrome.script(s, "chat_add_topic.js"),
				Chrome.script(s, "chat_first_topic.js"),
			]),
		)
	}

	## What a 404 tells the `viewer`: `what` is not here, and `back` is where
	## to go.
	NotHere : { viewer : Str, what : Str, back : Str }

	## notFoundHtml: `what` is not here, and `back` is where to go.
	not_found : (List(U8) -> Html), NotHere -> Html
	not_found = |src, { viewer, what, back }|
		Chrome.page(
			shell(src, { title: "Not here", viewer, active: "chat" }),
			Html.join([
				Html.trusted("<p>"),
				Html.text(what),
				Html.trusted("</p><p><a href=\""),
				Html.text(back),
				Html.trusted("\">Go back</a></p>"),
			]),
		)

	## chat_links.zig's /chat/links: the member's curated links where the
	## host holds them (`Held`, a mark the host fills), or the stub that says
	## who curates them, in a readable column of its own.
	links : (List(U8) -> Html), Str, [Held, NoLinks] -> Html
	links = |src, viewer, rendered|
		Chrome.page(
			{ tab: Html.trusted("Links"), title: "Links", viewer, active: "links", src },
			Html.join([
				links_css,
				Html.trusted("<div class=\"links-page\">"),
				match rendered {
					Held => Html.trusted("\u(0)")
					NoLinks => Html.trusted("<p>No links yet — ask Steve to curate links.</p>")
				},
				Html.trusted("</div>"),
			]),
		)

	## The links page cut where the rendered links go: the host holds them
	## (a curated page can be long), and answers before, them, after.
	links_around : (List(U8) -> Html), Str -> (List(U8), List(U8))
	links_around = |src, viewer|
		match Bytes.cut_seq(Html.bytes(links(src, viewer, Held)), [0]) {
			Ok(parts) => parts
			Err(NotFound) => crash "Pages.links_around: the page lost its mark"
		}

	## A feed page's `viewer` and its feed's `json`.
	FeedView : { viewer : Str, json : List(U8) }

	## recent.zig's /chat/recent: the attention strip, the feed's mount, its
	## JSON (script-safe) and its two scripts.
	recent : (List(U8) -> Html), FeedView -> Html
	recent = |src, { viewer, json }| {
		s = { tab: Html.trusted("Recent"), title: "Recent", viewer, active: "recent", src }
		Chrome.page(
			s,
			Html.join([
				Html.trusted("<div class=\"chat-notify\" id=\"chat-notify\"></div><div id=\"recent-mount\"></div>"),
				Html.json_script(Html.trusted("<script id=\"recent-data\" type=\"application/json\">"), Html.script_safe(json)),
				Chrome.script(s, "recent.js"),
				Chrome.script(s, "notify.js"),
			]),
		)
	}

	## /chat/images: the newest entries of the member's images.md.
	images : (List(U8) -> Html), FeedView -> Html
	images = |src, { viewer, json }| feed(src, viewer, Images, json, ["styles.js", "chat_image_popup.js", "images.js", "notify.js"])

	## /chat/code: every entry of the member's code.md.
	code : (List(U8) -> Html), FeedView -> Html
	code = |src, { viewer, json }| feed(src, viewer, Code, json, ["styles.js", "chat_code_popup.js", "code.js", "notify.js"])

	## noConversationsHtml: /chat for a viewer with nothing to resume.
	no_conversations : (List(U8) -> Html), Str -> Html
	no_conversations = |src, viewer|
		Chrome.page(shell(src, { title: "Chat", viewer, active: "chat" }), Html.trusted("<p>You do not have any conversations.</p>"))

	## conversationHtml: the page that boots the chat's client.
	conversation : (List(U8) -> Html), Limits, View -> Html
	conversation = |src, limits, v| {
		s = shell(src, { title: v.title, viewer: v.viewer, active: "" })
		attr = |name, value| Html.join([Html.trusted(" "), Html.escape(Str.to_utf8(name)), Html.trusted("=\""), value, Html.trusted("\"")])
		num = |n| Html.escape(Str.to_utf8(U64.to_str(n)))
		Chrome.page(
			s,
			Html.join([
				Chrome.chat_css,
				Html.trusted("<div id=\"chat-root\""),
				attr("data-conv", Html.text(v.key)),
				attr("data-conv-base", Html.text(v.base)),
				attr("data-session", Html.text(v.topic)),
				attr("data-me", Html.text(v.uid.to_str())),
				attr("data-me-name", Html.text(v.viewer)),
				attr("data-upload-image-max", num(limits.image_max)),
				attr("data-upload-video-max", num(limits.video_max)),
				attr("data-upload-accept", Html.escape(limits.accept)),
				attr("data-search-min", num(limits.search_min)),
				Html.trusted("><div class=\"chat-notify\" id=\"chat-notify\"></div><div class=\"chat-layout\"><div id=\"chat-left-sidebar\"></div>"),
				Html.json_script(Html.trusted("<script type=\"application/json\" id=\"chat-sidebar-data\">"), v.sidebar_json),
				Html.trusted("<div id=\"chat-feed\"></div><div id=\"chat-right-sidebar\"></div></div></div>"),
				Html.join(List.map(page_scripts, |name| Chrome.script(s, name))),
			]),
		)
	}

	## sidebarJSON: every other member (a DM each) and the viewer's channels,
	## then this conversation's topics, pinned and not; made safe inside the
	## page's `<script>`.
	sidebar_json : Sidebar -> Html.ScriptJson
	sidebar_json = |sb| {
		person = |u| {
			pk = Paths.pair_key_to_str(Paths.pair_key(sb.uid, u.id))
			online = if u.presence == Online [("online", JsonText.bool(Bool.True))] else []
			JsonText.obj(List.concat([("id", JsonText.str("uid:${u.id.to_str()}")), ("label", JsonText.str(u.name)), ("url", JsonText.str("/chat/c/${pk}")), ("active", JsonText.bool(sb.kind == Dm and pk == sb.key))], online))
		}
		room = |name|
			JsonText.obj([("id", JsonText.str("ch:${name}")), ("label", JsonText.str("# ${name}")), ("url", JsonText.str("/channel/${name}")), ("active", JsonText.bool(sb.kind == Channel and name == sb.key))])
		topic = |s|
			JsonText.obj([("id", JsonText.str(s)), ("label", JsonText.str(s)), ("url", JsonText.str("${sb.base}/${s}")), ("active", JsonText.bool(s == sb.topic))])
		pinned = List.keep_if(sb.topics, |s| List.contains(sb.pins, s))
		rest = List.drop_if(sb.topics, |s| List.contains(sb.pins, s))
		Html.script_safe(
			JsonText.obj([
				("conversations", JsonText.arr(List.concat(List.map(sb.others, person), List.map(sb.channels, room)))),
				("pinned_sessions", JsonText.arr(List.map(pinned, topic))),
				("topics", JsonText.arr(List.map(rest, topic))),
			]),
		)
	}

	## The sidebar as the twin hands it (angry-gopher chat_twin_test.zig, to
	## chat/twin.roc): the viewer, "1" for a DM, the key, base and topic,
	## then each list counted: the others (id, name, "1" when online), the
	## channels, the pins, the topics. The chat's own page reads its sidebar
	## itself (chat/main.roc `sidebar!`). **ITS UIDS AND TEXT ARE DECODED
	## HERE, AT THE DOOR**: one that is no uid is `NotAUid`, text that is not
	## UTF-8 `NotUtf8`, a count that is no number `NotACount`.
	decode_sidebar : List(List(U8)) -> Try(Sidebar, [NotAUid, NotUtf8, NotACount])
	decode_sidebar = |fields| {
		at = |i| List.get(fields, i) ?? []
		text_at = |i| Str.from_utf8(at(i)).map_err(|_| NotUtf8)
		uid_at = |i| Uid.from_utf8(at(i))
		n_others = ZigText.parse_u64(at(5)).map_err(|_| NotACount)?
		others = List.sublist(fields, { start: 6, len: n_others }) |> List.map_with_index(|_, k| Ok({ id: uid_at(6 + 3 * k)?, name: text_at(7 + 3 * k)?, presence: if at(8 + 3 * k) == ['1'] Online else Offline }))
		(channels, after_channels) = counted(fields, 6 + 3 * n_others)?
		(pins, after_pins) = counted(fields, after_channels)?
		(topics, _) = counted(fields, after_pins)?
		Ok({ uid: uid_at(0)?, kind: if at(1) == ['1'] Dm else Channel, key: text_at(2)?, base: text_at(3)?, topic: text_at(4)?, others: List.map_try(others, |o| o)?, channels, pins, topics })
	}
}

shell : (List(U8) -> Html), Heading -> Chrome.Shell
shell = |src, { title, viewer, active }| { tab: Html.trusted("Chat"), title, viewer, active, src }

links_css : Html
links_css = Html.trusted("<style>\n.links-page { max-width: 46rem; margin: 0 auto; line-height: 1.55; }\n.links-page h2 { margin-top: 1.6rem; }\n.links-page li { margin: 3px 0; }\n</style>")

## images.zig's and code.zig's pages: the attention strip, the feed's
## mount, its JSON (`json`, script-safe) and its scripts.
feed : (List(U8) -> Html), Str, [Images, Code], List(U8), List(Str) -> Html
feed = |src, viewer, which, json, scripts| {
	(name, title) = match which {
		Images => ("images", "Images")
		Code => ("code", "Code")
	}
	s = { tab: Html.escape(Str.to_utf8(title)), title, viewer, active: name, src }
	id = Html.escape(Str.to_utf8(name))
	Chrome.page(
		s,
		Html.join([
			Html.trusted("<div class=\"chat-notify\" id=\"chat-notify\"></div><div id=\""),
			id,
			Html.trusted("-mount\"></div>"),
			Html.json_script(Html.join([Html.trusted("<script id=\""), id, Html.trusted("-data\" type=\"application/json\">")]), Html.script_safe(json)),
			Html.join(List.map(scripts, |js| Chrome.script(s, js))),
		]),
	)
}

## The bundles the conversation page loads, in document order.
page_scripts : List(Str)
page_scripts = ["chat_image_popup.js", "chat_code_popup.js", "chat_time_popup.js", "chat_save_popup.js", "message.js", "message_view.js", "nav_stack.js", "middle_pane.js", "chat_search.js", "chat_drag_to_pin.js", "chat_add_topic.js", "chat_left_sidebar.js", "chat_right_sidebar.js", "chat_emoji.js", "chat_reactions.js", "chat_compose.js", "chat_help.js", "chat_responsive.js", "chat.js", "notify.js"]

## A count at `i`, then that many texts, and where the next begins;
## `NotUtf8` when one is not text, `NotACount` when the count is no number.
counted : List(List(U8)), U64 -> Try((List(Str), U64), [NotUtf8, NotACount])
counted = |fields, i| {
	n = ZigText.parse_u64(List.get(fields, i) ?? []).map_err(|_| NotACount)?
	items = List.sublist(fields, { start: i + 1, len: n })
	texts = List.keep_oks(items, Str.from_utf8)
	if List.len(texts) == List.len(items) Ok((texts, i + 1 + n)) else Err(NotUtf8)
}
