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
import Uid
import BusKey
import ChatUrl

Fanout := [].{

	## A message's parts, as its feeds keep them: the Recent row's excerpt,
	## the `<img>` tags, the code blocks.
	Parts : {
		excerpt : Str,
		images : List(Str),
		code : List(Feeds.Block),
	}

	## The parts of a message's markdown `md` (Recent.excerpt, Feeds.img_tags,
	## Feeds.code_blocks; the twins hold each to its Zig).
	parts_of : Str -> Parts
	parts_of = |md| {
		excerpt: Recent.excerpt(md),
		images: Feeds.img_tags(md),
		code: Feeds.code_blocks(md),
	}

	## The surfaces that can fail for a member, as /admin/host names them
	## (Host.report_fanout_failure!'s; a feed's append is the one that still can).
	Surface : [Code, Images]

	## One step of the fan-out, in the order it is taken:
	## - `Publish`: bytes on a member's key (it cannot fail);
	## - `Feed`: an entry appended to a member's feed file, and only then
	##   its event published; an append that failed is that surface's
	##   failure, counted, and its event never sent.
	Step : [
		Publish(BusKey, List(U8)),
		Feed(
			{
				surface : Surface,
				member : List(U8),
				path : Paths.ChatPath,
				entry : List(U8),
				key : BusKey,
				event : List(U8),
			},
		),
	]

	## A message stored in a conversation (its key and its members), as the
	## fan-out takes it: its `topic` (as the request
	## spelled it), its number `index` (0 is the topic's first), its fields,
	## its author's account `uid`, and the accounts the request holds (a
	## DM's; a channel names none).
	Sent : {
		key : Paths.ConvKey,
		members : List(Uid),
		topic : Str,
		index : U64,
		id : Str,
		from : Str,
		at : Str,
		uid : Uid,
		accounts : List(Accounts.Account),
	}

	## **EVERY MEMBER IN THE CONVERSATION'S ORDER, EACH MEMBER'S SURFACES IN
	## ONE ORDER: NOTIFY, SIDEBAR, RECENT, IMAGES, CODE** (fanoutCrossPage).
	## **ONE SURFACE AT A TIME** (metal-vmm QUEUE 156(c)): a surface that
	## fails costs that member that surface, and never their others or any
	## other member's.
	steps : Sent, Parts -> List(Step)
	steps = |m, parts| {
		at = { key: m.key, topic: m.topic }
		url = ChatUrl.topic(at).to_str()
		notify = notify_event(at, notify_text(m.from, at))
		added = topic_added(at)
		head = {
			from: m.from,
			at: m.at,
			source_id: m.id,
			conv: m.key.to_str(),
		}
		List.join(
			List.map(
				m.members,
				|uid|
					List.join([
						# **THE AUTHOR IS NEVER NOTIFIED** of their own message: the
						# favicon dot means a partner did something.
						if uid == m.uid [] else [Publish(BusKey.notify(uid), notify)],
						# A topic is added to the sidebar by its first message alone.
						if m.index == 0 [Publish(BusKey.sidebar(uid), added)] else [],
						# **EVERY MEMBER SEES THE ROW, THE AUTHOR AS "YOU"**.
						{
							who = if uid == m.uid "You" else m.from
							[
								Publish(
									BusKey.recent(uid),
									Recent.chat_event({
										at: m.at,
										url,
										who,
										label: recent_where(m, uid),
										topic: m.topic,
										excerpt: parts.excerpt,
										dm: m.key.kind(),
									}),
								),
							]
						},
						# The feeds only when the message has what they keep.
						match parts.images {
							[] => []
							tags => [
								Feed({
									surface: Images,
									member: uid.to_str().to_utf8(),
									path: Paths.feed_path(uid, Images),
									entry: Feeds.images_entry(head, tags),
									key: BusKey.images(uid),
									event: Feeds.images_event(head, tags),
								}),
							]
						},
						match parts.code {
							[] => []
							blocks => [
								Feed({
									surface: Code,
									member: uid.to_str().to_utf8(),
									path: Paths.feed_path(uid, Code),
									entry: Feeds.code_entry(head, blocks),
									key: BusKey.code(uid),
									event: Feeds.code_event(head, blocks),
								}),
							]
						},
					]),
			),
		)
	}

	## The status strip's line: a DM's "X sent you a message on <topic>.", a
	## channel's "X posted to <key> > <topic>.".
	notify_text : Str, Paths.TopicAt -> Str
	notify_text = |from, at|
		match at.key {
			Dm(_) => "${from} sent you a message on ${at.topic}."
			Channel(name) => "${from} posted to ${name.to_str()} > ${at.topic}."
		}

	## The notify stream's event: conv, session, text, link_url (ChatUrl.topic).
	notify_event : Paths.TopicAt, Str -> List(U8)
	notify_event = |at, text| JsonText.obj([
		("conv", JsonText.str(at.key.to_str())),
		("session", JsonText.str(at.topic)),
		("text", JsonText.str(text)),
		("link_url", JsonText.str(ChatUrl.topic(at).to_str())),
	])

	## The sidebar stream's topic-added: kind, conv, sid, url (ChatUrl.topic).
	topic_added : Paths.TopicAt -> List(U8)
	topic_added = |at| JsonText.obj([
		("kind", JsonText.str("topic-added")),
		("conv", JsonText.str(at.key.to_str())),
		("sid", JsonText.str(at.topic)),
		("url", JsonText.str(ChatUrl.topic(at).to_str())),
	])

	## chat_fanout `recentWhere`, for `viewer`: a channel names itself ("in
	## <key>"); a DM names the other member ("to <name>"; the DM with
	## yourself has none, so "to " and the name of no one). **A NAME THAT
	## WILL NOT READ GIVES ""** (its absent-ok): the label only, the row is
	## still sent.
	recent_where : Sent, Uid -> Str
	recent_where = |m, viewer|
		match m.key {
			Channel(name) => "in ${name.to_str()}"
			Dm(_) => {
				# The DM with yourself has no other member, so no name.
				match List.keep_if(m.members, |member| member != viewer).last() {
					Ok(other) =>
						match Accounts.name(m.accounts, other) {
							Ok(name) => "to ${name}"
							Err(_) => ""
						}
					Err(_) => "to "
				}
			}
		}
}
