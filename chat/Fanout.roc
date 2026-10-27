## **A STORED MESSAGE, OUT TO EVERY MEMBER'S CROSS-PAGE SURFACES**
## (angry-gopher chat_fanout `fanoutCrossPage`, `Fan`): who gets which of
## the five surfaces, on which key, as which bytes, and which feed files
## take an entry, as the steps chat/main.roc carries out after the store.
## Pure: the markdown's parts are the host's (Host.message_parts!, the one
## markdown reader), everything else is this module's. angry-gopher's
## chat_twin_test.zig holds each encoder to its Zig, and
## chat_actions_twin_test.zig a whole send's frames and files.
import Feeds
import Recent
import Accounts
import JsonText
import Paths

Fanout := [].{

	## The message's parts as the host found them, each made or failed on
	## its own (its fault: the host's error, a number this module never
	## reads, carried to be said).
	Parts : { excerpt : [Made(List(U8)), Failed(U16)], images : [Made(List(List(U8))), Failed(U16)], code : [Made(List(Feeds.Block)), Failed(U16)] }

	## The surfaces that can fail for a member, as /admin/host names them.
	Surface : [Code, Images, Recent]

	## One step of the fan-out, in the order it is taken:
	## - `Publish`: bytes on a member's key (it cannot fail);
	## - `Feed`: an entry appended to a member's feed file, and only then
	##   its event published; an append that failed is that surface's
	##   failure, counted, and its event never sent;
	## - `Failed`: a surface that cannot be made for a member (a part that
	##   failed), counted and said.
	Step : [
		Publish(List(U8), List(U8)),
		Feed({ surface : Surface, member : List(U8), path : Paths.ChatPath, entry : List(U8), key : List(U8), event : List(U8) }),
		Failed(Surface, List(U8), U16),
	]

	## A message stored in a conversation (`kind`, its key and its
	## members), as the fan-out takes it: its `topic` (as the request
	## spelled it), its number `index` (0 is the topic's first), its fields,
	## its author's account `uid`, and the accounts the request holds (a
	## DM's; a channel names none).
	Sent : { kind : [Dm, Channel], key : List(U8), members : List(List(U8)), topic : List(U8), index : U64, id : List(U8), from : List(U8), at : List(U8), uid : List(U8), accounts : List(Accounts.Account) }

	## **EVERY MEMBER IN THE CONVERSATION'S ORDER, EACH MEMBER'S SURFACES IN
	## ONE ORDER: NOTIFY, SIDEBAR, RECENT, IMAGES, CODE** (fanoutCrossPage).
	## **ONE SURFACE AT A TIME** (metal-vmm QUEUE 156(c)): a surface that
	## fails costs that member that surface, and never their others or any
	## other member's.
	steps : Sent, Parts -> List(Step)
	steps = |m, parts| {
		at = { key: m.key, topic: m.topic }
		url = topic_url(at)
		notify = notify_event(at, notify_text(m.kind, m.from, at))
		added = topic_added(at)
		head = { from: m.from, at: m.at, source_id: m.id, conv: m.key }
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
						match parts.excerpt {
							Made(excerpt) => {
								who = if uid == m.uid Str.to_utf8("You") else m.from
								[Publish(recent_key(uid), Recent.chat_event({ at: m.at, url, who, label: recent_where(m, uid), topic: m.topic, excerpt, dm: if m.kind == Dm Dm else Channel }))]
							}
							Failed(fault) => [Failed(Recent, uid, fault)]
						},
						# The feeds only when the message has what they keep; a part
						# that failed fails them whatever it held.
						match parts.images {
							Made([]) => []
							Made(tags) => [Feed({ surface: Images, member: uid, path: Paths.feed_path(uid, Images), entry: Feeds.images_entry(head, tags), key: images_key(uid), event: Feeds.images_event(head, tags) })]
							Failed(fault) => [Failed(Images, uid, fault)]
						},
						match parts.code {
							Made([]) => []
							Made(blocks) => [Feed({ surface: Code, member: uid, path: Paths.feed_path(uid, Code), entry: Feeds.code_entry(head, blocks), key: code_key(uid), event: Feeds.code_event(head, blocks) })]
							Failed(fault) => [Failed(Code, uid, fault)]
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
	topic_key = |{ key, topic }| List.join([key, ['/'], topic])

	## The topic's page: the conversation's URL root (Feeds.base_url,
	## convKeyBaseURL), then the topic.
	topic_url : Paths.TopicAt -> List(U8)
	topic_url = |{ key, topic }| List.join([Feeds.base_url(key), ['/'], topic])

	## The status strip's line: a DM's "X sent you a message on <topic>.", a
	## channel's "X posted to <key> > <topic>.".
	notify_text : [Dm, Channel], List(U8), Paths.TopicAt -> List(U8)
	notify_text = |kind, from, { key, topic }|
		match kind {
			Dm => List.join([from, Str.to_utf8(" sent you a message on "), topic, ['.']])
			Channel => List.join([from, Str.to_utf8(" posted to "), key, Str.to_utf8(" > "), topic, ['.']])
		}

	## The notify stream's event: conv, session, text, link_url (topic_url).
	notify_event : Paths.TopicAt, List(U8) -> List(U8)
	notify_event = |at, text| JsonText.obj([("conv", JsonText.str(at.key)), ("session", JsonText.str(at.topic)), ("text", JsonText.str(text)), ("link_url", JsonText.str(topic_url(at)))])

	## The sidebar stream's topic-added: kind, conv, sid, url (topic_url).
	topic_added : Paths.TopicAt -> List(U8)
	topic_added = |at| JsonText.obj([("kind", JsonText.str(Str.to_utf8("topic-added"))), ("conv", JsonText.str(at.key)), ("sid", JsonText.str(at.topic)), ("url", JsonText.str(topic_url(at)))])

	## chat_fanout `recentWhere`, for `viewer`: a channel names itself ("in
	## <key>"); a DM names the other member ("to <name>"; the DM with
	## yourself has none, so "to " and the name of no one). **A NAME THAT
	## WILL NOT READ GIVES ""** (its absent-ok): the label only, the row is
	## still sent.
	recent_where : Sent, List(U8) -> List(U8)
	recent_where = |m, viewer|
		match m.kind {
			Channel => List.concat(Str.to_utf8("in "), m.key)
			Dm => {
				other = List.fold(m.members, [], |found, member| if member != viewer member else found)
				match Accounts.name(m.accounts, other) {
					Ok(name) => List.concat(Str.to_utf8("to "), name)
					Err(_) => []
				}
			}
		}
}
