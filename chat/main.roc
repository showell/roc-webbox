## THE ROC CHAT: the router (docs/ROC-CHAT.md §3, milestone 1). Every /chat
## and /channel request angry-gopher has comes here, and the Roc answers
## each: it runs the prelude angry-gopher's chat.zig `handle` and
## `handleChannel` ran, parses the path (Route.roc), and serves the route.
##
## The prelude, in Zig's order:
##   1. a static script under /chat (`/<name>.js`) is served to anyone, by
##      any method (`script!`);
##   2. anyone not a member or the agent is sent to sign in, and returned;
##   3. every other request counts as presence, but a stream (by its route:
##      chat.zig read it from the path's spelling, so `.../stream/` counted).
##
## A topic's reactions, react, pin and unpin are the Roc's (docs/ROC-CHAT.md
## C4, `act!`); a reaction is the Roc's whole (its reactor, its bound, its
## stamp, its line and its frame), stored and sent through the primitives
## (Files' `append_line!`, `message_count!`, `publish!`); a message is the
## Roc's too (`append_message!`: its author, number, stamp, block and frame),
## stored through `store_block!` (the append, the count cache, the search
## index), and its fan-out (Fanout.roc: every member's surfaces, their keys,
## events and feed entries) through `publish!`, Files' `append_entry!`, each
## in an aside, and `report_fanout_failure!`, the message's parts its own
## (Fanout.parts_of).
## The files and folders it reads by name (the member's own, a
## conversation's topics, a channel's members, the rosters, a topic's
## reactions) it reads through the file primitives, the names and formats
## its own.
app [handle!] { pf: platform "platform/main.roc" }

import pf.Chat
import pf.Host
import Route
import Reaction
import Pages
import Chrome
import Html
import Paths
import Form
import ZigText
import Uid
import Feeds
import Recent
import ChatState
import Files
import Conversation
import Accounts
import Frame
import Time
import Transcript
import Fanout
import Count
import Last
import Saved
import JsonOut
import Limits
import BusKey
import ChatUrl
import Docs
import Upload
import Search
import Retire
import Members
import Bytes

handle! : Chat.Request => Chat.Answer
handle! = |req|
	if req.area == Retire {
		Retire.answer!({})
	} else {
		# **A PATH IS TEXT AT THE DOOR**: one that is not UTF-8 is the site's
		# 400 for a malformed request, before anything else reads it.
		match Str.from_utf8(req.sub) {
			Ok(sub) => dispatch!(req, sub)
			Err(_) => Chat.malformed
		}
	}

## The request, its path (`sub`) the text handle! checked.
dispatch! : Chat.Request, Str => Chat.Answer
dispatch! = |req, sub|
	match (if req.area == Channel Err(NotAnAsset) else Route.asset(sub)) {
		Ok(name) => script!(name)
		Err(NotAnAsset) =>
			if Host.check_member!({}) == Outsider {
				area = if req.area == Channel "/channel" else "/chat"
				Chat.to_login(List.concat(Str.to_utf8(area), req.sub))
			} else {
				route = if req.area == Channel Route.under_channel(sub) else Route.under_chat(sub)
				act!(req, route)
			}
	}

## **A STATIC SCRIPT, TO ANYONE, BY ANY METHOD** (chat.zig's `serveAsset`,
## as it was): the host's script of the name, which the host answers with
## its bytes, or webbox's plain 404 for a name its table has not. Nobody is
## asked who they are, and no presence is counted.
script! : Str => Chat.Answer
script! = |name|
	match Host.serve_script!(name.to_utf8()) {
		Served => Chat.answered
		Missing => Chat.not_found
	}

## **NOT THE VIEWER'S, OR NOT A CONVERSATION**: a DM's is webbox's plain 404,
## a channel's the page that says why, naming no channel a viewer cannot
## see (one not there and one not theirs read alike).
not_yours! : Route.R => Chat.Answer
not_yours! = |route|
	if route.family == Channel {
		not_found_page!(
			Unasked,
			{ what: "#${route.key} is not a channel you are a member of.", back: "/chat" },
		)
	} else {
		Chat.not_found
	}

## **A 404 THAT SAYS WHY** (metal-vmm QUEUE 156(j)): `what` is not there, and
## `back` is where to go instead.
not_found_page! : Who, { what : Str, back : Str } => Chat.Answer
not_found_page! = |who, { what, back }|
	match Members.load_viewer!(who) {
		Ok(viewer) => Chat.respond(
			404,
			{
				content_type: html,
				body: Pages.not_found(
					Chrome.src_in(Host.list_srcs!({})),
					{
						viewer,
						what,
						back,
					},
				).bytes(),
			},
		)
		Err(Failed) => Chat.answered
	}

## **EVERY ROUTE PAST THE GATE IS THE ROC'S**: presence, then the route's
## own work. A conversation's (metal-vmm QUEUE 271): whose it is, whether its
## topic is there, every 404, each tail's work; the pages and their streams
## (286: the Roc picks the member's bus key, the host holds the stream); the
## docs (278, 289, 290); search's words and messages (281, 282).
act! : Chat.Request, Route.R => Chat.Answer
act! = |req, route| {
	# **THE WELCOME DM ON THE FIRST /chat** (metal-vmm QUEUE 279), before
	# the member is counted online: login seeded it before they ever were.
	who = if route.family == Default welcome!({}) else Unasked
	# A stream is no presence (the Zig's streams were served uncounted).
	if Route.is_stream(route) {} else presence!(who)
	match route.family {
		Default => resume!(who)
		Conversations => if req.method != Get Chat.not_allowed(Get) else serve_conversations!({})
		Msg => redirect_to_msg!(route.rest.to_utf8())
		Links => serve_links!(route.rest.to_utf8())
		Recent =>
			if route.rest == "/stream" {
				member_stream!(req, BusKey.recent)
			} else {
				serve_recent!(route.rest.to_utf8())
			}
		Docs => docs!(req, route.rest)
		Search => search!(req, route.rest)
		Images =>
			if route.rest == "/stream" {
				member_stream!(req, BusKey.images)
			} else {
				serve_feed!(Images, route.rest.to_utf8())
			}
		Code =>
			if route.rest == "/stream" {
				member_stream!(req, BusKey.code)
			} else {
				serve_feed!(Code, route.rest.to_utf8())
			}
		Notifications => member_stream!(req, BusKey.notify)
		SidebarStream => member_stream!(req, BusKey.sidebar)
		NotFound => Chat.not_found
		_ => serve_conversation!(req, route)
	}
}

## **THE MEMBER COUNTED ONLINE** (metal-vmm QUEUE 288): the host marks
## them (the online map lasts the process, so it is the host's); on the
## edge, offline until now, the Roc tells every other member and the
## agent, on their sidebar (the row's dot) and their status strip.
## **BEST-EFFORT, IN AN ASIDE**: a read that fails tells no one and never
## fails the request, and the edge is given back (`presence_unspent!`),
## so a request 30 s on is the edge again.
presence! : Who => {}
presence! = |who|
	match Host.count_presence!({}) {
		Steady => {}
		CameOnline => {
			_ = Host.mark_aside!(Begin)
			told = came_online!(who)
			match (Host.mark_aside!(End).status, told) {
				(Done, Ok({})) => {}
				_ => Host.presence_unspent!({})
			}
		}
	}

## The came-online fan-out (the Zig's, gone): the member's name, then
## every authorized account but theirs (listAuthorized: one that will not
## read fails it), each told on its sidebar, then its status strip, with
## a link to its DM with the member.
came_online! : Who => Try({}, [Failed])
came_online! = |who| {
	me = Members.load_uid!({})?
	all = Members.load_accounts!(who)?
	name = Members.fail_if_unreadable!(Accounts.name(all, me))?
	roster = Members.fail_if_unreadable!(Accounts.authorized(all))?
	online = JsonOut.object([
		("kind", JsonOut.string("user-online")),
		("user_id", JsonOut.string(me.to_str())),
		("user_name", JsonOut.string(name)),
	]).bytes()
	List.for_each!(
		List.drop_if(roster, |u| u.id == me),
		|u| {
			Host.publish!(BusKey.sidebar(u.id).bytes(), online)
			link = ChatUrl.conv(Dm(Paths.pair_key(u.id, me))).to_str()
			strip = JsonOut.object([
				("text", JsonOut.string("${name} has come online.")),
				("link_url", JsonOut.string(link)),
			])
			Host.publish!(BusKey.notify(u.id).bytes(), strip.bytes())
		},
	)
	Ok({})
}

## **THE MEMBER'S DOCS** (docs.zig `handle`, metal-vmm QUEUE 289, 290):
## posting one to chat, the writes (a new doc, a save, a message saved to
## the reading list), the live preview, then the read pages.
docs! : Chat.Request, Str => Chat.Answer
docs! = |req, rest| if rest == "/post" post_doc!(req) else Docs.docs!(req, rest)

## **A MEMBER'S OWN STREAM** (metal-vmm QUEUE 286): their feed, their
## notifications or their sidebar, on the bus key `key` makes of their uid,
## live only (the page is the backlog). A GET's, as every stream is.
member_stream! : Chat.Request, (Uid -> BusKey) => Chat.Answer
member_stream! = |req, key|
	if req.method != Get {
		Chat.not_allowed(Get)
	} else {
		match Members.load_uid!({}) {
			Ok(me) => Chat.stream(key(me).bytes())
			Err(Failed) => Chat.answered
		}
	}

## A DM's or a channel's, in the Zig's order: a new topic and a send look
## their conversation up themselves (a send makes its topic); the landing
## needs no topic; everything else needs the topic there (a miss is Zig's
## to answer, the same 404s), then the method, then the work.
serve_conversation! : Chat.Request, Route.R => Chat.Answer
serve_conversation! = |req, route|
	match conv_key(route) {
		# **A KEY THAT NAMES NO CONVERSATION IS A 404**: no pair
		# (Paths.participant's rule), no valid name.
		Err(Invalid) => not_yours!(route)
		Ok(key) =>
			if route.part == New {
				create_topic!(req, { route, key })
			} else if route.tail == Send or route.tail == InvalidSend {
				send!(req, { route, key })
			} else if route.part == Landing {
				serve_landing!(route, key)
			} else {
				match find!(key) {
					Err(NotYours) => not_yours!(route)
					Err(Failed) => Chat.answered
					Ok((conv, who)) =>
						if route.part == Invalid {
							Chat.not_found
						} else {
							# The title before the topics, as findTopic read them: a
							# partner whose name will not read fails every topic route.
							match load_title!(key, who) {
								Err(Failed) => Chat.answered
								Ok(t) => {
									topics = load_topics!(key)
									if Conversation.has_topic(topics, route.topic) {
										serve_topic!(
											req,
											{
												route,
												found: {
													key,
													conv,
													who,
													title: Conversation.topic_title(t, route.topic),
													topics,
												},
											},
										)
									} else {
										# **A TOPIC THAT IS NOT THERE IS A 404 THAT SAYS SO**
										# (metal-vmm QUEUE 156(j)).
										not_found_page!(
											who,
											{
												what: "There is no topic \u(201C)${route.topic}\u(201D) in this conversation.",
												back: key.base(),
											},
										)
									}
								}
							}
						}
				}
			}
	}

## **THE CONVERSATION'S KEY, BUILT ONCE, WHERE THE REQUEST COMES IN**: the
## route's key as a DM's pair key (Paths.pair_key_from_str) or a channel's
## name (Paths.channel_name_from_str); every path past here is built from
## it.
conv_key : Route.R -> Try(Paths.ConvKey, [Invalid])
conv_key = |route|
	match route.family {
		Dm => Paths.pair_key_from_str(route.key).map_ok(|pair| Dm(pair))
		Channel => Paths.channel_name_from_str(route.key).map_ok(|name| Channel(name))
		_ => Err(Invalid)
	}

## A topic found: its conversation, the accounts as far as they were asked,
## its title, and the conversation's topics as they were listed to find it.
AtTopic : {
	key : Paths.ConvKey,
	conv : Chat.Conv,
	who : Who,
	title : Str,
	topics : List(Str),
}

## **THE IDS SAVED FROM THIS TOPIC** (GET <topic>/saved, metal-vmm QUEUE
## 273): the member's reading list read and its refs here taken
## (Saved.ids), as a JSON array, for the page to mark its bubbles. No list
## is nothing saved. Read whole each time: no cache.
serve_saved! : Route.R => Chat.Answer
serve_saved! = |route|
	match Members.load_uid!({}) {
		Err(Failed) => Chat.answered
		Ok(me) =>
			match Files.read_bytes!(Paths.reading_list_path(me)) {
				Ok(text) => {
					ids = Saved.ids(
						text,
						{ conv: route.key.to_utf8(), topic: route.topic.to_utf8() },
					)
					# An id is ASCII by its rule (Paths.is_valid_msg_ref_id).
					Chat.respond(
						200,
						{
							content_type: json,
							body: JsonOut.array(
								List.map(
									ids,
									|id| JsonOut.string(Str.from_utf8_lossy(id)),
								),
							).bytes(),
						},
					)
				}
				Err(Missing) => Chat.respond(200, { content_type: json, body: Str.to_utf8("[]") })
				Err(Failed) => Chat.answered
			}
	}

## A topic's page, or its raw transcript: a read, then the work.
serve_page_or_raw! : Chat.Request, { route : Route.R, found : AtTopic } => Chat.Answer
serve_page_or_raw! = |req, { route, found }|
	if req.method != Get and req.method != Head {
		Chat.not_allowed(Get)
	} else if route.tail == Page {
		serve_topic_page!(route, found)
	} else {
		match Files.serve_file!(Paths.transcript_path({ key: found.key, topic: route.topic })) {
			Serving => Chat.served_plain
			NotServing => Chat.not_found
		}
	}

## **A TOPIC'S BUNDLE** (chat_download `serveBundle`, metal-vmm QUEUE 291):
## its transcript, its reactions when anyone reacted, and every upload (a
## folder in the uploads passed over), named under the topic, then served
## as `<topic>.tar.gz`. A topic with no transcript is a 404; anything else
## that will not read fails the download: the whole topic or nothing.
serve_download! : Chat.Request, { route : Route.R, found : AtTopic } => Chat.Answer
serve_download! = |req, { route, found }|
	if req.method != Get and req.method != Head {
		Chat.not_allowed(Get)
	} else {
		at = { key: found.key, topic: route.topic }
		sid = route.topic
		md = Paths.transcript_path(at)
		match Files.read_stat!(md) {
			Err(Missing) => Chat.not_found
			Err(Failed) => Chat.answered
			Ok(_) =>
				match bundle_files!(at, md) {
					Err(Failed) => Chat.answered
					Ok(files) =>
						match add_all!(files) {
							Err(Failed) => Chat.answered
							Ok({}) => {
								Host.serve_bundle!(sid.to_utf8())
								Chat.answered
							}
						}
				}
		}
	}

## The bundle's files, each with its name in the tar: the transcript,
## the reactions when there, then the uploads by name.
bundle_files! : Paths.TopicAt,
Paths.ChatPath => Try(
	List({ name : Str, path : Paths.ChatPath }),
	[Failed],
)
bundle_files! = |at, md| {
	sid = at.topic
	reactions = Paths.reactions_path(at)
	with_reactions = match Files.read_stat!(reactions) {
		Ok(_) => Ok([{ name: "${sid}/${sid}.reactions.jsonl", path: reactions }])
		Err(Missing) => Ok([])
		Err(Failed) => Err(Failed)
	}
	uploads = match Files.list!(Paths.uploads_folder(at)) {
		Ok(listed) =>
			Ok(
				# **BY NAME, NOT THE DISK'S ORDER**: a folder's order is its
				# filesystem's, and the tar must not be.
				Paths.sort_by_bytes(
					List.map(
						List.keep_if(listed.entries, |e| e.kind != Dir),
						|e| e.name,
					),
				)
					|> List.map(
						|name| {
							name: "${sid}/uploads/${name}",
							path: Paths.upload_path(at, name),
						},
					),
			)
		Err(Missing) => Ok([])
		Err(Failed) => Err(Failed)
	}
	match (with_reactions, uploads) {
		(Ok(rx), Ok(ups)) => Ok(
			List.join([
				[{ name: "${sid}/${sid}.md", path: md }],
				rx,
				ups,
			]),
		)
		_ => Err(Failed)
	}
}

## Each file added to the host's bundle, in turn; the first that will not
## read fails it.
add_all! : List({ name : Str, path : Paths.ChatPath }) => Try({}, [Failed])
add_all! = |files|
	match files {
		[] => Ok({})
		[f, .. as more] =>
			match Files.bundle_add!(f.name.to_utf8(), f.path) {
				Ok({}) => add_all!(more)
				Err(Failed) => Err(Failed)
			}
	}

## A topic that is there: the method, then the work.
serve_topic! : Chat.Request, { route : Route.R, found : AtTopic } => Chat.Answer
serve_topic! = |req, { route, found }| {
	who = found.who
	match route.tail {
		# An upload and the bundle (metal-vmm QUEUE 291): the Roc decides,
		# the host serves the bytes.
		Uploads => Upload.serve!(
			req,
			{ at: { key: found.key, topic: route.topic }, file: route.rest },
		)
		Download => serve_download!(req, { route, found })
		Upload => Upload.post!(req, { key: found.key, topic: route.topic })
		# The topic's stream (metal-vmm QUEUE 286): its key and transcript
		# the Roc's, the backlog's replay and the live stream the host's.
		Stream =>
			if req.method != Get {
				Chat.not_allowed(Get)
			} else {
				at = { key: found.key, topic: route.topic }
				Chat.topic_stream(
					BusKey.topic(at).bytes(),
					{ transcript: Paths.transcript_path(at).bytes(), topic: route.topic.to_utf8() },
				)
			}
		Saved =>
			if req.method != Get and req.method != Head {
				Chat.not_allowed(Get)
			} else {
				serve_saved!(route)
			}
		Invalid => Chat.not_found
		Page | Raw => serve_page_or_raw!(req, { route, found })
		Reactions =>
			if req.method != Get {
				Chat.not_allowed(Get)
			} else {
				# readReactions's: none yet is no events; bytes as stored (QUEUE 267).
				ndjson = Str.to_utf8("application/x-ndjson; charset=utf-8")
				match Files.read_bytes!(
					Paths.reactions_path({
						key: found.key,
						topic: route.topic,
					}),
				) {
					Ok(bytes) => Chat.respond(200, { content_type: ndjson, body: bytes })
					Err(Missing) => Chat.respond(200, { content_type: ndjson, body: [] })
					Err(Failed) => Chat.answered
				}
			}
		_ =>
			if req.method != Post {
				Chat.not_allowed(Post)
			} else if route.tail == React {
				react!(who, { key: found.key, topic: route.topic })
			} else {
				match pin!(
					found.key,
					{ topic: route.topic, pin: if route.tail == Pin Pin else Unpin },
				) {
					Ok({}) => Chat.respond(204, { content_type: [], body: [] })
					Err(Failed) => Chat.answered
				}
			}
	}
}

## **THE CONVERSATION A DM OR CHANNEL ROUTE NAMES, IF IT IS THE MEMBER'S**
## (angry-gopher chat.zig `findConv`): a DM whose pair holds the member
## and whose other half is an account; a channel that lists the member.
## `NotYours` for every 404 the Zig answers (the route handed back to it,
## whose page says why); `Failed` when a read failed (the request has).
## A DM's accounts come back `Known`, for what looks one up next; a
## channel's are not asked.
find! : Paths.ConvKey => Try((Chat.Conv, Who), [NotYours, Failed])
find! = |key| {
	bytes = key.bytes()
	me = Members.load_uid!({})?
	match key {
		Dm(pair) =>
			match Conversation.dm_other(pair, me) {
				Ok(other) =>
					match Members.load_accounts!(Unasked) {
						Ok(all) =>
							if Accounts.has_account(all, other) {
								Ok((
									{
										family: Dm,
										key: bytes,
										base: Conversation.dm_base(bytes),
										members: Conversation.dm_members(bytes),
									},
									Known(all),
								))
							} else {
								Err(NotYours)
							}
						Err(Failed) => Err(Failed)
					}
				Err(NotAParticipant) => Err(NotYours)
			}
		Channel(name) => {
			members = load_channel_members!(name)?
			if List.contains(members, me) {
				Ok((
					{
						family: Channel,
						key: bytes,
						base: Conversation.channel_base(bytes),
						members: List.map(members, |u| u.to_str().to_utf8()),
					},
					Unasked,
				))
			} else {
				Err(NotYours)
			}
		}
	}
}

## Who is asking, and the accounts once asked (Members.roc).
Who : Members.Who

## Channel `name`'s members, as its member file lists them (Paths's
## parse); none when there is no such channel. **A MALFORMED ONE FAILS THE
## REQUEST** on its own route (channelMembers's error.MalformedChannel), never
## the 404 of a channel that is not the member's; a read that failed has
## failed it already.
load_channel_members! : Paths.ChannelName => Try(List(Uid), [Failed])
load_channel_members! = |name|
	match Files.read!(Paths.channel_path(name)) {
		Ok(text) =>
			match Paths.channel_members(text) {
				Ok(members) => Ok(members)
				Err(Malformed) => {
					Host.fail!(MalformedChannel, name.bytes())
					Err(Failed)
				}
			}
		# No member file is no channel: nobody's.
		Err(Missing) => Ok([])
		Err(Failed) => Err(Failed)
	}

## **EVERY CHANNEL'S ROSTER** (channelRosters): channels/ listed
## (Paths.channel_names), then each member file read and judged in the
## listing's order (Paths.roster), a malformed one counted as it is met
## (Host.count_malformed_channel!), as the Zig counted it, before any read after
## it can fail. `Failed` when the listing or a member file would not read
## (the request has failed with its error): **NEVER THE ROSTERS THAT READ
## BEFORE IT**, which would leave the rest out.
load_channel_rosters! : {} => Try(List(Paths.Roster), [Failed])
load_channel_rosters! = |{}| {
	match Files.list!(Paths.channels_folder) {
		Ok(listed) => {
			# A channel whose name is not UTF-8 is skipped, and counted as a
			# malformed one is.
			List.for_each!(
				Paths.channel_names_not_utf8(listed.not_utf8),
				|name| Host.count_malformed_channel!(name),
			)
			load_rosters_from!(Paths.channel_names(listed.entries), { at: 0, out: [] })
		}
		Err(Missing) => Ok([])
		Err(Failed) => Err(Failed)
	}
}

load_rosters_from! : List(Str),
{
	at : U64,
	out : List(Paths.Roster),
} => Try(List(Paths.Roster), [Failed])
load_rosters_from! = |names, { at: i, out }|
	match List.get(names, i) {
		Err(_) => Ok(out)
		Ok(name) =>
			match Paths.channel_name_from_str(name) {
				Ok(valid) => {
					# A member file that is not UTF-8 is malformed: skipped and
					# counted, never every member's chat down (QUEUE 267).
					part = match Files.read_text!(Paths.channel_path(valid)) {
						Ok(text) => Paths.roster(name, Ok(text))
						Err(Missing) => Paths.roster(name, Err(Missing))
						Err(Failed) => Paths.roster(name, Err(Failed))
						Err(NotUtf8) => Malformed
					}
					match part {
						Listed(r) => load_rosters_from!(
							names,
							{ at: i + 1, out: List.append(out, r) },
						)
						Malformed => {
							Host.count_malformed_channel!(name.to_utf8())
							load_rosters_from!(names, { at: i + 1, out })
						}
						Gone => load_rosters_from!(names, { at: i + 1, out })
						Failed => Err(Failed)
					}
				}
				Err(Invalid) => {
					Host.count_malformed_channel!(name.to_utf8())
					load_rosters_from!(names, { at: i + 1, out })
				}
			}
	}

## **A CONVERSATION'S TOPICS** (listTopics): its sessions folder listed,
## the choice Paths.topics's.
load_topics! : Paths.ConvKey => List(Str)
load_topics! = |key| Paths.topics(list!(Paths.topics_folder(key)))

## Files.list!'s entries. **NOTHING THERE HOLDS NOTHING** (webbox's
## store.list); a listing that failed has failed the request, and answers
## nothing too, so what follows writes nothing (the host does nothing more).
## A name that is not UTF-8 is no topic, and no counter is kept of it.
list! : Paths.ChatPath => List(Paths.Entry)
list! = |path|
	match Files.list!(path) {
		Ok(listed) => listed.entries
		Err(Missing) | Err(Failed) => []
	}

## `conv`'s title (convTitle): a DM's partner's name (its accounts known
## since find!), a channel's own. `Failed` when the partner's name would not
## read (the request has failed with its error).
load_title! : Paths.ConvKey, Who => Try(Str, [Failed])
load_title! = |key, who|
	match key {
		Dm(pair) =>
			match Members.load_accounts!(who) {
				Ok(all) => {
					other = pair.partner(Members.load_uid!({})?)
					match Members.fail_if_unreadable!(Accounts.name(all, other)) {
						Ok(name) => Ok(Conversation.dm_title(name, other))
						Err(Failed) => Err(Failed)
					}
				}
				Err(Failed) => Err(Failed)
			}
		Channel(name) => Ok(Conversation.channel_title(name))
	}

## POST .../pin and .../unpin: the member's pins in the conversation read,
## `topic` pinned or unpinned (ChatState.pinned), and the file written back or,
## emptied, removed. A read that failed stops here: the set is not empty, it
## is unknown, and writing it would drop every pin. `Failed` when a step failed.
pin! : Paths.ConvKey, { topic : Str, pin : ChatState.PinEdit } => Try({}, [Failed])
pin! = |key, { topic, pin }| {
	path = Paths.pinned_path(Members.load_uid!({})?, key)
	match Files.read!(path) {
		Ok(stored) => write_pins!(
			path,
			{
				stored,
				topic,
				pin,
			},
		)
		Err(Missing) => write_pins!(
			path,
			{
				stored: "",
				topic,
				pin,
			},
		)
		Err(Failed) => Err(Failed)
	}
}

## The pinned file at `path`, read as `stored`, with `topic` pinned or
## unpinned: written back, or, emptied, removed.
write_pins! : Paths.ChatPath,
{
	stored : Str,
	topic : Str,
	pin : ChatState.PinEdit,
} => Try({}, [Failed])
write_pins! = |
	path,
	{
		stored,
		topic,
		pin,
	},
|
	match ChatState.pinned(stored, { topic, pin }) {
		Write(bytes) => Files.write!(path, bytes)
		Remove => Files.remove!(path)
	}

## **WHERE THE MEMBER RESUMES DM `conv`: TOPIC `topic`** (setLastViewedTopic):
## the topic last viewed there first, then the DM last in, each written
## only when it changed (ChatState.is_changed); `Failed` when a step failed,
## and nothing after it is written. A topic with no name records nothing.
bookmark! : Paths.ConvKey, Str => Try({}, [Failed])
bookmark! = |key, topic| {
	me = Members.load_uid!({})?
	if topic.is_empty() {
		Ok({})
	} else {
		write_if_changed!(Paths.last_session_path(me, key), topic)?
		write_if_changed!(Paths.last_conv_path(me), key.to_str())
	}
}

## **WRITTEN ONLY WHEN IT CHANGES** (zig-metal-unikernel 153(1)): on every
## send and view the value is usually the one already there, and a write is
## disk requests each time.
write_if_changed! : Paths.ChatPath, Str => Try({}, [Failed])
write_if_changed! = |path, value|
	if ChatState.is_changed(Files.read!(path), value) Files.write!(
		path,
		ChatState.bookmark_line(value),
	) else Ok({})

## POST .../react: the form, then the reaction stored and sent live.
react! : Who, Paths.TopicAt => Chat.Answer
react! = |who, at| {
	body = Host.read_body!(Reaction)
	if body.status == Answered {
		Chat.answered
	} else {
		match Reaction.form(body.bytes) {
			Malformed => Chat.malformed
			Bad(why) => Chat.respond(400, { content_type: [], body: why })
			Reacted(r) =>
				match store_reaction!(
					who,
					at,
					r,
				) {
					Stored => Chat.respond(204, { content_type: [], body: [] })
					NoSuchMessage => Chat.respond(
						400,
						{ content_type: [], body: Str.to_utf8("react: no such message\n") },
					)
					Failed => Chat.answered
				}
		}
	}
}

## **A REACTION STORED, THEN SENT LIVE** (storeReaction, appendReaction):
## the reactor's own name (getUserName, from the accounts), the message
## judged against the topic's count, the line stamped with the request's
## time, then its sidecar line appended and its frame published on the
## topic's key. `Failed` when a step failed (the request has, with its
## error), and nothing after it is done.
store_reaction! : Who,
Paths.TopicAt,
{
	msg : U64,
	emoji : Str,
	change : Reaction.Change,
} => [
	Stored,
	NoSuchMessage,
	Failed,
]
store_reaction! = |
	who,
	topic_at,
	r,
|
	match (Members.load_viewer!(who), Members.load_uid!({})) {
		(Ok(name), Ok(uid)) => {
			match Last.messages!(topic_at) {
				Err(Failed) => Failed
				Ok(count) =>
				# Message numbers start at 1 (the N of MSG_<topic>_N).
					if r.msg == 0 or r.msg > count {
						NoSuchMessage
					} else {
						at = Time.rfc3339(Host.read_time!({}))
						line = Reaction.line({
							msg: r.msg,
							uid,
							from: name,
							emoji: r.emoji,
							change: r.change,
							at,
						})
						# **THE ECHO IS MADE BEFORE THE STORE** (metal-vmm QUEUE
						# 177.1), as a message's: its key and frame, so nothing
						# can fail between the append and the publish.
						key = BusKey.topic(topic_at)
						frame = Frame.reaction(line)
						match Files.append_line!(Paths.reactions_path(topic_at), line) {
							Ok({}) => {
								# **STORED IS DONE**: the live publish cannot fail.
								Host.publish!(key.bytes(), frame)
								Stored
							}
							Err(Failed) => Failed
						}
					}
			}
		}
		_ => Failed
	}

html : List(U8)
html = Chat.html

## /chat/links, by any method, as the Zig had it: the member's own, or the
## stub; nothing below it.
serve_links! : List(U8) => Chat.Answer
serve_links! = |rest|
	if rest != [] {
		Chat.not_found
	} else {
		match (Members.load_viewer!(Unasked), Members.load_uid!({})) {
			(Err(Failed), _) | (Ok(_), Err(Failed)) => Chat.answered
			(Ok(viewer), Ok(me)) => {
				src = Chrome.src_in(Host.list_srcs!({}))
				match Files.serve_rendered!(Paths.links_path(me)) {
					Serving => {
						(before, after) = Pages.links_around(src, viewer)
						Chat.served_html(before, after)
					}
					NotServing => Chat.respond(
						200,
						{
							content_type: html,
							body: Pages.links(src, { viewer, rendered: NoLinks }).bytes(),
						},
					)
				}
			}
		}
	}

## /chat/recent by any method, as the Zig had it: its rows gathered,
## named, dated, excerpted and ordered here; nothing below it but its stream.
serve_recent! : List(U8) => Chat.Answer
serve_recent! = |rest|
	if rest != [] {
		Chat.not_found
	} else {
		match load_recent!({}) {
			Ok(
				(
					me,
					viewer,
					written,
				),
			) => {
				# **ONE DAMAGED ROW IS ITS OWN** (QUEUE 267): a row whose
				# text is not UTF-8 (a torn last block) is left out and
				# counted, and the page served with the rest.
				got = Recent.rows_of(written)
				List.for_each!(got.damaged, |key| Host.count_dropped!(RecentRow, key))
				Chat.respond(
					200,
					{
						content_type: html,
						body: Pages.recent(
							Chrome.src_in(Host.list_srcs!({})),
							{ viewer, json: Recent.json(me, got.rows) },
						).bytes(),
					},
				)
			}
			Err(Failed) => Chat.answered
		}
	}

## The member, their name, and the rows of their feed (recent.zig's
## `gatherRows`, metal-vmm QUEUE 277), read in the Zig's order: the viewer's
## name; a DM with every other authorized member (listAuthorized), then the
## member's channels (listUserChannels), each topic's last message; then
## their docs. `Failed` when a read failed (the request has, with its error).
## **ONE DAMAGED ROW IS ITS OWN** (QUEUE 267): a DM whose partner's name,
## or a row whose author's, will not read is left out and counted.
load_recent! : {} => Try(
	(
		Uid,
		Str,
		List(Recent.Written),
	),
	[Failed],
)
load_recent! = |{}| {
	me = Members.load_uid!({})?
	accounts = Members.load_accounts!(Unasked)?
	viewer = Members.fail_if_unreadable!(Accounts.name(accounts, me))?
	roster = Members.fail_if_unreadable!(Accounts.roster_named(accounts))?
	dms = List.keep_if(roster, |u| u.id != me)
		|> List.map(
			|u| {
				key: Dm(Paths.pair_key(me, u.id)),
				label: u.name.map_ok(|name| "to ${name}"),
			},
		)
	from_dms = gather_convs!(
		me,
		accounts,
		dms,
		[],
	)?
	rosters = load_channel_rosters!({})?
	channels = List.keep_oks(
		Paths.member_channels(rosters, me),
		|name| Paths.channel_name_from_str(name).map_ok(
			|valid| {
				key: Channel(valid),
				label: Ok("in ${name}"),
			},
		),
	)
	from_channels = gather_convs!(
		me,
		accounts,
		channels,
		from_dms,
	)?
	docs = gather_docs!(
		me,
		Paths.docs(me, list!(Paths.docs_folder(me))),
		[],
	)?
	Ok((
		me,
		viewer,
		List.concat(from_channels, docs),
	))
}

## What a conversation's rows are labelled: "to <partner>" or "in <channel>".
Labelled : { key : Paths.ConvKey, label : Try(Str, [Unreadable]) }

## A row for each topic of each conversation, after `out`.
gather_convs! : Uid,
List(Accounts.Account),
List(Labelled),
List(Recent.Written) => Try(
	List(Recent.Written),
	[Failed],
)
gather_convs! = |
	me,
	accounts,
	convs,
	out,
|
	match convs {
		[] => Ok(out)
		[conv, .. as more] => {
			topics = load_topics!(conv.key)
			rows =
				match conv.label {
					Ok(label) => gather_topics!(
						me,
						accounts,
						{ key: conv.key, label },
						topics,
						out,
					)?
					Err(Unreadable) => {
						List.for_each!(
							topics,
							|topic| Host.count_dropped!(
								RecentRow,
								Str.to_utf8("${conv.key.base()}/${topic}"),
							),
						)
						out
					}
				}
			gather_convs!(
				me,
				accounts,
				more,
				rows,
			)
		}
	}

## gatherConvTopics: each topic's last message, when it was sent and by
## whom. **A TOPIC NOBODY HAS WRITTEN TO STILL BELONGS ON THE PAGE**, and
## one whose last date will not read (a transcript another writer made) is
## dated by its file too: at the epoch it would be buried, and its empty
## date would show as "NaNd".
gather_topics! : Uid,
List(Accounts.Account),
{
	key : Paths.ConvKey,
	label : Str,
},
List(Str),
List(Recent.Written) => Try(List(Recent.Written), [Failed])
gather_topics! = |
	me,
	accounts,
	conv,
	topics,
	out,
|
	match topics {
		[] => Ok(out)
		[topic, .. as more] => {
			at = { key: conv.key, topic }
			row = {
				..no_row,
				key: Str.to_utf8("${conv.key.base()}/${topic}"),
				label: conv.label.to_utf8(),
				topic: topic.to_utf8(),
				dm: conv.key.kind(),
			}
			rows =
				match Last.read_message!(at, accounts)? {
					Some(last) =>
						match (
							Time.unix_from_rfc3339(last.at),
							author_name(me, { accounts, uid: last.uid }),
						) {
							(Ok(secs), Ok(name)) => Ok([
								{
									..row,
									secs: secs_text(secs),
									uid: last.uid,
									name: name.to_utf8(),
									markdown: last.markdown,
								},
							])
							(Ok(_), Err(Unreadable)) => {
								Host.count_dropped!(RecentRow, row.key)
								Ok([])
							}
							(Err(NotADate), _) => by_file_time!(Paths.transcript_path(at), row)
						}
					None => by_file_time!(Paths.transcript_path(at), row)
				}?
			gather_topics!(
				me,
				accounts,
				conv,
				more,
				List.concat(out, rows),
			)
		}
	}

## The member's docs, each dated by its file; one gone since its folder
## was listed is left out.
gather_docs! : Uid,
List(
	{
		slug : Str,
		path : Paths.ChatPath,
	},
),
List(Recent.Written) => Try(List(Recent.Written), [Failed])
gather_docs! = |
	me,
	docs,
	out,
|
	match docs {
		[] => Ok(out)
		[doc, .. as more] => {
			row = {
				..no_row,
				kind: Doc,
				uid: me.to_str().to_utf8(),
				key: doc.slug.to_utf8(),
				label: Docs.title(doc.slug).to_utf8(),
			}
			rows = by_file_time!(doc.path, row)?
			gather_docs!(
				me,
				more,
				List.concat(out, rows),
			)
		}
	}

## byFileTime: `row` dated by `path`'s modification time, **IN EVEN
## SECONDS, AS FAT KEEPS IT** (recent.zig `fileSeconds`: every host floors
## it, so the two show the same data alike); no row for a file not there.
by_file_time! : Paths.ChatPath, Recent.Written => Try(List(Recent.Written), [Failed])
by_file_time! = |path, row|
	match Files.read_stat!(path) {
		Ok(st) => Ok([{ ..row, secs: secs_text(if st.mtime % 2 == 0 st.mtime else st.mtime - 1) }])
		Err(Missing) => Ok([])
		Err(Failed) => Err(Failed)
	}

## authorName: the last author's name, read only for someone other than the
## viewer ("" for the viewer, whom the page calls "You", and for nobody:
## an empty Who cell, never an older author). An id that is no uid names
## no account, so no name.
author_name : Uid, { accounts : List(Accounts.Account), uid : List(U8) } -> Try(Str, [Unreadable])
author_name = |me, { accounts, uid }|
	match Uid.from_utf8(uid) {
		Ok(id) if id != me => Accounts.name(accounts, id).map_err(|_| Unreadable)
		_ => Ok("")
	}

no_row : Recent.Written
no_row = {
	kind: Message,
	secs: [],
	uid: [],
	name: [],
	key: [],
	label: [],
	topic: [],
	markdown: [],
	dm: Channel,
}

## A row's time as Recent.Written carries it: a signed decimal.
secs_text : I64 -> List(U8)
secs_text = |secs| I64.to_str(secs).to_utf8()

## /chat/images (the newest 20 entries) or /chat/code (every one), by any
## method, as the Zig had them; nothing below them but their streams.
serve_feed! : [Images, Code], List(U8) => Chat.Answer
serve_feed! = |which, rest|
	if rest != [] {
		Chat.not_found
	} else {
		match (Members.load_viewer!(Unasked), Members.load_uid!({})) {
			(Err(Failed), _) | (Ok(_), Err(Failed)) => Chat.answered
			(Ok(viewer), Ok(me)) => {
				# A feed that failed is the request's failure; the page made
				# of nothing is not sent.
				# **ONE DAMAGED ENTRY IS ITS OWN** (QUEUE 267): an entry
				# whose bytes are not UTF-8 is skipped and counted.
				path = Paths.feed_path(me, which)
				file = match Files.read_bytes!(path) {
					Ok(bytes) => bytes
					Err(Missing) | Err(Failed) => []
				}
				src = Chrome.src_in(Host.list_srcs!({}))
				(page, damaged) = match which {
					Images => {
						got = Feeds.images_of(file)
						(
							Pages.images(src, { viewer, json: Feeds.images_json(got.entries, 20) }),
							got.damaged,
						)
					}
					Code => {
						got = Feeds.code_of(file)
						(
							Pages.code(src, { viewer, json: Feeds.code_json(got.entries) }),
							got.damaged,
						)
					}
				}
				if damaged > 0 Host.count_dropped!(FeedEntry, path.bytes()) else {}
				Chat.respond(200, { content_type: html, body: page.bytes() })
			}
		}
	}

## A conversation's landing: its first topic, or, with none, the page that
## offers one, the title and viewer read in the Zig's order.
serve_landing! : Route.R, Paths.ConvKey => Chat.Answer
serve_landing! = |route, key|
	match find!(key) {
		Err(NotYours) => not_yours!(route)
		Err(Failed) => Chat.answered
		Ok((conv, who)) => {
			first = Paths.first_of(load_topics!(key))
			if !first.is_empty() {
				Chat.redirect(
					List.join([
						conv.base,
						['/'],
						first.to_utf8(),
					]),
				)
			} else {
				match load_title!(key, who) {
					Err(Failed) => Chat.answered
					Ok(title) =>
						match Members.load_viewer!(who) {
							Ok(viewer) => Chat.respond(
								200,
								{
									content_type: html,
									body: Pages.no_topics(
										Chrome.src_in(Host.list_srcs!({})),
										{
											viewer,
											base: key.base(),
											title,
										},
									).bytes(),
								},
							)
							Err(Failed) => Chat.answered
						}
				}
			}
		}
	}

## A topic's page (angry-gopher chat_page.zig `conversationPage`): a DM's
## topic recorded as where the member resumes it first (a bookmark that
## fails serves no page), then the viewer and the sidebar (`load_sidebar!`), and
## the limits the server enforces (Limits).
serve_topic_page! : Route.R, AtTopic => Chat.Answer
serve_topic_page! = |route, at|
	if at.conv.family == Dm and bookmark!(at.key, route.topic).is_err() {
		Chat.answered
	} else {
		match load_sidebar!(route.topic, at) {
			Err(Failed) => Chat.answered
			Ok((viewer, sb)) => {
				view = {
					key: route.key,
					base: at.key.base(),
					topic: route.topic,
					title: at.title,
					uid: sb.uid,
					viewer,
					sidebar_json: Pages.sidebar_json(sb),
				}
				Chat.respond(
					200,
					{
						content_type: html,
						body: Pages.conversation(
							Chrome.src_in(Host.list_srcs!({})),
							{ limits: Limits.page, v: view },
						).bytes(),
					},
				)
			}
		}
	}

## **THE VIEWER AND THE SIDEBAR, READ IN THE ZIG'S ORDER** (conversationPage's
## getUserName, then sidebarOf): the viewer's name; every other authorized
## member (listAuthorized: an account it reads that will not read fails
## it), each online or not at the request's time (Host.check_online!, one asking
## for all); the member's channels (listUserChannels: a malformed one
## skipped and counted); their pins in this conversation (pinnedTopics,
## sorted); its topics as they were listed to find `topic`. `Failed`
## when a read failed (the request has, with its error): **A PINS FILE
## THAT WILL NOT READ IS NEVER NO PINS.**
load_sidebar! : Str, AtTopic => Try((Str, Pages.Sidebar), [Failed])
load_sidebar! = |topic, at| {
	uid = Members.load_uid!({})?
	match Members.load_accounts!(at.who) {
		Err(Failed) => Err(Failed)
		Ok(all) =>
			match Members.fail_if_unreadable!(Accounts.name(all, uid)) {
				Err(Failed) => Err(Failed)
				Ok(viewer) =>
					match Members.fail_if_unreadable!(Accounts.authorized(all)) {
						Err(Failed) => Err(Failed)
						Ok(roster) => {
							others = List.drop_if(roster, |u| u.id == uid)
							flags = Host.check_online!(
								List.map(
									others,
									|u| u.id.to_str().to_utf8(),
								),
							)
							match load_channel_rosters!({}) {
								Err(Failed) => Err(Failed)
								Ok(rosters) =>
									match Files.read!(Paths.pinned_path(uid, at.key)) {
										Err(Failed) => Err(Failed)
										Ok(stored) => Ok((
											viewer,
											sidebar_of(
												uid,
												topic,
												at,
												with_online(others, flags),
												Paths.member_channels(rosters, uid),
												ChatState.pins(stored),
											),
										))
										Err(Missing) => Ok((
											viewer,
											sidebar_of(
												uid,
												topic,
												at,
												with_online(others, flags),
												Paths.member_channels(rosters, uid),
												[],
											),
										))
									}
							}
						}
					}
			}
	}
}

## The other members, each beside its own flag (Host.check_online! answers one
## per id, in their order).
with_online : List({ id : Uid, name : Str }),
List([Offline, Online]) -> List(
	{
		id : Uid,
		name : Str,
		presence : [Online, Offline],
	},
)
with_online = |others, flags|
	List.map_with_index(
		others,
		|u, i|
			{
				id: u.id,
				name: u.name,
				presence: if List.get(flags, i) == Ok(Online) Online else Offline,
			},
	)

sidebar_of : Uid,
Str,
AtTopic,
List(
	{
		id : Uid,
		name : Str,
		presence : [Online, Offline],
	},
),
List(Str),
List(Str) -> Pages.Sidebar
sidebar_of = |
	me,
	topic,
	at,
	others,
	channels,
	pins,
|
	{
		uid: me,
		kind: if at.conv.family == Dm Dm else Channel,
		key: at.key.to_str(),
		base: at.key.base(),
		topic,
		others,
		channels,
		pins,
		topics: at.topics,
	}

json : List(U8)
json = Chat.json

## **THE HOST'S WELCOME** (login.zig `sendHostWelcome` as it was, metal-vmm
## QUEUE 279), **FOR A MEMBER MADE FROM NOW ON** (QUEUE 283): signup marks
## the welcome pending, in the gopher's own users folder, and the member's
## first /chat gives it: their DM with the host (member 1) gets the host's
## automated hello, in `general`, by the host's name, and the member's
## bookmark at it, so /chat opens on it; then the mark goes. An account with
## no mark is never welcomed, whatever its DMs. **ONCE**: a DM with the host
## that has a topic already (a welcome stored before a crash took the mark's
## removal with it, or the member's own words) only clears the mark. With no
## host yet the mark stays, for the next visit; the host's own mark goes.
## **BEST-EFFORT, IN AN ASIDE**: a read or a store that fails means no
## welcome this time, never a failed /chat; the next visit tries again. The
## accounts it read, for the rest of the request (`Unasked` when it read
## none, or the aside failed).
welcome! : {} => Who
welcome! = |{}| {
	_ = Host.mark_aside!(Begin)
	got = seed_welcome!({})
	match (Host.mark_aside!(End).status, got) {
		(Done, Ok(who)) => who
		_ => Unasked
	}
}

## The host's hello in the DM `key`, and the member's bookmark at it.
hello! : List(Accounts.Account), { host : Uid, key : Paths.ConvKey } => Try({}, [Failed])
hello! = |accounts, { host, key }| {
	name = Members.fail_if_unreadable!(Accounts.name(accounts, host))?
	bytes = key.bytes()
	conv = {
		family: Dm,
		key: bytes,
		base: Conversation.dm_base(bytes),
		members: Conversation.dm_members(bytes),
	}
	text = "Hi, this is an automated message from ${name}. Please say hello and ${name} will get back to you soon."
	_ = append_message_by!(
		conv,
		{
			who: Known(accounts),
			me: host,
			draft: {
				at: { key, topic: "general" },
				name,
				markdown: text,
				cid: "",
			},
		},
	)?
	bookmark!(key, "general")
}

seed_welcome! : {} => Try(Who, [Failed])
seed_welcome! = |{}| {
	me = Members.load_uid!({})?
	match Host.check_welcome!({}) {
		Failed => Err(Failed)
		None => Ok(Unasked)
		Pending => {
			accounts = Members.load_accounts!(Unasked)?
			match List.keep_if(accounts, |a| a.id.to_str() == "1") {
				[host, ..] if host.id != me => {
					pair = Paths.pair_key(host.id, me)
					key = Dm(pair)
					if Paths.first_of(load_topics!(key)).is_empty() {
						hello!(accounts, { host: host.id, key })?
					}
					Host.clear_welcome!({})?
					Ok(Known(accounts))
				}
				[_, ..] => {
					Host.clear_welcome!({})?
					Ok(Known(accounts))
				}
				[] => Ok(Known(accounts))
			}
		}
	}
}

## /chat: the member's last DM, at the topic they resume, or its own page
## when it has no topic yet; with none, the empty /chat.
resume! : Who => Chat.Answer
resume! = |who|
	match Members.load_uid!({}) {
		Err(Failed) => Chat.answered
		Ok(me) => {
			conv = ChatState.bookmark(Files.read!(Paths.last_conv_path(me)))
			match Paths.pair_key_from_str(conv) {
				Ok(pair) if pair.is_participant(me) => {
					topics = load_topics!(Dm(pair))
					if Paths.first_of(topics).is_empty() {
						Chat.redirect("/chat/c/${conv}".to_utf8())
					} else {
						Chat.redirect("/chat/c/${conv}/${resume_at!(me, { pair, topics })}".to_utf8())
					}
				}
				_ =>
					match Members.load_viewer!(who) {
						Ok(viewer) => Chat.respond(
							200,
							{
								content_type: html,
								body: Pages.no_conversations(
									Chrome.src_in(Host.list_srcs!({})),
									viewer,
								).bytes(),
							},
						)
						Err(Failed) => Chat.answered
					}
			}
		}
	}

## Where member `me` resumes DM `conv`, whose topics are `topics`: the
## choice ChatState's, the last-viewed topic and the clock the host's.
resume_at! : Uid, { pair : Paths.PairKey, topics : List(Str) } => Str
resume_at! = |me, { pair, topics }| {
	last = ChatState.bookmark(Files.read!(Paths.last_session_path(me, Dm(pair))))
	ChatState.resume_topic(topics, { last, now_secs: Host.read_time!({}) })
}

## /chat/conversations: a DM with every other member, where the member
## resumes it, and its topics.
serve_conversations! : {} => Chat.Answer
serve_conversations! = |{}|
	match (load_roster!({}), Members.load_uid!({})) {
		(Ok(members), Ok(me)) => Chat.respond(
			200,
			{
				content_type: json,
				body: Conversation.conversations_json(
					me,
					load_dm_entries!(
						me,
						members,
						0,
						[],
					),
				),
			},
		)
		(Err(Failed), _) | (Ok(_), Err(Failed)) => Chat.answered
	}

## The authorized roster (listAuthorized), from the accounts. `Failed` when
## the accounts could not be listed, or one the roster reads would not read
## (the request has failed with its error).
load_roster! : {} => Try(List({ id : Uid, name : Str }), [Failed])
load_roster! = |{}|
	match Members.load_accounts!(Unasked) {
		Ok(all) => Members.fail_if_unreadable!(Accounts.authorized(all))
		Err(Failed) => Err(Failed)
	}

load_dm_entries! : Uid,
List(
	{
		id : Uid,
		name : Str,
	},
),
U64,
List(Conversation.Entry) => List(Conversation.Entry)
load_dm_entries! = |
	me,
	members,
	i,
	acc,
|
	match List.get(members, i) {
		Ok({ id, name }) =>
			if id == me {
				load_dm_entries!(
					me,
					members,
					i + 1,
					acc,
				)
			} else {
				pair = Paths.pair_key(me, id)
				listed = load_topics!(Dm(pair))
				default = resume_at!(me, { pair, topics: listed })
				load_dm_entries!(
					me,
					members,
					i + 1,
					List.append(
						acc,
						{
							conv: pair,
							id,
							name,
							default,
							sessions: listed,
						},
					),
				)
			}
		Err(_) => acc
	}

## A conversation's members as Uids: each is a canonical pair's half or a
## line Paths.channel_members checked, so one that is no uid fails the
## request (NotUtf8, about it), and `Failed`.
decode_members! : List(List(U8)) => Try(List(Uid), [Failed])
decode_members! = |all|
	match List.keep_if(all, |m| Uid.from_utf8(m).is_err()) {
		[bad, ..] => {
			Host.fail!(NotUtf8, bad)
			Err(Failed)
		}
		[] => Ok(List.keep_oks(all, Uid.from_utf8))
	}

## /chat/msg/<id>: the topic a message id names, in the member's DMs, then
## their channels; a 302 there.
redirect_to_msg! : List(U8) => Chat.Answer
redirect_to_msg! = |id|
	if !Paths.is_valid_msg_ref_id(id) {
		Chat.not_found
	} else {
		topic = match List.split_last(id, '_') {
			Ok({ before, after: _ }) => before
			Err(NotFound) => []
		}
		at = |base, key| List.join([
			Str.to_utf8(base),
			key,
			['/'],
			topic,
			Str.to_utf8("#msg-"),
			id,
		])
		match (Members.load_uid!({}), load_roster!({})) {
			(Err(Failed), _) | (Ok(_), Err(Failed)) => Chat.answered
			(Ok(me), Ok(members)) =>
				match find_dm!(
					me,
					{
						members,
						topic,
						at: 0,
					},
				) {
					Ok(conv) => Chat.found(at("/chat/c/", conv))
					Err(NoSuchTopic) =>
						match load_channel_rosters!({}) {
							Err(Failed) => Chat.answered
							Ok(rosters) =>
								match find_channel!(
									Paths.member_channels(rosters, me),
									{ topic, at: 0 },
								) {
									Ok(name) => Chat.found(at("/channel/", name))
									Err(NoSuchTopic) => Chat.not_found
								}
						}
				}
		}
	}

find_dm! : Uid,
{
	members : List({ id : Uid, name : Str }),
	topic : List(U8),
	at : U64,
} => Try(List(U8), [NoSuchTopic])
find_dm! = |
	me,
	{
		members,
		topic,
		at: i,
	},
|
	match List.get(members, i) {
		Ok({ id, name: _ }) =>
			if id == me {
				find_dm!(
					me,
					{
						members,
						topic,
						at: i + 1,
					},
				)
			} else {
				pair = Paths.pair_key(me, id)
				if List.contains(
					List.map(load_topics!(Dm(pair)), Str.to_utf8),
					topic,
				) Ok(pair.bytes()) else find_dm!(
					me,
					{
						members,
						topic,
						at: i + 1,
					},
				)
			}
		Err(_) => Err(NoSuchTopic)
	}

find_channel! : List(Str), { topic : List(U8), at : U64 } => Try(List(U8), [NoSuchTopic])
find_channel! = |names, { topic, at: i }|
	match List.get(names, i) {
		Ok(name) =>
			match Paths.channel_name_from_str(name) {
				Ok(valid) =>
					if List.contains(List.map(load_topics!(Channel(valid)), Str.to_utf8), topic) {
						Ok(name.to_utf8())
					} else {
						find_channel!(names, { topic, at: i + 1 })
					}
				# Every name here passed channel_name_from_str already
				# (load_rosters_from! keeps no other).
				Err(Invalid) => crash "find_channel!: a kept roster's name is no channel name"
			}
		Err(_) => Err(NoSuchTopic)
	}

## POST <base>/new: a topic made with a first "hi", a DM's announced in its
## highest general<N>; the conversation and topic as JSON.
create_topic! : Chat.Request, { route : Route.R, key : Paths.ConvKey } => Chat.Answer
create_topic! = |req, { route, key }|
	match find!(key) {
		Ok((conv, who)) =>
			if req.method != Post {
				Chat.not_allowed(Post)
			} else {
				body = Host.read_body!(Message)
				if body.status == Answered {
					Chat.answered
				} else {
					match Form.field(body.bytes, "topic") {
						Malformed => Chat.malformed
						Found(raw) => make_topic!(
							key,
							{
								conv,
								who,
								topic: ZigText.trim_str(raw),
							},
						)
						Missing => make_topic!(
							key,
							{
								conv,
								who,
								topic: "",
							},
						)
					}
				}
			}
		Err(NotYours) => not_yours!(route)
		Err(Failed) => Chat.answered
	}

make_topic! : Paths.ConvKey,
{
	conv : Chat.Conv,
	who : Who,
	topic : Str,
} => Chat.Answer
make_topic! = |
	key,
	{
		conv,
		who,
		topic,
	},
| {
	if !Paths.is_topic_id(topic) {
		Chat.respond(
			400,
			{
				content_type: [],
				body: Str.to_utf8("Topic must be letters, digits, and hyphens only — no spaces, underscores, or punctuation.\n"),
			},
		)
	} else if topic.caseless_ascii_equals("new") {
		Chat.respond(
			400,
			{
				content_type: [],
				body: Str.to_utf8("\"new\" is reserved — pick another topic name.\n"),
			},
		)
	} else if Conversation.has_topic(load_topics!(key), topic) {
		Chat.respond(409, { content_type: [], body: Str.to_utf8("That topic already exists.\n") })
	} else {
		match Members.load_viewer!(who) {
			Err(Failed) => Chat.answered
			Ok(name) => {
				dm = conv.family == Dm
				# The bookmark first, as a send's: one that fails makes no topic.
				if dm and bookmark!(key, topic).is_err() {
					Chat.answered
				} else if append_message!(
					conv,
					{
						who,
						draft: {
							at: { key, topic },
							name,
							markdown: "hi",
							cid: "",
						},
					},
				).is_err() {
					Chat.answered
				} else {
					# **STORED IS DONE** (metal-vmm QUEUE 267): the topic is
					# made once its "hi" is stored, so the announcement is an
					# aside, best-effort, counted when it fails, never a 500
					# whose retry is a 409.
					if dm {
						_ = Host.mark_aside!(Begin)
						_ = announce!(
							key,
							{
								conv,
								who,
								topic,
								name,
							},
						)
						match Host.mark_aside!(End).status {
							Done => {}
							Failed => Host.count_dropped!(Announcement, topic.to_utf8())
						}
					} else {
						{}
					}
					Chat.respond(
						200,
						{ content_type: json, body: Conversation.made_json({ key, topic }) },
					)
				}
			}
		}
	}
}

## A DM's new topic, said where the partner already watches: its highest
## general<N>, unless that is the topic made.
announce! : Paths.ConvKey,
{
	conv : Chat.Conv,
	who : Who,
	topic : Str,
	name : Str,
} => Try({}, [Failed])
announce! = |
	key,
	{
		conv,
		who,
		topic,
		name,
	},
|
	match Conversation.highest_general(load_topics!(key)) {
		Ok(gen) if gen != topic =>
			append_message!(
				conv,
				{
					who,
					draft: {
						at: { key, topic: gen },
						name,
						markdown: "New topic: [${topic}](${key.base()}/${topic})",
						cid: "",
					},
				},
			).map_ok(|_| {})
		_ => Ok({})
	}

## POST .../<topic>/send: docs/ROC-CHAT.md §6.2's steps, the store's append
## the host's. A send makes its topic, so no topic need be there; the
## conversation must be the member's.
send! : Chat.Request, { route : Route.R, key : Paths.ConvKey } => Chat.Answer
send! = |req, { route, key }|
	match find!(key) {
		Err(Failed) => Chat.answered
		Ok((conv, who)) =>
		# The title before any tail, unused, as the Zig's convRoute read
		# it: a partner whose name will not read fails a send too.
			match load_title!(key, who) {
				Err(Failed) => Chat.answered
				Ok(_) => receive_message!(
					req,
					{
						route,
						at: { key, topic: route.topic },
						conv,
						who,
					},
				)
			}
		Err(NotYours) => not_yours!(route)
	}

## A send in `conv`, found and titled: the tail, the method, the header,
## the body, the form.
receive_message! : Chat.Request,
{
	route : Route.R,
	at : Paths.TopicAt,
	conv : Chat.Conv,
	who : Who,
} => Chat.Answer
receive_message! = |
	req,
	{
		route,
		at,
		conv,
		who,
	},
|
	if route.tail == InvalidSend {
		Chat.not_found
	} else if req.method != Post {
		Chat.not_allowed(Post)
	} else {
		# The header before the body: reading the body moves past it.
		send = if Host.read_header!(Str.to_utf8("x-chat-async")) == [['1']] Async else Sync
		body = Host.read_body!(Message)
		if body.status == Answered {
			Chat.answered
		} else {
			match Form.field(body.bytes, "markdown") {
				Malformed => Chat.malformed
				Missing => Chat.refuse("not sent: no message (the form has no markdown field)\n")
				Found(md) =>
					match Form.field(body.bytes, "cid") {
						Malformed => Chat.malformed
						Found(cid) => store!(
							at,
							{
								conv,
								who,
								send,
								posted: { markdown: md, cid },
							},
						)
						Missing => store!(
							at,
							{
								conv,
								who,
								send,
								posted: { markdown: md, cid: "" },
							},
						)
					}
			}
		}
	}

## What the send form carried: the message's `markdown` and the sender's
## client id `cid`. Named fields because both are text. It becomes
## a Draft once the message is judged and its author's name read.
Posted : { markdown : Str, cid : Str }

## The message judged, then stored: empty or hostile is refused (one that
## is not UTF-8 text the form refused); the bookmark (a DM's) before the
## store, so one that fails stores nothing; then 204 for an async sender,
## else back to the topic.
store! : Paths.TopicAt,
{
	conv : Chat.Conv,
	who : Who,
	send : [Async, Sync],
	posted : Posted,
} => Chat.Answer
store! = |
	at,
	{
		conv,
		who,
		send,
		posted: { markdown: md, cid },
	},
|
	if Bytes.trim(md.to_utf8(), Bytes.zig_spaces) == [] {
		Chat.refuse("not sent: the message is empty\n")
	} else if Host.check_hostile!(
		md.to_utf8(),
		Str.to_utf8("not sent: malformed markdown — too much formatting; break it into smaller messages\n"),
	) != Fine {
		Chat.answered
	} else {
		match Members.load_viewer!(who) {
			Err(Failed) => Chat.answered
			Ok(name) =>
				if conv.family == Dm and bookmark!(at.key, at.topic).is_err() {
					Chat.answered
				} else if append_message!(
					conv,
					{
						who,
						draft: {
							at,
							name,
							markdown: md,
							cid,
						},
					},
				).is_err() {
					Chat.answered
				} else if send == Async {
					Chat.respond(204, { content_type: [], body: [] })
				} else {
					Chat.redirect(List.concat(conv.base, "/${at.topic}".to_utf8()))
				}
		}
	}

## /chat/search/words or /messages; anything else under it the Zig's 404.
search! : Chat.Request, Str => Chat.Answer
search! = |req, rest|
	if rest == "/words" {
		search_words!(req)
	} else if rest == "/messages" {
		search_messages!(req)
	} else {
		Chat.not_found
	}

## **SEARCH'S WORDS** (GET /chat/search/words, chat_search.zig `handle` as it
## was, metal-vmm QUEUE 281): the method, the rate limit (the host's), the
## typed `prefix` decoded (a bad escape is the site's 400) and made a key,
## then the words the index holds that begin it, of what the member can see
## (the host's); none for an empty key. 503 with no index.
## A search's refusal as its JSON says it: `{"error":<text>}`.
search_error : Str -> List(U8)
search_error = |text| JsonOut.object([("error", JsonOut.string(text))]).bytes()

search_words! : Chat.Request => Chat.Answer
search_words! = |req|
	if req.method != Get {
		Chat.not_allowed(Get)
	} else if Host.admit!({}) == Refused {
		Chat.respond(
			429,
			{ content_type: json, body: search_error("too many searches; wait a second") },
		)
	} else {
		match Form.decode(List.first(Host.read_query!(Str.to_utf8("prefix"))) ?? []) {
			Err(BadEscape) => Chat.malformed
			Ok(typed) => {
				key = Search.key(typed)
				got = Host.search_words!(key, if key == [] 0 else Search.most_words)
				match got.status {
					Ready => Chat.respond(
						200,
						{
							content_type: json,
							body: Search.words_json(
								key,
								{ unreadable: got.unreadable, words: got.words },
							),
						},
					)
					NotReady => Chat.respond(
						503,
						{ content_type: json, body: search_error("search is not ready") },
					)
				}
			}
		}
	}

## **SEARCH'S MESSAGES** (GET /chat/search/messages, chat_search.zig
## `handle` as it was, metal-vmm QUEUE 282): as the words are asked, the
## `word` field; a key shorter than a word finds nothing; each hit's
## excerpt cut here (Search.excerpt) from the window the host hands.
search_messages! : Chat.Request => Chat.Answer
search_messages! = |req|
	if req.method != Get {
		Chat.not_allowed(Get)
	} else if Host.admit!({}) == Refused {
		Chat.respond(
			429,
			{ content_type: json, body: search_error("too many searches; wait a second") },
		)
	} else {
		match Form.decode(List.first(Host.read_query!(Str.to_utf8("word"))) ?? []) {
			Err(BadEscape) => Chat.malformed
			Ok(typed) => {
				key = Search.key(typed)
				got = Host.search_messages!(
					key,
					if List.len(key) < Search.min_len 0 else Search.most_messages,
				)
				match got.status {
					Ready => Chat.respond(
						200,
						{
							content_type: json,
							body: Search.messages_json(
								key,
								{
									matched: got.matched,
									unreadable: got.unreadable,
									hits: got.hits,
								},
							),
						},
					)
					NotReady => Chat.respond(
						503,
						{ content_type: json, body: search_error("search is not ready") },
					)
				}
			}
		}
	}

## **A DOC POSTED TO CHAT** (POST /chat/docs/post, docs.zig `docsPost` as it
## was, metal-vmm QUEUE 278): the member's doc `slug`, as it is on disk, a
## message to their default partner's DM, at the topic they resume it at;
## 200 with where it went, for the client to go there. Refused in the Zig's
## words: a slug that is none, a doc empty or not there, one too formatted
## (the host's 400), no partner to post to. A doc that is not UTF-8 text
## fails the request (NotUtf8): it is the message.
post_doc! : Chat.Request => Chat.Answer
post_doc! = |req|
	if req.method != Post {
		Chat.not_allowed(Post)
	} else {
		body = Host.read_body!(Doc)
		if body.status == Answered {
			Chat.answered
		} else {
			match Form.field(body.bytes, "slug") {
				Malformed => Chat.malformed
				Found(slug) => post_slug!(ZigText.trim_str(slug))
				Missing => post_slug!("")
			}
		}
	}

post_slug! : Str => Chat.Answer
post_slug! = |slug|
	match Members.load_uid!({}) {
		Err(Failed) => Chat.answered
		Ok(me) =>
			match Paths.doc_path(me, slug) {
				Err(NotASlug) => Chat.refuse("bad slug\n")
				Ok(path) =>
					match Files.read_text!(path) {
						Ok(text) => post_text!(me, text)
						# readUserDoc: a doc not there reads empty.
						Err(Missing) => post_text!(me, "")
						Err(Failed) => Chat.answered
						Err(NotUtf8) => {
							Host.fail!(NotUtf8, path.bytes())
							Chat.answered
						}
					}
			}
	}

## The doc's text judged, its partner found, then stored as a message.
post_text! : Uid, Str => Chat.Answer
post_text! = |me, md|
	if Bytes.trim(md.to_utf8(), Bytes.zig_spaces) == [] {
		Chat.refuse("doc is empty\n")
	} else if Host.check_hostile!(
		md.to_utf8(),
		Str.to_utf8("not posted: too much markdown formatting; break the doc up\n"),
	) != Fine {
		Chat.answered
	} else {
		match Members.load_accounts!(Unasked) {
			Err(Failed) => Chat.answered
			Ok(accounts) =>
				match Members.fail_if_unreadable!(Accounts.authorized(accounts)) {
					Err(Failed) => Chat.answered
					Ok(roster) =>
						match List.keep_if(
							roster,
							|u| u.id != me and u.id.to_str() == default_partner(me),
						) {
							[] => Chat.refuse("no default chat partner available\n")
							[partner, ..] => post_to!(
								me,
								{
									who: Known(accounts),
									pair: Paths.pair_key(me, partner.id),
									md,
								},
							)
						}
				}
		}
	}

## defaultChatPartner: member 1's is 2, everyone else's 1.
default_partner : Uid -> Str
default_partner = |me| if me.to_str() == "1" "2" else "1"

## The doc stored in DM `pair`, at the topic `me` resumes it at, by their
## name, with no client id; the bookmark left as it was (appendMessage
## wrote none).
post_to! : Uid,
{
	who : Who,
	pair : Paths.PairKey,
	md : Str,
} => Chat.Answer
post_to! = |
	me,
	{
		who,
		pair,
		md,
	},
| {
	key = Dm(pair)
	topic = resume_at!(me, { pair, topics: load_topics!(key) })
	bytes = key.bytes()
	conv = {
		family: Dm,
		key: bytes,
		base: Conversation.dm_base(bytes),
		members: Conversation.dm_members(bytes),
	}
	match Members.load_viewer!(who) {
		Err(Failed) => Chat.answered
		Ok(name) =>
			match append_message!(
				conv,
				{
					who,
					draft: {
						at: { key, topic },
						name,
						markdown: md,
						cid: "",
					},
				},
			) {
				Err(Failed) => Chat.answered
				Ok(id) => Chat.respond(
					200,
					{
						content_type: json,
						body: JsonOut.object([
							("conv", JsonOut.string(pair.to_str())),
							("session", JsonOut.string(topic)),
							("id", JsonOut.string(id)),
						]).bytes(),
					},
				)
			}
	}
}

## A message not yet stored: where it goes (`at`, its conversation and
## topic), its author's `name`, its `markdown`, and the sender's client id
## `cid`. Named fields because three are byte lists: in a row of
## arguments, a swapped pair type-checks.
Draft : {
	at : Paths.TopicAt,
	name : Str,
	markdown : Str,
	cid : Str,
}

## **A MESSAGE STORED, THEN SENT LIVE** (angry-gopher chat_store
## `appendMessage`, its comments the spec): by the member, named `name`, to
## `topic` of `conv` (as the request spelled it), with the
## sender's client id `cid` ("" for none). Its number is the topic's count
## (`message_count!`), its id `<topic>_<n>`, its stamp the request's time; its
## block and its frame are made, then the block stored (`store_block!`: the
## append, the count cache, the search index), then the frame published
## on the topic's key, then the fan-out (`fan_out!`, its steps Fanout.roc's,
## made before the store too). `who` holds a DM's accounts (the fan-out
## names the other member). Its id once stored; `Err(Failed)` when a step
## before the store failed (the request has, with its error), and nothing
## was stored.
append_message! : Chat.Conv, { who : Who, draft : Draft } => Try(Str, [Failed])
append_message! = |conv, { who, draft }| append_message_by!(
	conv,
	{
		who,
		me: Members.load_uid!({})?,
		draft,
	},
)

## append_message!, by the member `me` (the request's, or the host's for
## the welcome DM).
append_message_by! : Chat.Conv,
{
	who : Who,
	me : Uid,
	draft : Draft,
} => Try(Str, [Failed])
append_message_by! = |
	conv,
	{
		who,
		me,
		draft: {
			at: topic_at,
			name,
			markdown: md,
			cid,
		},
	},
|
	# **NO MESSAGE WITHOUT AN AUTHOR** (the review of 156): the decoder
	# refuses such a block on every read, so it would go out live and be
	# gone on reload. A nameless member (a release cut short) cannot post.
	if name == "" {
		Host.fail!(NoAuthor, [])
		Err(Failed)
	} else {
		topic = topic_at.topic
		match Last.messages!(topic_at) {
			Ok(count) => {
				index = count
				# A count of the largest U64 has no next number: the call
				# crashes into a 500, storing nothing.
				id = "${topic}_${U64.to_str(index + 1)}"
				stamp = Time.rfc3339(Host.read_time!({}))
				message = {
					id: id.to_utf8(),
					from: name.to_utf8(),
					at: stamp.to_utf8(),
					uid: By(me),
					markdown: md.to_utf8(),
				}
				block = Transcript.stored_form(index, message)
				# The store's record (Chat.Message, which the host reads): the
				# same message, its author's digits.
				stored = {
					id: message.id,
					from: message.from,
					at: message.at,
					uid: me.to_str().to_utf8(),
					markdown: message.markdown,
				}
				rendered = Host.render!(md.to_utf8())
				# **THE HTML DECODED HERE, AT THE DOOR**: the renderer makes
				# text of text, so html that is not UTF-8 is the host's fault,
				# and the send fails (NotUtf8, about the message's id) before
				# anything is stored.
				match (rendered.status, Str.from_utf8(rendered.html)) {
					(Failed, _) => Err(Failed)
					(Rendered, Err(_)) => {
						Host.fail!(NotUtf8, id.to_utf8())
						Err(Failed)
					}
					(Rendered, Ok(page_html)) => {
						# **THE ECHO IS MADE BEFORE THE STORE** (metal-vmm QUEUE
						# 177.1): the live publish's key and frame, so nothing
						# can fail between the store and the publish. A live
						# publish that failed after the store answered success
						# with no echo on the sender's stream, whose client then
						# sent the message again: a duplicate.
						key = BusKey.topic(topic_at)
						# **THE FAN-OUT IS MADE BEFORE THE STORE TOO**: every
						# member's events and feed entries, so what runs after
						# the store only sends and appends. A DM's accounts are
						# the request's already (`find!`); asked here only were
						# they not, before anything is stored.
						named = if topic_at.key.kind() == Dm Members.load_accounts!(who) else Ok([])
						match (named, decode_members!(conv.members)) {
							(Ok(all), Ok(members)) => {
								frame = Frame.message({
									index,
									from: name,
									from_uid: me,
									at: stamp,
									html: page_html,
									markdown: md,
									id,
									cid,
								})
								steps = Fanout.steps(
									{
										key: topic_at.key,
										members,
										topic,
										index,
										id,
										from: name,
										at: stamp,
										uid: me,
										accounts: all,
									},
									Fanout.parts_of(md),
								)
								store_block!(
									topic_at,
									{
										block,
										index,
										message: stored,
									},
								)?
								# **STORED IS DONE** (metal-vmm QUEUE 172): from
								# here nothing fails the send, which a client
								# would answer by sending it again. The publish
								# cannot fail; the fan-out is best-effort, each
								# failure counted and said.
								Host.publish!(key.bytes(), frame)
								fan_out!(topic_at, steps)
								Ok(id)
							}
							_ => Err(Failed)
						}
					}
				}
			}
			Err(Failed) => Err(Failed)
		}
	}

## **A MESSAGE STORED, IN ITS ORDER** (chat_store `storeMessage` as it was,
## metal-vmm QUEUE 287): `block`, message `index`, appended to the topic's
## transcript (the one primitive that can fail the send); then the `.count`
## (`index` + 1, the transcript's new size, where the block begins and who
## wrote it), the text the backfill writes for the same transcript; then the
## search index told of `message`. **A CRASH BETWEEN THE APPEND AND THE
## COUNT** leaves a count whose size is not the transcript's, which the next
## count refuses and recounts (Count.believed): the size is the protection,
## not the order. **STORED IS DONE**: the count and the index never fail it.
store_block! : Paths.TopicAt,
{
	block : List(U8),
	index : U64,
	message : Chat.Message,
} => Try({}, [Failed])
store_block! = |
	at,
	{
		block,
		index,
		message,
	},
| {
	size = Files.append!(Paths.transcript_path(at), block)?
	last = Known({
		offset: size - List.len(block),
		uid: message.uid,
	})
	Files.write_cache!(
		Paths.count_path(at),
		Count.text(index + 1, { size, last }),
	)
	Host.index_message!(Paths.conv_folder(at.key).bytes(), { sid: at.topic.to_utf8(), message })
	Ok({})
}

## **THE FAN-OUT, CARRIED OUT IN ITS ORDER** (Fanout.steps): each publish
## sent; each feed's entry appended and only then its event sent; each
## surface that failed for a member counted and said (`report_fanout_failure!`),
## on the topic `at`. **A FAILURE NEVER STOPS
## THE STEPS AFTER IT, NOR FAILS THE SEND.**
fan_out! : Paths.TopicAt, List(Fanout.Step) => {}
fan_out! = |at, steps|
	match steps {
		[] => {}
		[step, .. as rest] => {
			match step {
				Publish(on, bytes) => Host.publish!(on.bytes(), bytes)
				# **EACH FEED'S ENTRY IN AN ASIDE OF ITS OWN** (metal-vmm QUEUE
				# 172, 156(c)): a stat or an append that fails is that
				# member's surface's, its fault counted and said, never the
				# send's; the steps after it go on. A request that has failed
				# already begins none.
				AppendFeed(f) =>
					match Host.mark_aside!(Begin).status {
						Failed => {}
						Done => {
							_ = Files.append_entry!(f.path, { separator: f.sep, entry: f.entry })
							ended = Host.mark_aside!(End)
							match ended.status {
								Done => Host.publish!(f.key.bytes(), f.event)
								Failed => Host.report_fanout_failure!(
									f.surface,
									{
										member: f.member,
										key: at.key.bytes(),
										sid: at.topic.to_utf8(),
										fault: ended.fault,
									},
								)
							}
						}
					}
			}
			fan_out!(at, rest)
		}
	}
