## **A STORED MESSAGE, OUT TO EVERY MEMBER'S CROSS-PAGE SURFACES**
## (angry-gopher chat_fanout `fanoutCrossPage`, `Fan`): who gets which of
## the five surfaces, on which key, as which bytes, and which feed files
## take an entry, as the steps chat/main.roc carries out after the store.
## Pure: the markdown's parts are Recent's and Feeds' (`parts_of`), everything
## else is this module's. angry-gopher's
## chat_twin_test.zig holds each encoder to its Zig, and
## chat_actions_twin_test.zig a whole send's frames and files.
import Feeds
import Recent
import Accounts
import JsonText
import Paths

Fanout := [].{

	## A message's parts, as its feeds keep them: the Recent row's excerpt,
	## the `<img>` tags, the code blocks.
	Parts : { excerpt : List(U8), images : List(List(U8)), code : List(Feeds.Block) }

	## The parts of a message's markdown `md` (Recent.excerpt, Feeds.img_tags,
	## Feeds.code_blocks; the twins hold each to its Zig).
	parts_of : List(U8) -> Parts
	parts_of = |md| { excerpt: Recent.excerpt(md), images: Feeds.img_tags(md), code: Feeds.code_blocks(md) }

	## The surfaces that can fail for a member, as /admin/host names them
	## (Host.fanout_failed!'s; a feed's append is the one that still can).
	Surface : [Code, Images]

	## One step of the fan-out, in the order it is taken:
	## - `Publish`: bytes on a member's key (it cannot fail);
	## - `Feed`: an entry appended to a member's feed file, and only then
	##   its event published; an append that failed is that surface's
	##   failure, counted, and its event never sent.
	Step : [
		Publish(List(U8), List(U8)),
		Feed({ surface : Surface, member : List(U8), path : Paths.ChatPath, entry : List(U8), key : List(U8), event : List(U8) }),
	]

	## A message stored in a conversation (its key and its members), as the
	## fan-out takes it: its `topic` (as the request
	## spelled it), its number `index` (0 is the topic's first), its fields,
	## its author's account `uid`, and the accounts the request holds (a
	## DM's; a channel names none).
	Sent : { key : Paths.ConvKey, members : List(List(U8)), topic : List(U8), index : U64, id : List(U8), from : List(U8), at : List(U8), uid : List(U8), accounts : List(Accounts.Account) }

	## **EVERY MEMBER IN THE CONVERSATION'S ORDER, EACH MEMBER'S SURFACES IN
	## ONE ORDER: NOTIFY, SIDEBAR, RECENT, IMAGES, CODE** (fanoutCrossPage).
	## **ONE SURFACE AT A TIME** (metal-vmm QUEUE 156(c)): a surface that
	## fails costs that member that surface, and never their others or any
	## other member's.
	steps : Sent, Parts -> List(Step)
	steps = |m, parts| {
		at = { key: m.key, topic: m.topic }
		url = topic_url(at)
		notify = notify_event(at, notify_text(m.from, at))
		added = topic_added(at)
		head = { from: m.from, at: m.at, source_id: m.id, conv: Paths.conv_key_bytes(m.key) }
		List.join(
			List.map(
				m.members,
				|uid|
					List.join([
						# **THE AUTHOR IS NEVER NOTIFIED** of their own message: the
						# favicon dot means a partner did something.
						if uid == m.uid [] else [Publish(notify_key(uid), notify)],
						# A topic is added to the sidebar by its first message alone.
						if m.index == 0 [Publish(sidebar_key(uid), added)] else [],
						# **EVERY MEMBER SEES THE ROW, THE AUTHOR AS "YOU"**.
						{
							who = if uid == m.uid Str.to_utf8("You") else m.from
							[Publish(recent_key(uid), Recent.chat_event({ at: m.at, url, who, label: recent_where(m, uid), topic: m.topic, excerpt: parts.excerpt, dm: Paths.conv_kind(m.key) }))]
						},
						# The feeds only when the message has what they keep.
						match parts.images {
							[] => []
							tags => [Feed({ surface: Images, member: uid, path: Paths.feed_path(uid, Images), entry: Feeds.images_entry(head, tags), key: images_key(uid), event: Feeds.images_event(head, tags) })]
						},
						match parts.code {
							[] => []
							blocks => [Feed({ surface: Code, member: uid, path: Paths.feed_path(uid, Code), entry: Feeds.code_entry(head, blocks), key: code_key(uid), event: Feeds.code_event(head, blocks) })]
						},
					]),
			),
		)
	}

	## **THE PER-MEMBER BUS KEYS** (chat_fanout `notifyBusKey`,
	## `sidebarBusKey`, `recentBusKey`, `imagesBusKey`, `codeBusKey`): each
	## namespaced, so none meets a topic's `<key>/<topic>` (topic_key). The Zig streams
	## that serve them subscribe with the Zig's own, held equal by the twins.
	notify_key : List(U8) -> List(U8)
	notify_key = |uid| List.concat(Str.to_utf8("ntf:"), uid)

	sidebar_key : List(U8) -> List(U8)
	sidebar_key = |uid| List.concat(Str.to_utf8("sb:"), uid)

	recent_key : List(U8) -> List(U8)
	recent_key = |uid| List.concat(Str.to_utf8("rec:"), uid)

	images_key : List(U8) -> List(U8)
	images_key = |uid| List.concat(Str.to_utf8("img:"), uid)

	code_key : List(U8) -> List(U8)
	code_key = |uid| List.concat(Str.to_utf8("code:"), uid)

	## The topic's live bus key, where its messages and reactions are
	## published: `<key>/<topic>`.
	topic_key : Paths.TopicAt -> List(U8)
	topic_key = |{ key, topic }| List.join([Paths.conv_key_bytes(key), ['/'], topic])

	## **THE TYPED LAYER AND ITS BYTES CORES**: production calls topic_url,
	## notify_text, notify_event and topic_added on a TopicAt; each unwraps
	## its key and calls its `_bytes` core, which the twins feed any bytes
	## (`""`, `\xff`, `../x`) to hold it to the Zig. Only the twins call a
	## core (the hunt bytes_core_outside_twin).
	TopicBytes : { key : List(U8), topic : List(U8) }

	unwrapped : Paths.TopicAt -> TopicBytes
	unwrapped = |at| { key: Paths.conv_key_bytes(at.key), topic: at.topic }

	## The topic's page: the conversation's URL root (Feeds.base_url,
	## convKeyBaseURL), then the topic.
	topic_url : Paths.TopicAt -> List(U8)
	topic_url = |at| topic_url_bytes(unwrapped(at))

	topic_url_bytes : TopicBytes -> List(U8)
	topic_url_bytes = |{ key, topic }| List.join([Feeds.base_url(key), ['/'], topic])

	## The status strip's line: a DM's "X sent you a message on <topic>.", a
	## channel's "X posted to <key> > <topic>.".
	notify_text : List(U8), Paths.TopicAt -> List(U8)
	notify_text = |from, at| notify_text_bytes(Paths.conv_kind(at.key), from, unwrapped(at))

	notify_text_bytes : [Dm, Channel], List(U8), TopicBytes -> List(U8)
	notify_text_bytes = |kind, from, { key, topic }|
		match kind {
			Dm => List.join([from, Str.to_utf8(" sent you a message on "), topic, ['.']])
			Channel => List.join([from, Str.to_utf8(" posted to "), key, Str.to_utf8(" > "), topic, ['.']])
		}

	## The notify stream's event: conv, session, text, link_url (topic_url).
	notify_event : Paths.TopicAt, List(U8) -> List(U8)
	notify_event = |at, text| notify_event_bytes(unwrapped(at), text)

	notify_event_bytes : TopicBytes, List(U8) -> List(U8)
	notify_event_bytes = |at, text| JsonText.obj([("conv", JsonText.str(at.key)), ("session", JsonText.str(at.topic)), ("text", JsonText.str(text)), ("link_url", JsonText.str(topic_url_bytes(at)))])

	## The sidebar stream's topic-added: kind, conv, sid, url (topic_url).
	topic_added : Paths.TopicAt -> List(U8)
	topic_added = |at| topic_added_bytes(unwrapped(at))

	topic_added_bytes : TopicBytes -> List(U8)
	topic_added_bytes = |at| JsonText.obj([("kind", JsonText.str(Str.to_utf8("topic-added"))), ("conv", JsonText.str(at.key)), ("sid", JsonText.str(at.topic)), ("url", JsonText.str(topic_url_bytes(at)))])

	## chat_fanout `recentWhere`, for `viewer`: a channel names itself ("in
	## <key>"); a DM names the other member ("to <name>"; the DM with
	## yourself has none, so "to " and the name of no one). **A NAME THAT
	## WILL NOT READ GIVES ""** (its absent-ok): the label only, the row is
	## still sent.
	recent_where : Sent, List(U8) -> List(U8)
	recent_where = |m, viewer|
		match m.key {
			Channel(name) => List.concat(Str.to_utf8("in "), Paths.channel_name_bytes(name))
			Dm(_) => {
				other = List.fold(m.members, [], |found, member| if member != viewer member else found)
				match Accounts.name(m.accounts, other) {
					Ok(name) => List.concat(Str.to_utf8("to "), name)
					Err(_) => []
				}
			}
		}
}
