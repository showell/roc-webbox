## THE ROC CHAT: the router (docs/ROC-CHAT.md §3, milestone 1). Every /chat
## and /channel request angry-gopher has comes here first. The router runs
## the prelude angry-gopher's chat.zig `handle` and `handleChannel` ran,
## parses the path (Route.roc), and hands the route to Zig, which serves it
## once this call has returned.
##
## The prelude, in Zig's order:
##   1. a static script under /chat (`/<name>.js`) is served to anyone;
##   2. anyone not a member or the agent is sent to sign in, and returned;
##   3. every other request counts as presence, but a stream (by its route:
##      chat.zig read it from the path's spelling, so `.../stream/` counted).
##
## A topic's reactions, react, pin and unpin are the Roc's (docs/ROC-CHAT.md
## C4, `act!`); a reaction is the Roc's whole (its reactor, its bound, its
## stamp, its line and its frame), stored and sent through the primitives
## (`append_line!`, `message_count!`, `publish!`); a message is the Roc's
## too (`append_message!`: its author, number, stamp, block and frame), stored
## through `store_block!` (the append, the count cache, the search index),
## and its fan-out (Fanout.roc: every member's surfaces, their keys, events
## and feed entries) through `publish!`, `append_entry!` and
## `report_fanout_failure!`, the message's parts its own (Fanout.parts_of).
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
import Topics
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

handle! : Chat.Request => Chat.Answer
handle! = |req|
	if req.area == Retire {
		retire!({})
	} else {
		# **A PATH IS TEXT AT THE DOOR**: one that is not UTF-8 is the site's
		# 400 for a malformed request, before anything else reads it.
		match Str.from_utf8(req.sub) {
			Ok(sub) => dispatch!(req, sub)
			Err(_) => Chat.malformed
		}
	}

## **THE ADMIN RETIRE** (metal-vmm QUEUE 293), asked in its own area by
## the admin page behind its password, before any of the chat's prelude
## (no member, no presence): the keep list checked against the accounts,
## then the plan made and handed to the host a step at a time. A keep list
## refused is a 400 in its own words; a plan carried out, an empty 200.
retire! : {} => Chat.Answer
retire! = |{}| {
	asked = Retire.asked!({})
	match load_accounts!(Unasked) {
		Err(Failed) => Chat.answered
		Ok(accounts) =>
			match Retire.refused(accounts, asked.keep) {
				Err(Unreadable(why)) => {
					fail_unreadable!(why)
					Chat.answered
				}
				Err(Refused(why)) => Chat.respond(
					400,
					[],
					why.to_utf8(),
				)
				Ok({}) =>
					match Retire.plan!(accounts, asked) {
						Err(Failed) => Chat.answered
						Ok(steps) =>
							match Retire.carry_out!(steps) {
								Ok({}) => Chat.respond(
									200,
									[],
									[],
								)
								Err(Failed) => Chat.answered
							}
					}
			}
	}
}

## The request, its path (`sub`) the text handle! checked.
dispatch! : Chat.Request, Str => Chat.Answer
dispatch! = |req, sub|
	match (if req.area == Channel Err(NotAnAsset) else Route.asset(sub)) {
		Ok(route) => zig(route)
		Err(NotAnAsset) =>
			if Host.check_member!({}) == Outsider {
				area = if req.area == Channel "/channel" else "/chat"
				Chat.to_login(List.concat(Str.to_utf8(area), req.sub))
			} else {
				route = if req.area == Channel Route.under_channel(sub) else Route.under_chat(sub)
				match served_by(route) {
					Roc => act!(req, route)
					# A stream is no presence (the Zig's streams were served uncounted).
					Zig => {
						if Route.is_stream(route) {} else presence!(Unasked)
						zig(route)
					}
				}
			}
	}

## **NOT THE VIEWER'S, OR NOT A CONVERSATION**: a DM's is webbox's plain 404,
## a channel's the page that says why, naming no channel a viewer cannot
## see (one not there and one not theirs read alike).
not_yours! : Route.R => Chat.Answer
not_yours! = |route|
	if route.family == Channel {
		not_found_page!(
			Unasked,
			"#${route.key} is not a channel you are a member of.",
			"/chat",
		)
	} else {
		Chat.not_found
	}

## **A 404 THAT SAYS WHY** (metal-vmm QUEUE 156(j)): `what` is not there, and
## `back` is where to go instead.
not_found_page! : Who, Str, Str => Chat.Answer
not_found_page! = |
	who,
	what,
	back,
|
	match load_viewer!(who) {
		Ok(viewer) => Chat.respond(
			404,
			html,
			Pages.not_found(
				Chrome.src_in(Host.srcs!({})),
				{
					viewer,
					what,
					back,
				},
			).bytes(),
		)
		Err(Failed) => Chat.answered
	}

## The route handed back to the Zig, as the seam's bytes.
zig : Route.R -> Chat.Answer
zig = |route| Chat.zig(Route.to_wire(route))

## Which side serves a route. The Roc serves: /chat and /chat/default, the recent,
## images and code pages and every stream (metal-vmm QUEUE 286), /chat/links,
## /chat/conversations, /chat/msg/<id>; and every route of a DM or a
## channel. Every other route is Zig's.
served_by : Route.R -> [Roc, Zig]
served_by = |r|
	match r.family {
		Default | Links | Conversations | Msg => Roc
		# The pages and their streams (metal-vmm QUEUE 286): the Roc picks
		# the member's bus key, the host holds the stream.
		Recent | Images | Code | Notifications | SidebarStream => Roc
		NotFound => Roc
		# **THE ROC DECIDES EVERY CONVERSATION'S ROUTE** (metal-vmm QUEUE
		# 271): whose it is, whether its topic is there, every 404, and
		# each tail's work (the last, an upload's POST: QUEUE 292).
		Dm | Channel => Roc
		# The docs: posted to chat (metal-vmm QUEUE 278), the read pages
		# (289), the writes and the live preview (290).
		Docs => Roc
		# Search's words and messages (metal-vmm QUEUE 281, 282), and the
		# 404 for anything else under /chat/search.
		Search => Roc
		_ => Zig
	}

## The Roc's own routes: presence, then the route's own work.
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
			_ = Host.aside!(Begin)
			told = came_online!(who)
			match (Host.aside!(End), told) {
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
	me = load_uid!({})?
	all = load_accounts!(who)?
	name = fail_if_unreadable!(Accounts.name(all, me))?
	roster = fail_if_unreadable!(Accounts.authorized(all))?
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
docs! = |req, rest|
	if rest == "/post" {
		post_doc!(req)
	} else if rest == "/new" {
		new_doc!(req)
	} else if rest == "/save" {
		save_doc!(req)
	} else if rest == "/render" {
		preview_doc!(req)
	} else if rest == "/save_to_reading_list" {
		save_to_reading_list!(req)
	} else {
		docs_read!(req, rest)
	}

## docsNew: a doc of the posted title, made empty, then its editor (303);
## a GET, or no title, back to the docs.
new_doc! : Chat.Request => Chat.Answer
new_doc! = |req|
	if req.method != Post {
		Chat.redirect("/chat/docs".to_utf8())
	} else {
		body = Host.read_body!(Doc)
		if body.status == Answered {
			Chat.answered
		} else {
			match Form.field(body.bytes, "title") {
				Malformed => Chat.malformed
				Found(title) => create_doc!(ZigText.trim_str(title))
				Missing => create_doc!("")
			}
		}
	}

## createUserDoc: the title's slug, one no doc has yet, made empty.
create_doc! : Str => Chat.Answer
create_doc! = |title|
	if title == "" {
		Chat.redirect("/chat/docs".to_utf8())
	} else {
		match load_uid!({}) {
			Err(Failed) => Chat.answered
			Ok(me) =>
				match unused_slug!(me, Docs.slug_of_title(title)) {
					Err(Failed) => Chat.answered
					Ok(slug) =>
						match Paths.doc_path(me, slug) {
							# A slug of 80 suffixed past 80 (docPath's InvalidDocSlug).
							Err(NotASlug) => Chat.respond(
								500,
								[],
								"The doc cannot be made: InvalidDocSlug.\n".to_utf8(),
							)
							Ok(path) =>
								match Files.write!(path, []) {
									Err(Failed) => Chat.answered
									Ok({}) => {
										doc_touched!(me, slug)
										Chat.redirect("/chat/docs/${slug}".to_utf8())
									}
								}
						}
				}
		}
	}

## uniqueDocSlug: `base` unless a doc has it or a docs route does, else
## the first of `base-2` to `base-999` no doc has; past those, `base`.
unused_slug! : Uid, Str => Try(Str, [Failed])
unused_slug! = |me, base|
	if [
		"list",
		"new",
		"save",
		"render",
		"post",
	].contains(base) {
		suffixed_slug!(
			me,
			base,
			2,
		)
	} else {
		match doc_there!(me, base) {
			Err(Failed) => Err(Failed)
			Ok(Free) => Ok(base)
			Ok(Taken) => suffixed_slug!(
				me,
				base,
				2,
			)
		}
	}

## `base-n`, or the next, up to 999.
suffixed_slug! : Uid, Str, U64 => Try(Str, [Failed])
suffixed_slug! = |
	me,
	base,
	n,
|
	if n >= 1000 {
		Ok(base)
	} else {
		candidate = "${base}-${n.to_str()}"
		match doc_there!(me, candidate) {
			Err(Failed) => Err(Failed)
			Ok(Free) => Ok(candidate)
			Ok(Taken) => suffixed_slug!(
				me,
				base,
				n + 1,
			)
		}
	}

## docFileExists: whether the member has a doc `slug` (a name no slug
## names none).
doc_there! : Uid, Str => Try([Taken, Free], [Failed])
doc_there! = |me, slug|
	match Paths.doc_path(me, slug) {
		Err(NotASlug) => Ok(Free)
		Ok(path) =>
			match Files.stat!(path) {
				Ok(_) => Ok(Taken)
				Err(Missing) => Ok(Free)
				Err(Failed) => Err(Failed)
			}
	}

## docsSave: a doc's body replaced (the editor's autosave), then 204.
## **A SAVE SAYS WHAT IT SAVES** (metal-vmm QUEUE 172): no body field is
## refused, never an emptied doc; a doc not there is a 404, never made.
save_doc! : Chat.Request => Chat.Answer
save_doc! = |req|
	if req.method != Post {
		Chat.not_allowed(Post)
	} else {
		body = Host.read_body!(Doc)
		if body.status == Answered {
			Chat.answered
		} else {
			match Form.field(body.bytes, "slug") {
				Malformed => Chat.malformed
				Found(slug) => save_slug!(body.bytes, ZigText.trim_str(slug))
				Missing => save_slug!(body.bytes, "")
			}
		}
	}

## The save of doc `slug`, its text the form's `body`.
save_slug! : List(U8), Str => Chat.Answer
save_slug! = |form, slug|
	match load_uid!({}) {
		Err(Failed) => Chat.answered
		Ok(me) =>
			match Paths.doc_path(me, slug) {
				Err(NotASlug) => refuse("bad slug\n")
				Ok(path) =>
					match Form.field(form, "body") {
						Malformed => Chat.malformed
						Missing => refuse("not saved: no body\n")
						Found(text) =>
							match Files.stat!(path) {
								Err(Missing) => Chat.respond(
									404,
									[],
									"no such doc\n".to_utf8(),
								)
								Err(Failed) => Chat.answered
								Ok(_) =>
									match Files.write!(path, text.to_utf8()) {
										Err(Failed) => Chat.answered
										Ok({}) => {
											doc_touched!(me, slug)
											Chat.respond(
												204,
												[],
												[],
											)
										}
									}
							}
					}
			}
	}

## docsRender: posted markdown as the live preview renders it, the same
## processor a message's; hostile markdown is its placeholder, counted.
preview_doc! : Chat.Request => Chat.Answer
preview_doc! = |req|
	if req.method != Post {
		Chat.not_allowed(Post)
	} else {
		body = Host.read_body!(Doc)
		if body.status == Answered {
			Chat.answered
		} else {
			match Form.field(body.bytes, "body") {
				Malformed => Chat.malformed
				Found(md) => preview!(md)
				Missing => preview!("")
			}
		}
	}

## `md` rendered for the preview.
preview! : Str => Chat.Answer
preview! = |md| {
	rendered = Host.render_preview!(md.to_utf8())
	match rendered.status {
		Failed => Chat.answered
		Rendered => Chat.respond(
			200,
			html,
			rendered.html,
		)
	}
}

## docsSaveToReadingList: a chat message, as its saver saw it, appended to
## their reading list with the way back to it, then 204; a list at its
## cap is the client's 413.
save_to_reading_list! : Chat.Request => Chat.Answer
save_to_reading_list! = |req|
	if req.method != Post {
		Chat.not_allowed(Post)
	} else {
		body = Host.read_body!(Doc)
		if body.status == Answered {
			Chat.answered
		} else {
			fields = List.map(
				[
					"conv",
					"sid",
					"id",
					"from",
					"at",
					"body",
					"note",
				],
				|name| Form.field(body.bytes, name),
			)
			if fields.contains(Malformed) {
				Chat.malformed
			} else {
				texts = List.map(
					fields,
					|f|
						match f {
							Found(t) => t
							_ => ""
						},
				)
				match texts {
					[
						conv,
						sid,
						id,
						from,
						at,
						md,
						note,
					] => saved_message!({
						conv: ZigText.trim_str(conv),
						sid: ZigText.trim_str(sid),
						id: ZigText.trim_str(id),
						from,
						at,
						md,
						note,
					})
					_ => crash "save_to_reading_list!: seven fields asked, not seven answered"
				}
			}
		}
	}

## The saved message appended; one missing a place or a body refused.
saved_message! : {
	conv : Str,
	sid : Str,
	id : Str,
	from : Str,
	at : Str,
	md : Str,
	note : Str,
} => Chat.Answer
saved_message! = |m|
	if m.conv == "" or m.sid == "" or m.id == "" or m.md == "" {
		refuse("missing field\n")
	} else {
		match load_uid!({}) {
			Err(Failed) => Chat.answered
			Ok(me) => {
				url = "${ChatUrl.feed_conv(m.conv).to_str()}/${m.sid}#msg-${m.id}"
				entry = Docs.reading_entry({
					note: m.note,
					from: m.from,
					at: m.at,
					url,
					body: m.md,
				}).to_utf8()
				path = Paths.reading_list_path(me)
				# **A DOCUMENT THAT WILL NOT READ IS NOT AN EMPTY DOCUMENT**:
				# the write replaces it with what was read and the entry.
				stored = match Files.read_bytes!(path) {
					Ok(bytes) => Ok(bytes)
					Err(Missing) => Ok([])
					Err(Failed) => Err(Failed)
				}
				match stored {
					Err(Failed) => Chat.answered
					Ok(before) =>
						if List.len(before) + List.len(entry) > Limits.reading_list_bytes {
							Chat.respond(
								413,
								[],
								"not saved: the reading list is full\n".to_utf8(),
							)
						} else {
							match Files.write!(path, List.concat(before, entry)) {
								Err(Failed) => Chat.answered
								Ok({}) => {
									doc_touched!(me, "reading-list")
									Chat.respond(
										204,
										[],
										[],
									)
								}
							}
						}
				}
			}
		}
	}

## publishDocRecent: the member's own recent feed told of doc `slug`,
## made or saved now.
doc_touched! : Uid, Str => {}
doc_touched! = |me, slug|
	Host.publish!(
		BusKey.recent(me).bytes(),
		Docs.recent_frame(Time.rfc3339(Host.now!({})), slug),
	)

## **THE DOCS' READ PAGES** (docs.zig `handle`, metal-vmm QUEUE 289), each
## the member's own, never another's: the landing, the list's JSON, a doc's
## raw markdown, its editor. One segment after /docs: a nested one is a 404.
docs_read! : Chat.Request, Str => Chat.Answer
docs_read! = |req, rest|
	match load_uid!({}) {
		Err(Failed) => Chat.answered
		Ok(me) =>
			if rest == "" or rest == "/" {
				docs_landing!(me)
			} else {
				seg = rest.drop_prefix("/")
				if seg == "list" {
					if req.method != Get Chat.not_allowed(Get) else docs_list!(me)
				} else if seg.contains("/") {
					Chat.not_found
				} else if seg.ends_with(".md") {
					raw_doc!(me, seg.drop_suffix(".md"))
				} else {
					docs_editor!(me, ZigText.trim_str(seg))
				}
			}
	}

## The member's docs, sorted by slug (a folder not there holds none).
## `Failed` when it would not list.
load_docs! : Uid => Try(List({ slug : Str, path : Paths.ChatPath }), [Failed])
load_docs! = |me|
	match Files.list!(Paths.docs_folder(me)) {
		Ok(listed) => Ok(Paths.docs(me, listed.entries))
		Err(Missing) => Ok([])
		Err(Failed) => Err(Failed)
	}

## **THE DOC TOUCHED LAST** (mostRecentDocSlug), the landing's 303, a
## reading list just saved among them; with none, the editor with nothing
## open.
docs_landing! : Uid => Chat.Answer
docs_landing! = |me|
	match load_docs!(me) {
		Err(Failed) => Chat.answered
		Ok(docs) =>
			match last_touched!(docs, Err(None)) {
				Err(Failed) => Chat.answered
				Ok(Ok(last)) => Chat.redirect("/chat/docs/${last.slug}".to_utf8())
				Ok(Err(None)) => docs_page!(sorted_slugs(docs), Nothing)
			}
	}

## Of `docs`, sorted by slug, the one changed last, the first by name of
## a tie (a folder's order differs by machine), against `best` so far; one
## gone since the listing is passed over.
last_touched! : List({ slug : Str, path : Paths.ChatPath }),
Try({ slug : Str, mtime : I64 }, [None]) => Try(
	Try({ slug : Str, mtime : I64 }, [None]),
	[Failed],
)
last_touched! = |docs, best|
	match docs {
		[] => Ok(best)
		[doc, .. as more] =>
			match Files.stat!(doc.path) {
				Err(Failed) => Err(Failed)
				Err(Missing) => last_touched!(more, best)
				Ok(st) =>
					match best {
						Ok(b) if b.mtime >= st.mtime => last_touched!(more, best)
						_ => last_touched!(more, Ok({ slug: doc.slug, mtime: st.mtime }))
					}
			}
	}

## The slugs of `docs`, sorted as load_docs! sorts them (listUserDocs' order).
sorted_slugs : List({ slug : Str, path : Paths.ChatPath }) -> List(Str)
sorted_slugs = |docs| List.map(docs, |d| d.slug)

## docsList: the member's docs as JSON, for an API client.
docs_list! : Uid => Chat.Answer
docs_list! = |me|
	match load_docs!(me) {
		Err(Failed) => Chat.answered
		Ok(docs) => Chat.respond(
			200,
			json,
			Docs.list_json(me.to_str(), sorted_slugs(docs)),
		)
	}

## serveRawDoc: a doc's markdown as stored. **AN ERROR IS NOT "NO SUCH
## DOC"** (metal-vmm QUEUE 114): a name no slug is the Zig's 500, saying so.
raw_doc! : Uid, Str => Chat.Answer
raw_doc! = |me, slug|
	match Paths.doc_path(me, slug) {
		Err(NotASlug) => Chat.respond(
			500,
			[],
			"The doc cannot be read: InvalidDocSlug.\n".to_utf8(),
		)
		Ok(path) =>
			match Files.read_bytes!(path) {
				Ok(bytes) => Chat.respond(
					200,
					"text/markdown; charset=utf-8".to_utf8(),
					bytes,
				)
				Err(Missing) => Chat.not_found
				Err(Failed) => Chat.answered
			}
	}

## renderDocsEditor: the editor with `slug` open; one no slug, or not
## among the member's docs, is back to the bare editor (303).
docs_editor! : Uid, Str => Chat.Answer
docs_editor! = |me, slug|
	match load_docs!(me) {
		Err(Failed) => Chat.answered
		Ok(docs) => {
			slugs = sorted_slugs(docs)
			if slug == "" {
				docs_page!(slugs, Nothing)
			} else {
				match (Paths.doc_path(me, slug), slugs.contains(slug)) {
					(Ok(path), Bool.True) => open_doc!(
						slugs,
						slug,
						path,
					)
					_ => Chat.redirect("/chat/docs".to_utf8())
				}
			}
		}
	}

## The editor with the doc at `path` open: its markdown (a doc gone since
## the listing is empty) and that rendered, the preview's first paint.
open_doc! : List(Str), Str, Paths.ChatPath => Chat.Answer
open_doc! = |
	slugs,
	slug,
	path,
| {
	stored = match Files.read_bytes!(path) {
		Ok(bytes) => Ok(bytes)
		Err(Missing) => Ok([])
		Err(Failed) => Err(Failed)
	}
	match stored {
		Err(Failed) => Chat.answered
		Ok(markdown) => {
			rendered = Host.render!(markdown)
			match rendered.status {
				Failed => Chat.answered
				Rendered => docs_page!(
					slugs,
					Doc({
						slug,
						markdown,
						rendered: Chrome.rendered(rendered.html),
					}),
				)
			}
		}
	}
}

## The docs page for the member, `open` among their `slugs`.
docs_page! : List(Str), Docs.Open => Chat.Answer
docs_page! = |slugs, open|
	match load_viewer!(Unasked) {
		Err(Failed) => Chat.answered
		Ok(viewer) => Chat.respond(
			200,
			html,
			Docs.editor({
				src: Chrome.src_in(Host.srcs!({})),
				viewer,
				slugs,
				open,
			}).bytes(),
		)
	}

## **A MEMBER'S OWN STREAM** (metal-vmm QUEUE 286): their feed, their
## notifications or their sidebar, on the bus key `key` makes of their uid,
## live only (the page is the backlog). A GET's, as every stream is.
member_stream! : Chat.Request, (Uid -> BusKey) => Chat.Answer
member_stream! = |req, key|
	if req.method != Get {
		Chat.not_allowed(Get)
	} else {
		match load_uid!({}) {
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
				create_topic!(
					req,
					route,
					key,
				)
			} else if route.tail == Send or route.tail == InvalidSend {
				send!(
					req,
					route,
					key,
				)
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
											route,
											{
												key,
												conv,
												who,
												title: Conversation.topic_title(t, route.topic),
												topics,
											},
										)
									} else {
										# **A TOPIC THAT IS NOT THERE IS A 404 THAT SAYS SO**
										# (metal-vmm QUEUE 156(j)).
										not_found_page!(
											who,
											"There is no topic \u(201C)${route.topic}\u(201D) in this conversation.",
											key.base(),
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
	match load_uid!({}) {
		Err(Failed) => Chat.answered
		Ok(me) =>
			match Files.read_bytes!(Paths.reading_list_path(me)) {
				Ok(text) => {
					ids = Saved.ids(
						text,
						route.key.to_utf8(),
						route.topic.to_utf8(),
					)
					# An id is ASCII by its rule (Paths.is_valid_msg_ref_id).
					Chat.respond(
						200,
						json,
						JsonOut.array(
							List.map(
								ids,
								|id| JsonOut.string(Str.from_utf8_lossy(id)),
							),
						).bytes(),
					)
				}
				Err(Missing) => Chat.respond(
					200,
					json,
					Str.to_utf8("[]"),
				)
				Err(Failed) => Chat.answered
			}
	}

## **HOW MANY MESSAGES A TOPIC HOLDS** (chat_count.messageCount, metal-vmm
## QUEUE 275): the N that numbers the next one. **THE SIDECAR IS A CACHE;
## THE TRANSCRIPT IS THE TRUTH**: the `.count` is believed only when the
## transcript is still the size it was taken at (one stat), else the
## transcript is read and its blocks counted (Count.count_blocks): a sidecar
## whose read failed among them, a miss (metal-vmm QUEUE 284). No
## transcript is no messages; one that will not be looked at or read fails
## the request, never 0, which would number the next message onto the last.
## The Roc only reads the sidecar; the host writes it with every message.
count_messages! : Paths.TopicAt => Try(U64, [Failed])
count_messages! = |at| {
	transcript = Paths.transcript_path(at)
	match Files.stat!(transcript) {
		Err(Missing) => Ok(0)
		Err(Failed) => Err(Failed)
		Ok({ size, mtime: _ }) =>
			match believed_count!(at, size) {
				Ok(n) => Ok(n)
				Err(Recount) =>
					match Files.read_bytes!(transcript) {
						Ok(raw) => Ok(Count.count_blocks(raw))
						# Gone since the stat: no messages.
						Err(Missing) => Ok(0)
						Err(Failed) => Err(Failed)
					}
			}
	}
}

## The sidecar's count when it was taken at `size` (readCount, then
## believedCount, Last.sidecar!): a sidecar missing, past readCount's 1 KiB,
## that does not parse, or whose read failed (metal-vmm QUEUE 284) is a
## recount.
believed_count! : Paths.TopicAt, U64 => Try(U64, [Recount])
believed_count! = |at, size|
	Count.believed(Last.sidecar!(at), size).map_err(|_| Recount)

## A topic's page, or its raw transcript: a read, then the work.
serve_page_or_raw! : Chat.Request, Route.R, AtTopic => Chat.Answer
serve_page_or_raw! = |
	req,
	route,
	found,
|
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

## **AN UPLOAD'S POST** (chat_upload `handleUpload`, metal-vmm QUEUE 292):
## the form read and its file's type sniffed by the host, which holds the
## bytes; then here, in the Zig's order, a type the chat takes not, a file
## past its kind's cap, the member's allowance, the file stored, and the
## answer the compose box reads.
post_upload! : Chat.Request, Route.R, AtTopic => Chat.Answer
post_upload! = |
	req,
	route,
	found,
|
	if req.method != Post {
		Chat.not_allowed(Post)
	} else {
		form = Host.read_upload!({})
		match form.status {
			Answered => Chat.answered
			NoFile => {
				Host.refuse_upload!(Malformed, "no file\n".to_utf8())
				Chat.answered
			}
			Unsupported => Chat.respond(
				415,
				[],
				Upload.unsupported.to_utf8(),
			)
			Read =>
				match Upload.kind_of(form.ext) {
					Err(NotTaken) => crash "post_upload!: the host sniffed a type not taken"
					Ok(kind) =>
						if form.size > kind.cap {
							Host.refuse_upload!(
								TooLarge,
								Upload.too_large({ noun: kind.noun, cap: kind.cap }).to_utf8(),
							)
							Chat.answered
						} else {
							keep_upload!(
								form,
								kind.name,
								{ key: found.key, topic: route.topic },
							)
						}
				}
		}
	}

## The allowance spent on the file, then the file stored and its answer.
keep_upload! : {
	size : U64,
	ext : List(U8),
	filename : List(U8),
	status : _,
},
Str,
Paths.TopicAt => Chat.Answer
keep_upload! = |
	form,
	kind,
	at,
|
	match Host.reserve_upload!(form.size) {
		Failed => Chat.answered
		Refused => Chat.respond(
			403,
			[],
			Upload.allowance_spent.to_utf8(),
		)
		Reserved => {
			stored = Host.store_upload!(Paths.uploads_folder(at).bytes(), form.ext)
			name = Str.from_utf8_lossy(stored.name)
			match stored.status {
				Failed => Chat.answered
				Stored => Chat.respond(
					200,
					json,
					Upload.stored_answer({
						url: "${Paths.ConvKey.base(at.key)}/${at.topic}/uploads/${name}",
						filename: form.filename,
						kind,
					}),
				)
			}
		}
	}

## **AN UPLOAD SERVED** (chat_upload `serveUpload`, metal-vmm QUEUE 291):
## a GET's or a HEAD's, of a name an upload has, typed by it; whole, or the
## range asked for, or the 416 for one that cannot be. The host serves the
## bytes (Host.serve_upload!).
serve_upload! : Chat.Request, Route.R, AtTopic => Chat.Answer
serve_upload! = |
	req,
	route,
	found,
|
	if req.method != Get and req.method != Head {
		Chat.not_allowed(Get)
	} else {
		match Upload.content_type(route.rest) {
			Err(NotAnUpload) => Chat.not_found
			Ok(content_type) => {
				path = Paths.upload_path({ key: found.key, topic: route.topic }, route.rest)
				match Files.stat!(path) {
					Err(Missing) => Chat.not_found
					Err(Failed) => Chat.answered
					Ok(st) => {
						part = match Host.read_header!("range".to_utf8()) {
							[] => Whole({ first: 0, last: 0 })
							[asked, ..] =>
								match Upload.range(asked, st.size) {
									Ok(r) => Range(r)
									Err(Unsatisfiable) => Unsatisfiable({ first: 0, last: 0 })
								}
						}
						(kind, r) = match part {
							Whole(at) => (Whole, at)
							Range(at) => (Range, at)
							Unsatisfiable(at) => (Unsatisfiable, at)
						}
						served = Host.serve_upload!({
							first: r.first,
							last: r.last,
							size: st.size,
							content_type: content_type.to_utf8(),
							path: path.bytes(),
							part: kind,
						})
						match served {
							Served => Chat.answered
							# Gone since its stat: nothing was answered.
							Gone => Chat.not_found
						}
					}
				}
			}
		}
	}

## **A TOPIC'S BUNDLE** (chat_download `serveBundle`, metal-vmm QUEUE 291):
## its transcript, its reactions when anyone reacted, and every upload (a
## folder in the uploads passed over), named under the topic, then served
## as `<topic>.tar.gz`. A topic with no transcript is a 404; anything else
## that will not read fails the download: the whole topic or nothing.
serve_download! : Chat.Request, Route.R, AtTopic => Chat.Answer
serve_download! = |
	req,
	route,
	found,
|
	if req.method != Get and req.method != Head {
		Chat.not_allowed(Get)
	} else {
		at = { key: found.key, topic: route.topic }
		sid = route.topic
		md = Paths.transcript_path(at)
		match Files.stat!(md) {
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
	with_reactions = match Files.stat!(reactions) {
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
serve_topic! : Chat.Request, Route.R, AtTopic => Chat.Answer
serve_topic! = |
	req,
	route,
	found,
| {
	who = found.who
	match route.tail {
		# An upload and the bundle (metal-vmm QUEUE 291): the Roc decides,
		# the host serves the bytes.
		Uploads => serve_upload!(
			req,
			route,
			found,
		)
		Download => serve_download!(
			req,
			route,
			found,
		)
		Upload => post_upload!(
			req,
			route,
			found,
		)
		# The topic's stream (metal-vmm QUEUE 286): its key and transcript
		# the Roc's, the backlog's replay and the live stream the host's.
		Stream =>
			if req.method != Get {
				Chat.not_allowed(Get)
			} else {
				at = { key: found.key, topic: route.topic }
				Chat.topic_stream(
					BusKey.topic(at).bytes(),
					Paths.transcript_path(at).bytes(),
					route.topic.to_utf8(),
				)
			}
		Saved =>
			if req.method != Get and req.method != Head {
				Chat.not_allowed(Get)
			} else {
				serve_saved!(route)
			}
		Invalid => Chat.not_found
		Page | Raw => serve_page_or_raw!(
			req,
			route,
			found,
		)
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
					Ok(bytes) => Chat.respond(
						200,
						ndjson,
						bytes,
					)
					Err(Missing) => Chat.respond(
						200,
						ndjson,
						[],
					)
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
					route.topic,
					if route.tail == Pin Pinned else Unpinned,
				) {
					Ok({}) => Chat.respond(
						204,
						[],
						[],
					)
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
	me = load_uid!({})?
	match key {
		Dm(pair) =>
			match Conversation.dm_other(pair, me) {
				Ok(other) =>
					match load_accounts!(Unasked) {
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

## **THE ACCOUNTS ARE ASKED OF THE HOST AT MOST ONCE A REQUEST**
## (Host.list_accounts! lists every one, two reads each): `Known` once asked,
## handed down to whatever looks one up next; `Unasked` until a route first
## needs them.
Who : [Known(List(Accounts.Account)), Unasked]

## The accounts: those already asked, or the host's now. `Failed` when they
## could not be listed: the request has failed, and no lookup is made on
## nothing. An account that would not read is among them, and fails the
## request only when a lookup needs it (`fail_if_unreadable!`): never "no such account".
load_accounts! : Who => Try(List(Accounts.Account), [Failed])
load_accounts! = |who|
	match who {
		Known(all) => Ok(all)
		Unasked => {
			got = Host.list_accounts!({})
			match got.status {
				# **EACH ID AND NAME DECODED HERE, AT THE DOOR**
				# (Accounts.from_host): one that is no uid fails the request
				# (NotAUid, about the account); a name that is not UTF-8 is
				# that account's alone, listed as unreadable.
				Found =>
					match List.map_try(got.accounts, Accounts.from_host) {
						Ok(all) => Ok(all)
						Err(NotAUid(bad)) => {
							Host.fail!(NotAUid, bad)
							Err(Failed)
						}
					}
				Failed => Err(Failed)
			}
		}
	}

## The member's name (getUserName of their own id), from the accounts.
## `Failed` when it would not read (the request has failed with its error).
load_viewer! : Who => Try(Str, [Failed])
load_viewer! = |who| {
	me = load_uid!({})?
	match load_accounts!(who) {
		Ok(all) => fail_if_unreadable!(Accounts.name(all, me))
		Err(Failed) => Err(Failed)
	}
}

## **THE MEMBER'S ID, DECODED WHERE THE HOST HANDS IT** (Host.me!): a
## session is signed only for an id a counter made, so one that is no
## canonical uid fails the request (NotAUid, about the id), and `Failed`.
load_uid! : {} => Try(Uid, [Failed])
load_uid! = |{}| {
	bytes = Host.me!({})
	match Uid.from_utf8(bytes) {
		Ok(uid) => Ok(uid)
		Err(NotAUid) => {
			Host.fail!(NotAUid, bytes)
			Err(Failed)
		}
	}
}

## A lookup's answer, or, when it needed an account's read that failed, the
## request failed with that read's error (`fail_unreadable!`) and `Failed`.
fail_if_unreadable! : Try(a, Accounts.Unreadable) => Try(a, [Failed])
fail_if_unreadable! = |looked|
	match looked {
		Ok(answer) => Ok(answer)
		Err(why) => {
			fail_unreadable!(why)
			Err(Failed)
		}
	}

## **THE REQUEST FAILS WITH THE ACCOUNT'S OWN ERROR**: a lookup needed
## account `id`'s kind or name, which `load_accounts!` listed as unreadable, so
## the host fails the request with the error that read failed with, as the
## Zig's own read of it did.
fail_unreadable! : Accounts.Unreadable => {}
fail_unreadable! = |why|
	match why {
		KindUnreadable(id) => Host.fail!(KindUnreadable, id.to_str().to_utf8())
		NameUnreadable(id) => Host.fail!(NameUnreadable, id.to_str().to_utf8())
	}

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
			load_rosters_from!(
				Paths.channel_names(listed.entries),
				0,
				[],
			)
		}
		Err(Missing) => Ok([])
		Err(Failed) => Err(Failed)
	}
}

load_rosters_from! : List(Str), U64, List(Paths.Roster) => Try(List(Paths.Roster), [Failed])
load_rosters_from! = |
	names,
	i,
	out,
|
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
							i + 1,
							List.append(out, r),
						)
						Malformed => {
							Host.count_malformed_channel!(name.to_utf8())
							load_rosters_from!(
								names,
								i + 1,
								out,
							)
						}
						Gone => load_rosters_from!(
							names,
							i + 1,
							out,
						)
						Failed => Err(Failed)
					}
				}
				Err(Invalid) => {
					Host.count_malformed_channel!(name.to_utf8())
					load_rosters_from!(
						names,
						i + 1,
						out,
					)
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
			match load_accounts!(who) {
				Ok(all) => {
					other = pair.partner(load_uid!({})?)
					match fail_if_unreadable!(Accounts.name(all, other)) {
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
pin! : Paths.ConvKey, Str, ChatState.Pin => Try({}, [Failed])
pin! = |
	key,
	topic,
	pin,
| {
	path = Paths.pinned_path(load_uid!({})?, key)
	match Files.read!(path) {
		Ok(stored) => write_pins!(
			path,
			stored,
			topic,
			pin,
		)
		Err(Missing) => write_pins!(
			path,
			"",
			topic,
			pin,
		)
		Err(Failed) => Err(Failed)
	}
}

## The pinned file at `path`, read as `stored`, with `topic` pinned or
## unpinned: written back, or, emptied, removed.
write_pins! : Paths.ChatPath, Str, Str, ChatState.Pin => Try({}, [Failed])
write_pins! = |
	path,
	stored,
	topic,
	pin,
|
	match ChatState.pinned(
		stored,
		topic,
		pin,
	) {
		Write(bytes) => Files.write!(path, bytes)
		Remove => Files.remove!(path)
	}

## **WHERE THE MEMBER RESUMES DM `conv`: TOPIC `topic`** (setLastViewedTopic):
## the topic last viewed there first, then the DM last in, each written
## only when it changed (ChatState.is_changed); `Failed` when a step failed,
## and nothing after it is written. A topic with no name records nothing.
bookmark! : Paths.ConvKey, Str => Try({}, [Failed])
bookmark! = |key, topic| {
	me = load_uid!({})?
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
			Bad(why) => Chat.respond(
				400,
				[],
				why,
			)
			Reacted(r) =>
				match store_reaction!(
					who,
					at,
					r,
				) {
					Stored => Chat.respond(
						204,
						[],
						[],
					)
					NoSuchMessage => Chat.respond(
						400,
						[],
						Str.to_utf8("react: no such message\n"),
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
	match (load_viewer!(who), load_uid!({})) {
		(Ok(name), Ok(uid)) => {
			match count_messages!(topic_at) {
				Err(Failed) => Failed
				Ok(count) =>
				# Message numbers start at 1 (the N of MSG_<topic>_N).
					if r.msg == 0 or r.msg > count {
						NoSuchMessage
					} else {
						at = Time.rfc3339(Host.now!({}))
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
html = Str.to_utf8("text/html; charset=utf-8")

## /chat/links, by any method, as the Zig had it: the member's own, or the
## stub; nothing below it.
serve_links! : List(U8) => Chat.Answer
serve_links! = |rest|
	if rest != [] {
		Chat.not_found
	} else {
		match (load_viewer!(Unasked), load_uid!({})) {
			(Err(Failed), _) | (Ok(_), Err(Failed)) => Chat.answered
			(Ok(viewer), Ok(me)) => {
				src = Chrome.src_in(Host.srcs!({}))
				match Files.serve_rendered!(Paths.links_path(me)) {
					Serving => {
						(before, after) = Pages.links_around(src, viewer)
						Chat.served_html(before, after)
					}
					NotServing => Chat.respond(
						200,
						html,
						Pages.links(
							src,
							viewer,
							NoLinks,
						).bytes(),
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
					html,
					Pages.recent(
						Chrome.src_in(Host.srcs!({})),
						{ viewer, json: Recent.json(me, got.rows) },
					).bytes(),
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
	me = load_uid!({})?
	accounts = load_accounts!(Unasked)?
	viewer = fail_if_unreadable!(Accounts.name(accounts, me))?
	roster = fail_if_unreadable!(Accounts.roster_named(accounts))?
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
				match Last.of!(at, accounts)? {
					Some(last) =>
						match (
							Time.unix_from_rfc3339(last.at),
							author_name(
								me,
								accounts,
								last.uid,
							),
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
				label: Recent.doc_title(doc.slug).to_utf8(),
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
	match Files.stat!(path) {
		Ok(st) => Ok([{ ..row, secs: secs_text(if st.mtime % 2 == 0 st.mtime else st.mtime - 1) }])
		Err(Missing) => Ok([])
		Err(Failed) => Err(Failed)
	}

## authorName: the last author's name, read only for someone other than the
## viewer ("" for the viewer, whom the page calls "You", and for nobody:
## an empty Who cell, never an older author). An id that is no uid names
## no account, so no name.
author_name : Uid, List(Accounts.Account), List(U8) -> Try(Str, [Unreadable])
author_name = |
	me,
	accounts,
	uid,
|
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
		match (load_viewer!(Unasked), load_uid!({})) {
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
				src = Chrome.src_in(Host.srcs!({}))
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
				Chat.respond(
					200,
					html,
					page.bytes(),
				)
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
						match load_viewer!(who) {
							Ok(viewer) => Chat.respond(
								200,
								html,
								Pages.no_topics(
									Chrome.src_in(Host.srcs!({})),
									{
										viewer,
										base: key.base(),
										title,
									},
								).bytes(),
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
					html,
					Pages.conversation(
						Chrome.src_in(Host.srcs!({})),
						Limits.page,
						view,
					).bytes(),
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
	uid = load_uid!({})?
	match load_accounts!(at.who) {
		Err(Failed) => Err(Failed)
		Ok(all) =>
			match fail_if_unreadable!(Accounts.name(all, uid)) {
				Err(Failed) => Err(Failed)
				Ok(viewer) =>
					match fail_if_unreadable!(Accounts.authorized(all)) {
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
json = Str.to_utf8("application/json; charset=utf-8")

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
	_ = Host.aside!(Begin)
	got = seed_welcome!({})
	match (Host.aside!(End), got) {
		(Done, Ok(who)) => who
		_ => Unasked
	}
}

## The host's hello in the DM `key`, and the member's bookmark at it.
hello! : List(Accounts.Account), Uid, Paths.ConvKey => Try({}, [Failed])
hello! = |
	accounts,
	host,
	key,
| {
	name = fail_if_unreadable!(Accounts.name(accounts, host))?
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
		Known(accounts),
		host,
		{
			at: { key, topic: "general" },
			name,
			markdown: text,
			cid: "",
		},
	)?
	bookmark!(key, "general")
}

seed_welcome! : {} => Try(Who, [Failed])
seed_welcome! = |{}| {
	me = load_uid!({})?
	match Host.welcome_pending!({}) {
		Failed => Err(Failed)
		None => Ok(Unasked)
		Pending => {
			accounts = load_accounts!(Unasked)?
			match List.keep_if(accounts, |a| a.id.to_str() == "1") {
				[host, ..] if host.id != me => {
					pair = Paths.pair_key(host.id, me)
					key = Dm(pair)
					if Paths.first_of(load_topics!(key)).is_empty() {
						hello!(
							accounts,
							host.id,
							key,
						)?
					}
					Host.welcome_done!({})?
					Ok(Known(accounts))
				}
				[_, ..] => {
					Host.welcome_done!({})?
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
	match load_uid!({}) {
		Err(Failed) => Chat.answered
		Ok(me) => {
			conv = ChatState.bookmark(Files.read!(Paths.last_conv_path(me)))
			match Paths.pair_key_from_str(conv) {
				Ok(pair) if pair.is_participant(me) => {
					topics = load_topics!(Dm(pair))
					if Paths.first_of(topics).is_empty() {
						Chat.redirect("/chat/c/${conv}".to_utf8())
					} else {
						Chat.redirect("/chat/c/${conv}/${resume_at!(me, pair, topics)}".to_utf8())
					}
				}
				_ =>
					match load_viewer!(who) {
						Ok(viewer) => Chat.respond(
							200,
							html,
							Pages.no_conversations(Chrome.src_in(Host.srcs!({})), viewer).bytes(),
						)
						Err(Failed) => Chat.answered
					}
			}
		}
	}

## Where member `me` resumes DM `conv`, whose topics are `topics`: the
## choice ChatState's, the last-viewed topic and the clock the host's.
resume_at! : Uid, Paths.PairKey, List(Str) => Str
resume_at! = |
	me,
	pair,
	topics,
| {
	last = ChatState.bookmark(Files.read!(Paths.last_session_path(me, Dm(pair))))
	ChatState.resume_topic(
		topics,
		last,
		Host.now!({}),
	)
}

## /chat/conversations: a DM with every other member, where the member
## resumes it, and its topics.
serve_conversations! : {} => Chat.Answer
serve_conversations! = |{}|
	match (load_roster!({}), load_uid!({})) {
		(Ok(members), Ok(me)) => Chat.respond(
			200,
			json,
			Topics.conversations_json(
				me,
				load_dm_entries!(
					me,
					members,
					0,
					[],
				),
			),
		)
		(Err(Failed), _) | (Ok(_), Err(Failed)) => Chat.answered
	}

## The authorized roster (listAuthorized), from the accounts. `Failed` when
## the accounts could not be listed, or one the roster reads would not read
## (the request has failed with its error).
load_roster! : {} => Try(List({ id : Uid, name : Str }), [Failed])
load_roster! = |{}|
	match load_accounts!(Unasked) {
		Ok(all) => fail_if_unreadable!(Accounts.authorized(all))
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
List(Topics.Entry) => List(Topics.Entry)
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
				default = resume_at!(
					me,
					pair,
					listed,
				)
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
		topic = match Paths.cut_last(id, '_') {
			Ok((before, _)) => before
			Err(NoSeparator) => []
		}
		at = |base, key| List.join([
			Str.to_utf8(base),
			key,
			['/'],
			topic,
			Str.to_utf8("#msg-"),
			id,
		])
		match (load_uid!({}), load_roster!({})) {
			(Err(Failed), _) | (Ok(_), Err(Failed)) => Chat.answered
			(Ok(me), Ok(members)) =>
				match find_dm!(
					me,
					members,
					topic,
					0,
				) {
					Ok(conv) => Chat.found(at("/chat/c/", conv))
					Err(NoSuchTopic) =>
						match load_channel_rosters!({}) {
							Err(Failed) => Chat.answered
							Ok(rosters) =>
								match find_channel!(
									Paths.member_channels(rosters, me),
									topic,
									0,
								) {
									Ok(name) => Chat.found(at("/channel/", name))
									Err(NoSuchTopic) => Chat.not_found
								}
						}
				}
		}
	}

find_dm! : Uid, List({ id : Uid, name : Str }), List(U8), U64 => Try(List(U8), [NoSuchTopic])
find_dm! = |
	me,
	members,
	topic,
	i,
|
	match List.get(members, i) {
		Ok({ id, name: _ }) =>
			if id == me {
				find_dm!(
					me,
					members,
					topic,
					i + 1,
				)
			} else {
				pair = Paths.pair_key(me, id)
				if List.contains(
					List.map(load_topics!(Dm(pair)), Str.to_utf8),
					topic,
				) Ok(pair.bytes()) else find_dm!(
					me,
					members,
					topic,
					i + 1,
				)
			}
		Err(_) => Err(NoSuchTopic)
	}

find_channel! : List(Str), List(U8), U64 => Try(List(U8), [NoSuchTopic])
find_channel! = |
	names,
	topic,
	i,
|
	match List.get(names, i) {
		Ok(name) =>
			match Paths.channel_name_from_str(name) {
				Ok(valid) =>
					if List.contains(List.map(load_topics!(Channel(valid)), Str.to_utf8), topic) {
						Ok(name.to_utf8())
					} else {
						find_channel!(
							names,
							topic,
							i + 1,
						)
					}
				# Every name here passed channel_name_from_str already
				# (load_rosters_from! keeps no other).
				Err(Invalid) => crash "find_channel!: a kept roster's name is no channel name"
			}
		Err(_) => Err(NoSuchTopic)
	}

## POST <base>/new: a topic made with a first "hi", a DM's announced in its
## highest general<N>; the conversation and topic as JSON.
create_topic! : Chat.Request, Route.R, Paths.ConvKey => Chat.Answer
create_topic! = |
	req,
	route,
	key,
|
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
							conv,
							who,
							ZigText.trim_str(raw),
						)
						Missing => make_topic!(
							key,
							conv,
							who,
							"",
						)
					}
				}
			}
		Err(NotYours) => not_yours!(route)
		Err(Failed) => Chat.answered
	}

make_topic! : Paths.ConvKey, Chat.Conv, Who, Str => Chat.Answer
make_topic! = |
	key,
	conv,
	who,
	topic,
| {
	if !Paths.is_topic_id(topic) {
		Chat.respond(
			400,
			[],
			Str.to_utf8("Topic must be letters, digits, and hyphens only — no spaces, underscores, or punctuation.\n"),
		)
	} else if Topics.is_same_name(topic, "new") {
		Chat.respond(
			400,
			[],
			Str.to_utf8("\"new\" is reserved — pick another topic name.\n"),
		)
	} else if Conversation.has_topic(load_topics!(key), topic) {
		Chat.respond(
			409,
			[],
			Str.to_utf8("That topic already exists.\n"),
		)
	} else {
		match load_viewer!(who) {
			Err(Failed) => Chat.answered
			Ok(name) => {
				dm = conv.family == Dm
				# The bookmark first, as a send's: one that fails makes no topic.
				if dm and bookmark!(key, topic).is_err() {
					Chat.answered
				} else if append_message!(
					conv,
					who,
					{
						at: { key, topic },
						name,
						markdown: "hi",
						cid: "",
					},
				).is_err() {
					Chat.answered
				} else {
					# **STORED IS DONE** (metal-vmm QUEUE 267): the topic is
					# made once its "hi" is stored, so the announcement is an
					# aside, best-effort, counted when it fails, never a 500
					# whose retry is a 409.
					if dm {
						_ = Host.aside!(Begin)
						_ = announce!(
							key,
							conv,
							who,
							topic,
							name,
						)
						match Host.aside!(End) {
							Done => {}
							Failed => Host.count_dropped!(Announcement, topic.to_utf8())
						}
					} else {
						{}
					}
					Chat.respond(
						200,
						json,
						Topics.made_json({ key, topic }),
					)
				}
			}
		}
	}
}

## A DM's new topic, said where the partner already watches: its highest
## general<N>, unless that is the topic made.
announce! : Paths.ConvKey, Chat.Conv, Who, Str, Str => Try({}, [Failed])
announce! = |
	key,
	conv,
	who,
	topic,
	name,
|
	match Topics.highest_general(load_topics!(key)) {
		Ok(gen) if gen != topic =>
			append_message!(
				conv,
				who,
				{
					at: { key, topic: gen },
					name,
					markdown: "New topic: [${topic}](${key.base()}/${topic})",
					cid: "",
				},
			).map_ok(|_| {})
		_ => Ok({})
	}

## POST .../<topic>/send: docs/ROC-CHAT.md §6.2's steps, the store's append
## the host's. A send makes its topic, so no topic need be there; the
## conversation must be the member's.
send! : Chat.Request, Route.R, Paths.ConvKey => Chat.Answer
send! = |
	req,
	route,
	key,
|
	match find!(key) {
		Err(Failed) => Chat.answered
		Ok((conv, who)) =>
		# The title before any tail, unused, as the Zig's convRoute read
		# it: a partner whose name will not read fails a send too.
			match load_title!(key, who) {
				Err(Failed) => Chat.answered
				Ok(_) => receive_message!(
					req,
					route,
					{ key, topic: route.topic },
					conv,
					who,
				)
			}
		Err(NotYours) => not_yours!(route)
	}

## A send in `conv`, found and titled: the tail, the method, the header,
## the body, the form.
receive_message! : Chat.Request, Route.R, Paths.TopicAt, Chat.Conv, Who => Chat.Answer
receive_message! = |
	req,
	route,
	at,
	conv,
	who,
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
				Missing => refuse("not sent: no message (the form has no markdown field)\n")
				Found(md) =>
					match Form.field(body.bytes, "cid") {
						Malformed => Chat.malformed
						Found(cid) => store!(
							at,
							conv,
							who,
							send,
							{ markdown: md, cid },
						)
						Missing => store!(
							at,
							conv,
							who,
							send,
							{ markdown: md, cid: "" },
						)
					}
			}
		}
	}

refuse : Str -> Chat.Answer
refuse = |why| Chat.respond(
	400,
	[],
	Str.to_utf8(why),
)

## What the send form carried: the message's `markdown` and the sender's
## client id `cid`. Named fields because both are text. It becomes
## a Draft once the message is judged and its author's name read.
Posted : { markdown : Str, cid : Str }

## The message judged, then stored: empty or hostile is refused (one that
## is not UTF-8 text the form refused); the bookmark (a DM's) before the
## store, so one that fails stores nothing; then 204 for an async sender,
## else back to the topic.
store! : Paths.TopicAt, Chat.Conv, Who, [Async, Sync], Posted => Chat.Answer
store! = |
	at,
	conv,
	who,
	send,
	{ markdown: md, cid },
|
	if ZigText.trim(md.to_utf8()) == [] {
		refuse("not sent: the message is empty\n")
	} else if Host.check_hostile!(
		md.to_utf8(),
		Str.to_utf8("not sent: malformed markdown — too much formatting; break it into smaller messages\n"),
	) != Fine {
		Chat.answered
	} else {
		match load_viewer!(who) {
			Err(Failed) => Chat.answered
			Ok(name) =>
				if conv.family == Dm and bookmark!(at.key, at.topic).is_err() {
					Chat.answered
				} else if append_message!(
					conv,
					who,
					{
						at,
						name,
						markdown: md,
						cid,
					},
				).is_err() {
					Chat.answered
				} else if send == Async {
					Chat.respond(
						204,
						[],
						[],
					)
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
			json,
			search_error("too many searches; wait a second"),
		)
	} else {
		match Form.value(List.first(Host.read_query!(Str.to_utf8("prefix"))) ?? []) {
			Err(BadEscape) => Chat.malformed
			Ok(typed) => {
				key = Search.key(typed)
				got = Host.search_words!(key, if key == [] 0 else Search.most_words)
				match got.status {
					Ready => Chat.respond(
						200,
						json,
						Search.words_json(
							key,
							got.unreadable,
							got.words,
						),
					)
					NotReady => Chat.respond(
						503,
						json,
						search_error("search is not ready"),
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
			json,
			search_error("too many searches; wait a second"),
		)
	} else {
		match Form.value(List.first(Host.read_query!(Str.to_utf8("word"))) ?? []) {
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
						json,
						Search.messages_json(
							key,
							got.matched,
							got.unreadable,
							got.hits,
						),
					)
					NotReady => Chat.respond(
						503,
						json,
						search_error("search is not ready"),
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
	match load_uid!({}) {
		Err(Failed) => Chat.answered
		Ok(me) =>
			match Paths.doc_path(me, slug) {
				Err(NotASlug) => refuse("bad slug\n")
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
	if ZigText.trim(md.to_utf8()) == [] {
		refuse("doc is empty\n")
	} else if Host.check_hostile!(
		md.to_utf8(),
		Str.to_utf8("not posted: too much markdown formatting; break the doc up\n"),
	) != Fine {
		Chat.answered
	} else {
		match load_accounts!(Unasked) {
			Err(Failed) => Chat.answered
			Ok(accounts) =>
				match fail_if_unreadable!(Accounts.authorized(accounts)) {
					Err(Failed) => Chat.answered
					Ok(roster) =>
						match List.keep_if(
							roster,
							|u| u.id != me and u.id.to_str() == default_partner(me),
						) {
							[] => refuse("no default chat partner available\n")
							[partner, ..] => post_to!(
								me,
								Known(accounts),
								Paths.pair_key(me, partner.id),
								md,
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
post_to! : Uid, Who, Paths.PairKey, Str => Chat.Answer
post_to! = |
	me,
	who,
	pair,
	md,
| {
	key = Dm(pair)
	topic = resume_at!(
		me,
		pair,
		load_topics!(key),
	)
	bytes = key.bytes()
	conv = {
		family: Dm,
		key: bytes,
		base: Conversation.dm_base(bytes),
		members: Conversation.dm_members(bytes),
	}
	match load_viewer!(who) {
		Err(Failed) => Chat.answered
		Ok(name) =>
			match append_message!(
				conv,
				who,
				{
					at: { key, topic },
					name,
					markdown: md,
					cid: "",
				},
			) {
				Err(Failed) => Chat.answered
				Ok(id) => Chat.respond(
					200,
					json,
					JsonOut.object([
						("conv", JsonOut.string(pair.to_str())),
						("session", JsonOut.string(topic)),
						("id", JsonOut.string(id)),
					]).bytes(),
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
append_message! : Chat.Conv, Who, Draft => Try(Str, [Failed])
append_message! = |
	conv,
	who,
	draft,
| append_message_by!(
	conv,
	who,
	load_uid!({})?,
	draft,
)

## append_message!, by the member `me` (the request's, or the host's for
## the welcome DM).
append_message_by! : Chat.Conv, Who, Uid, Draft => Try(Str, [Failed])
append_message_by! = |
	conv,
	who,
	me,
	{
		at: topic_at,
		name,
		markdown: md,
		cid,
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
		match count_messages!(topic_at) {
			Ok(count) => {
				index = count
				# A count of the largest U64 has no next number: the call
				# crashes into a 500, storing nothing.
				id = "${topic}_${U64.to_str(index + 1)}"
				stamp = Time.rfc3339(Host.now!({}))
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
						named = if topic_at.key.kind() == Dm load_accounts!(who) else Ok([])
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
									{ conv, at: topic_at },
									block,
									index,
									stored,
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
## Where a block goes: its conversation, as the host takes it, and its topic.
BlockAt : { conv : Chat.Conv, at : Paths.TopicAt }

store_block! : BlockAt, List(U8), U64, Chat.Message => Try({}, [Failed])
store_block! = |
	{ conv, at },
	block,
	index,
	message,
| {
	appended = Host.append_message!(
		conv,
		at.topic.to_utf8(),
		block,
	)
	match appended.status {
		Failed => Err(Failed)
		Appended => {
			last = Known({
				offset: appended.size - List.len(block),
				uid: message.uid,
			})
			Files.write_cache!(
				Paths.count_path(at),
				Count.text(
					index + 1,
					appended.size,
					last,
				),
			)
			Host.index_message!(
				conv,
				at.topic.to_utf8(),
				message,
			)
			Ok({})
		}
	}
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
				Feed(f) => {
					got = Files.append_entry!(
						f.path,
						Feeds.sep,
						f.entry,
					)
					match got.status {
						Appended => Host.publish!(f.key.bytes(), f.event)
						Failed => Host.report_fanout_failure!(
							f.surface,
							f.member,
							at.key.bytes(),
							at.topic.to_utf8(),
							got.fault,
						)
					}
				}
			}
			fan_out!(at, rest)
		}
	}
