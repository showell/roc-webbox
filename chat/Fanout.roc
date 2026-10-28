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
import JsonOut
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

	## The surfaces that can fail for a member (`failure` names them, as
	## /admin/host says them; a feed's append is the one that still can).
	Surface : [Code, Images]

	## **A SURFACE THAT FAILED FOR ONE MEMBER, IN THE OPERATOR'S WORDS**
	## (Host.count!'s text for a `FanoutFailure`):
	## "<surface> for member <member>, <fault>, on <key>/<sid>", `fault` the
	## name of the error the surface's aside ended with (Host.name_fault!).
	failure : Surface,
	{
		member : List(U8),
		key : List(U8),
		sid : List(U8),
		fault : List(U8),
	} -> List(U8)
	failure = |surface, f| {
		name = match surface {
			Code => "code"
			Images => "images"
		}
		List.join([
			Str.to_utf8("${name} for member "),
			f.member,
			Str.to_utf8(", "),
			f.fault,
			Str.to_utf8(", on "),
			f.key,
			['/'],
			f.sid,
		])
	}

	## One step of the fan-out, in the order it is taken:
	## - `Publish`: bytes on a member's key (it cannot fail);
	## - `AppendFeed`: an entry appended to a member's feed file, and only then
	##   its event published; an append that failed is that surface's
	##   failure, counted, and its event never sent.
	Step : [
		Publish(BusKey, List(U8)),
		AppendFeed(
			{
				surface : Surface,
				member : List(U8),
				path : Paths.ChatPath,
				sep : List(U8),
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
									}).bytes(),
								),
							]
						},
						# The feeds only when the message has what they keep.
						match parts.images {
							[] => []
							tags => [
								AppendFeed({
									surface: Images,
									member: uid.to_str().to_utf8(),
									path: Paths.feed_path(uid, Images),
									sep: Feeds.sep,
									entry: Feeds.images_entry(head, tags),
									key: BusKey.images(uid),
									event: Feeds.images_event(head, tags).bytes(),
								}),
							]
						},
						match parts.code {
							[] => []
							blocks => [
								AppendFeed({
									surface: Code,
									member: uid.to_str().to_utf8(),
									path: Paths.feed_path(uid, Code),
									sep: Feeds.sep,
									entry: Feeds.code_entry(head, blocks),
									key: BusKey.code(uid),
									event: Feeds.code_event(head, blocks).bytes(),
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
	notify_event = |at, text| JsonOut.object([
		("conv", JsonOut.string(at.key.to_str())),
		("session", JsonOut.string(at.topic)),
		("text", JsonOut.string(text)),
		("link_url", JsonOut.string(ChatUrl.topic(at).to_str())),
	]).bytes()

	## The sidebar stream's topic-added: kind, conv, sid, url (ChatUrl.topic).
	topic_added : Paths.TopicAt -> List(U8)
	topic_added = |at| JsonOut.object([
		("kind", JsonOut.string("topic-added")),
		("conv", JsonOut.string(at.key.to_str())),
		("sid", JsonOut.string(at.topic)),
		("url", JsonOut.string(ChatUrl.topic(at).to_str())),
	]).bytes()

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

expect {
	said = Fanout.failure(
		Images,
		{
			member: Str.to_utf8("2"),
			key: Str.to_utf8("ops"),
			sid: Str.to_utf8("Standup"),
			fault: Str.to_utf8("IsDir"),
		},
	)
	said == Str.to_utf8("images for member 2, IsDir, on ops/Standup")
}
expect {
	said = Fanout.failure(
		Code,
		{
			member: Str.to_utf8("12"),
			key: Str.to_utf8("1_12"),
			sid: Str.to_utf8("Plans"),
			fault: Str.to_utf8("NoSpaceLeft"),
		},
	)
	said == Str.to_utf8("code for member 12, NoSpaceLeft, on 1_12/Plans")
}
