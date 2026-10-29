## **THE DOCS' READ PAGES** (angry-gopher docs.zig, metal-vmm QUEUE 289):
## the three-pane editor (the member's list, the open doc's textarea, its
## preview) and the list's JSON, each from what the host read. The chrome
## is Chrome.roc's.
import pf.Chat
import pf.Host
import Accounts
import BusKey
import Bytes
import ChatUrl
import Chrome
import Files
import Form
import Html
import JsonOut
import Limits
import Members
import Paths
import Time
import Uid
import ZigText
import Ascii

Docs := [].{

	## What the editor has open: no doc chosen yet, or the doc `slug`, its markdown
	## as stored and that markdown rendered (Chrome.rendered, the host's).
	Open : [
		NoneChosen,
		Doc(
			{
				slug : Str,
				markdown : List(U8),
				rendered : Html,
			},
		),
	]

	## renderDocsPage: the member's docs (`slugs`, sorted), `open` among
	## them, under the chrome `src` and `viewer` make.
	editor : {
		src : List(U8) -> Str,
		viewer : Str,
		slugs : List(Str),
		open : Open,
	} -> Html
	editor = |page| {
		shell = {
			tab: Html.trusted("Docs"),
			title: "Docs",
			viewer: page.viewer,
			active: "docs",
			src: page.src,
		}
		selected = match page.open {
			NoneChosen => ""
			Doc(d) => d.slug
		}
		Chrome.page(
			shell,
			Html.join([
				docs_css,
				Html.trusted("<div class=\"docs-notify chat-notify\" id=\"chat-notify\"></div>"),
				Html.trusted("<div class=\"docs-layout\">"),
				doc_list(page.slugs, selected),
				Html.trusted("<section class=\"docs-edit\">"),
				match page.open {
					NoneChosen =>
						if page.slugs.is_empty() {
							Html.join([
								Html.trusted("<p class=\"muted docs-hint\">"),
								Html.trusted("Create your first doc on the left"),
								Html.trusted(" to start writing.</p>"),
							])
						} else {
							Html.join([
								Html.trusted("<p class=\"muted docs-hint\">"),
								Html.trusted("Pick a doc on the left, or create a new one.</p>"),
							])
						}
					Doc(d) => Html.join([
						Html.trusted("<div class=\"docs-title-row\">"),
						Html.trusted("<span class=\"docs-title\">"),
						Html.text(Docs.title(d.slug)),
						Html.trusted("</span>"),
						Html.trusted("<button type=\"button\" id=\"docs-post-btn\""),
						Html.trusted(" class=\"docs-post-btn\">"),
						Html.trusted("Post to chat</button>"),
						Html.trusted("<span class=\"docs-status\" id=\"docs-status\">"),
						Html.trusted("</span></div>"),
						Html.tag({
							name: "textarea",
							attrs: [
								Attr("id", "docs-body"),
								Attr("data-slug", d.slug),
								Attr("spellcheck", "true"),
							],
							inner: Html.escape(d.markdown),
						}),
					])
				},
				Html.trusted("</section><section class=\"docs-preview\" id=\"docs-preview\">"),
				match page.open {
					NoneChosen => Html.trusted("")
					Doc(d) => d.rendered
				},
				Html.trusted("</section></div>"),
				match page.open {
					NoneChosen => Html.trusted("")
					Doc(_) => Html.join([
						Html.trusted("<dialog id=\"docs-posted-dialog\""),
						Html.trusted(" class=\"docs-alert-dialog\">"),
						Html.trusted("<p>Doc sent to chat.</p>"),
						Html.trusted("<button type=\"button\" id=\"docs-posted-ok\">"),
						Html.trusted("OK</button></dialog>"),
						Chrome.script(shell, "docs.js"),
					])
				},
				Chrome.script(shell, "notify.js"),
			]),
		)
	}

	## **A TITLE'S SLUG** (docs_store `slugifyTitle`): the title trimmed,
	## ASCII letters lowered, every run of anything else between them one
	## hyphen, none at either end; "untitled" for a title of no letter or
	## digit; cut to 80, then its end trimmed again.
	slug_of_title : Str -> Str
	slug_of_title = |title| {
		kept = List.fold(
			ZigText.trim_str(title).with_ascii_lowercased().to_utf8(),
			{ out: [], hyphen: Bool.False },
			|acc, c| {
				if Ascii.is_alphanumeric(c) {
					{ out: List.append(acc.out, c), hyphen: Bool.False }
				} else if acc.hyphen or acc.out.is_empty() {
					acc
				} else {
					{ out: List.append(acc.out, '-'), hyphen: Bool.True }
				}
			},
		)
		slug = Bytes.trim_end(kept.out, ['-'])
		short = if List.len(slug) > 80 Bytes.trim_end(List.take_first(slug, 80), ['-']) else slug
		match Str.from_utf8(short) {
			Ok("") => "untitled"
			Ok(s) => s
			Err(_) => crash "Docs.slug_of_title: ASCII bytes made no text"
		}
	}

	## **A MESSAGE SAVED FOR LATER** (reading_list `composeEntry`): the note
	## as a heading ("read later" when it is blank), who and when on one
	## line each, the way back to it, the message in a fence longer than any
	## in it, and a rule.
	reading_entry : {
		note : Str,
		from : Str,
		at : Str,
		url : Str,
		body : Str,
	} -> Str
	reading_entry = |e| {
		trimmed = ZigText.trim_str(e.note)
		note = if trimmed == "" "read later" else one_line(trimmed)
		fence = quote_fence(e.body)
		Str.join_with(
			[
				"### ${note}\n\n",
				"${one_line(e.from)} · ${one_line(e.at)} · [↩ open in chat](${e.url})\n\n",
				"${fence} quote\n${e.body}\n${fence}\n\n---\n\n",
			],
			"",
		)
	}

	## publishDocRecent's frame: the member's own recent feed told of a doc
	## made or saved at `at`.
	recent_frame : Str, Str -> List(U8)
	recent_frame = |at, slug|
		JsonOut.object([
			("kind", JsonOut.string("doc")),
			("at", JsonOut.string(at)),
			("who", JsonOut.string("You")),
			("slug", JsonOut.string(slug)),
			("title", JsonOut.string(Docs.title(slug))),
		]).bytes()

	## docsList: `{"me": uid, "docs": [{"slug", "title"}, ...]}`.
	list_json : Str, List(Str) -> List(U8)
	list_json = |me, slugs|
		JsonOut.object([
			("me", JsonOut.string(me)),
			(
				"docs",
				JsonOut.array(
					List.map(
						slugs,
						|slug| JsonOut.object([
							("slug", JsonOut.string(slug)),
							("title", JsonOut.string(Docs.title(slug))),
						]),
					),
				),
			),
		]).bytes()

	## docs_store `titleFromSlug`: hyphens to spaces, the first letter
	## upper-cased (a slug is ASCII: text in, text out).
	title : Str -> Str
	title = |slug| {
		spaced = List.map(slug.to_utf8(), |c| if c == '-' ' ' else c)
		titled = List.update(
			spaced,
			0,
			|c| if c >= 'a' and c <= 'z' c - 32 else c,
		) ?? spaced
		match Str.from_utf8(titled) {
			Ok(title) => title
			Err(_) => crash "Docs.title: an ASCII edit split a codepoint"
		}
	}

	## **THE MEMBER'S DOCS** (docs.zig `handle`, metal-vmm QUEUE 289, 290, 300):
	## the writes (a new doc, a save, a message saved to the reading list),
	## the live preview, then the read pages. Posting a doc to chat is the
	## chat's (main.roc `post_doc!`).
	docs! : Chat.Request, { rest : Str, accounts : List(Accounts.Account) } => Chat.Answer
	docs! = |req, { rest, accounts }|
		if rest == "/new" {
			new_doc!(req)
		} else if rest == "/save" {
			save_doc!(req)
		} else if rest == "/render" {
			preview_doc!(req)
		} else if rest == "/save_to_reading_list" {
			save_to_reading_list!(req)
		} else {
			docs_read!(req, { rest, accounts })
		}

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
		match Members.load_uid!({}) {
			Err(Failed) => Chat.answered
			Ok(me) =>
				match unused_slug!(me, Docs.slug_of_title(title)) {
					Err(Failed) => Chat.answered
					Ok(slug) =>
						match Paths.doc_path(me, slug) {
							# A slug of 80 suffixed past 80 (docPath's InvalidDocSlug).
							Err(NotASlug) => Chat.respond(
								500,
								{
									content_type: [],
									body: "The doc cannot be made: InvalidDocSlug.\n".to_utf8(),
								},
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
		suffixed_slug!(me, base)
	} else {
		match doc_there!(me, base) {
			Err(Failed) => Err(Failed)
			Ok(Free) => Ok(base)
			Ok(Taken) => suffixed_slug!(me, base)
		}
	}

## The first of `base-2` to `base-999` no doc has; past those, `base`.
suffixed_slug! : Uid, Str => Try(Str, [Failed])
suffixed_slug! = |me, base| suffixed_from!(me, { base, suffix: 2 })

## `base-n`, or the next, up to 999.
suffixed_from! : Uid, { base : Str, suffix : U64 } => Try(Str, [Failed])
suffixed_from! = |me, { base, suffix: n }|
	if n >= 1000 {
		Ok(base)
	} else {
		candidate = "${base}-${n.to_str()}"
		match doc_there!(me, candidate) {
			Err(Failed) => Err(Failed)
			Ok(Free) => Ok(candidate)
			Ok(Taken) => suffixed_from!(me, { base, suffix: n + 1 })
		}
	}

## docFileExists: whether the member has a doc `slug` (a name no slug
## names none).
doc_there! : Uid, Str => Try([Taken, Free], [Failed])
doc_there! = |me, slug|
	match Paths.doc_path(me, slug) {
		Err(NotASlug) => Ok(Free)
		Ok(path) =>
			match Files.read_stat!(path) {
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
	match Members.load_uid!({}) {
		Err(Failed) => Chat.answered
		Ok(me) =>
			match Paths.doc_path(me, slug) {
				Err(NotASlug) => Chat.refuse("bad slug\n")
				Ok(path) =>
					match Form.field(form, "body") {
						Malformed => Chat.malformed
						Missing => Chat.refuse("not saved: no body\n")
						Found(text) =>
							match Files.read_stat!(path) {
								Err(Missing) => Chat.respond(
									404,
									{ content_type: [], body: "no such doc\n".to_utf8() },
								)
								Err(Failed) => Chat.answered
								Ok(_) =>
									match Files.write!(path, text.to_utf8()) {
										Err(Failed) => Chat.answered
										Ok({}) => {
											doc_touched!(me, slug)
											Chat.respond(204, { content_type: [], body: [] })
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
		Rendered => Chat.respond(200, { content_type: Chat.html, body: rendered.html })
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
		Chat.refuse("missing field\n")
	} else {
		match Members.load_uid!({}) {
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
								{
									content_type: [],
									body: "not saved: the reading list is full\n".to_utf8(),
								},
							)
						} else {
							match Files.write!(path, List.concat(before, entry)) {
								Err(Failed) => Chat.answered
								Ok({}) => {
									doc_touched!(me, "reading-list")
									Chat.respond(204, { content_type: [], body: [] })
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
doc_touched! = |me, slug| {
	now = Time.rfc3339(Host.read_time!({}))
	Host.publish!(BusKey.recent(me).bytes(), Docs.recent_frame(now, slug))
}

## **THE DOCS' READ PAGES** (docs.zig `handle`, metal-vmm QUEUE 289), each
## the member's own, never another's: the landing, the list's JSON, a doc's
## raw markdown, its editor. One segment after /docs: a nested one is a 404.
docs_read! : Chat.Request, { rest : Str, accounts : List(Accounts.Account) } => Chat.Answer
docs_read! = |req, { rest, accounts }|
	match Members.load_uid!({}) {
		Err(Failed) => Chat.answered
		Ok(me) =>
			if rest == "" or rest == "/" {
				docs_landing!(me, accounts)
			} else {
				seg = rest.drop_prefix("/")
				if seg == "list" {
					if req.method != Get Chat.not_allowed(Get) else docs_list!(me)
				} else if seg.contains("/") {
					Chat.not_found
				} else if seg.ends_with(".md") {
					raw_doc!(me, seg.drop_suffix(".md"))
				} else {
					docs_editor!(me, { slug: ZigText.trim_str(seg), accounts })
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
docs_landing! : Uid, List(Accounts.Account) => Chat.Answer
docs_landing! = |me, accounts|
	match load_docs!(me) {
		Err(Failed) => Chat.answered
		Ok(docs) =>
			match last_touched!(docs, NoDocs) {
				Err(Failed) => Chat.answered
				Ok(Newest(last)) => Chat.redirect("/chat/docs/${last.slug}".to_utf8())
				Ok(NoDocs) => docs_page!(sorted_slugs(docs), { open: NoneChosen, accounts })
			}
	}

## Of `docs`, sorted by slug, the one changed last, the first by name of
## a tie (a folder's order differs by machine), against `best` so far; one
## gone since the listing is passed over.
last_touched! : List({ slug : Str, path : Paths.ChatPath }),
[Newest({ slug : Str, mtime : I64 }), NoDocs] => Try(
	[Newest({ slug : Str, mtime : I64 }), NoDocs],
	[Failed],
)
last_touched! = |docs, best|
	match docs {
		[] => Ok(best)
		[doc, .. as more] =>
			match Files.read_stat!(doc.path) {
				Err(Failed) => Err(Failed)
				Err(Missing) => last_touched!(more, best)
				Ok(st) =>
					match best {
						Newest(b) if b.mtime >= st.mtime => last_touched!(more, best)
						_ => last_touched!(more, Newest({ slug: doc.slug, mtime: st.mtime }))
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
			{ content_type: Chat.json, body: Docs.list_json(me.to_str(), sorted_slugs(docs)) },
		)
	}

## serveRawDoc: a doc's markdown as stored. **AN ERROR IS NOT "NO SUCH
## DOC"** (metal-vmm QUEUE 114): a name no slug is the Zig's 500, saying so.
raw_doc! : Uid, Str => Chat.Answer
raw_doc! = |me, slug|
	match Paths.doc_path(me, slug) {
		Err(NotASlug) => Chat.respond(
			500,
			{ content_type: [], body: "The doc cannot be read: InvalidDocSlug.\n".to_utf8() },
		)
		Ok(path) =>
			match Files.read_bytes!(path) {
				Ok(bytes) => Chat.respond(
					200,
					{ content_type: "text/markdown; charset=utf-8".to_utf8(), body: bytes },
				)
				Err(Missing) => Chat.not_found
				Err(Failed) => Chat.answered
			}
	}

## renderDocsEditor: the editor with `slug` open; one no slug, or not
## among the member's docs, is back to the bare editor (303).
docs_editor! : Uid, { slug : Str, accounts : List(Accounts.Account) } => Chat.Answer
docs_editor! = |me, { slug, accounts }|
	match load_docs!(me) {
		Err(Failed) => Chat.answered
		Ok(docs) => {
			slugs = sorted_slugs(docs)
			if slug == "" {
				docs_page!(slugs, { open: NoneChosen, accounts })
			} else {
				match (Paths.doc_path(me, slug), slugs.contains(slug)) {
					(Ok(path), Bool.True) => open_doc!(
						slugs,
						{
							slug,
							path,
							accounts,
						},
					)
					_ => Chat.redirect("/chat/docs".to_utf8())
				}
			}
		}
	}

## The editor with the doc at `path` open: its markdown (a doc gone since
## the listing is empty) and that rendered, the preview's first paint.
open_doc! : List(Str),
{
	slug : Str,
	path : Paths.ChatPath,
	accounts : List(Accounts.Account),
} => Chat.Answer
open_doc! = |
	slugs,
	{
		slug,
		path,
		accounts,
	},
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
					{
						open: Doc({
							slug,
							markdown,
							rendered: Chrome.rendered(rendered.html),
						}),
						accounts,
					},
				)
			}
		}
	}
}

## The docs page for the member, `open` among their `slugs`.
docs_page! : List(Str), { open : Docs.Open, accounts : List(Accounts.Account) } => Chat.Answer
docs_page! = |slugs, { open, accounts }|
	match Members.load_viewer!(accounts) {
		Err(Failed) => Chat.answered
		Ok(viewer) => Chat.respond(
			200,
			{
				content_type: Chat.html,
				body: Docs.editor({
					src: Chrome.src_in(Host.list_srcs!({})),
					viewer,
					slugs,
					open,
				}).bytes(),
			},
		)
	}

## The left pane: the "+ New" form, then the docs, `selected` marked.
doc_list : List(Str), Str -> Html
doc_list = |slugs, selected|
	Html.join([
		Html.trusted("<aside class=\"docs-list\">"),
		Html.trusted("<form method=\"post\" action=\"/chat/docs/new\" class=\"docs-new\">"),
		Html.trusted("<input type=\"text\" name=\"title\" placeholder=\"New doc title\""),
		Html.trusted(" autocomplete=\"off\" maxlength=\"80\" required>"),
		Html.trusted("<button type=\"submit\">+ New</button></form>"),
		if slugs.is_empty() {
			Html.join([
				Html.trusted("<p class=\"docs-empty muted\">"),
				Html.trusted("No docs yet. Type a title above to create one.</p>"),
			])
		} else {
			Html.join([
				Html.trusted("<ul class=\"docs-items\">"),
				Html.join(
					List.map(
						slugs,
						|slug|
							Html.tag({
								name: "li",
								attrs: [
									Attr(
										"class",
										if slug == selected "docs-item active" else "docs-item",
									),
								],
								inner: Html.tag({
									name: "a",
									attrs: [Attr("href", "/chat/docs/${slug}")],
									inner: Html.text(Docs.title(slug)),
								}),
							}),
					),
				),
				Html.trusted("</ul>"),
			])
		},
		Html.trusted("</aside>"),
	])

## oneLine: every line break a space, so a field cannot break the block.
one_line : Str -> Str
one_line = |s| s.replace_each("\n", " ").replace_each("\r", " ")

## quoteFence: one `~` more than the longest run of three or more that
## starts a line of `body`, and never fewer than three.
quote_fence : Str -> Str
quote_fence = |body| {
	longest = List.fold(
		List.split_on(body.to_utf8(), '\n'),
		0,
		|most, line| {
			run = Bytes.count_while(line, { keep: |c| c == '~', at: 0 })
			if run >= 3 and run > most run else most
		},
	)
	Str.repeat("~", (if longest > 2 longest else 2) + 1)
}

## The docs page's own style (docs.zig `docs_css`).
docs_css : Html
docs_css = Html.trusted(
	\\<style>
	\\html, body { height:100%; }
	\\.app-body-wrap { margin:10px auto; padding:0 18px 10px; min-height:0;
	\\                 max-width:1400px; display:flex; flex-direction:column; flex:1; }
	\\.docs-notify:not(:empty) { margin-bottom:6px; }
	\\.docs-layout { display:grid; grid-template-columns:220px 1fr 1fr; gap:14px;
	\\               flex:1; min-height:0; }
	\\.docs-list { border:1px solid var(--cc-border); border-radius:8px; background:var(--cc-card-bg);
	\\             padding:10px; overflow-y:auto; min-height:0; display:flex;
	\\             flex-direction:column; gap:10px; }
	\\.docs-new { display:flex; gap:6px; }
	\\.docs-new input { flex:1; min-width:0; padding:5px 7px; font-size:13px;
	\\                  border:1px solid var(--cc-border); background:var(--cc-bg); color:var(--cc-fg);
	\\                  border-radius:4px; font-family:inherit; }
	\\.docs-new button { padding:5px 10px; font-size:13px; }
	\\.docs-items { list-style:none; padding:0; margin:0; }
	\\.docs-item { padding:0; margin:2px 0; }
	\\.docs-item a { display:block; padding:5px 8px; border-radius:4px; color:var(--cc-accent);
	\\               text-decoration:none; font-size:13px; }
	\\.docs-item a:hover { background:var(--cc-search-sel-bg); }
	\\.docs-item.active a { background:var(--cc-accent); color:var(--cc-bg); font-weight:bold; }
	\\.docs-empty { font-size:12px; margin:0; }
	\\.docs-edit { display:flex; flex-direction:column; min-width:0; min-height:0; gap:6px; }
	\\.docs-title-row { display:flex; align-items:baseline; justify-content:space-between; gap:8px; }
	\\.docs-title { font-size:15px; font-weight:bold; color:var(--cc-accent); overflow:hidden;
	\\              text-overflow:ellipsis; white-space:nowrap; flex:1; min-width:0; }
	\\.docs-post-btn { padding:4px 12px; font-size:12px; flex:none; }
	\\.docs-status { font-size:12px; color:var(--cc-muted-fg); flex:none; }
	\\.docs-status.saving { color:var(--cc-muted-fg); }
	\\.docs-status.saved  { color:var(--cc-saved-fg); }
	\\.docs-status.error  { color:var(--cc-error); }
	\\.docs-alert-dialog { max-width:90vw; border:1px solid var(--cc-dialog-border);
	\\                     background:var(--cc-bg); color:var(--cc-fg);
	\\                     border-radius:8px; padding:18px 20px; }
	\\.docs-alert-dialog::backdrop { background:var(--cc-backdrop); }
	\\.docs-alert-dialog p { margin:0 0 14px; }
	\\.docs-alert-dialog button { padding:5px 16px; }
	\\#docs-body { flex:1; min-height:0; width:100%; box-sizing:border-box;
	\\             font-family:ui-monospace,Menlo,Consolas,monospace; font-size:14px;
	\\             line-height:1.45; padding:10px;
	\\             border:1px solid var(--cc-border); background:var(--cc-bg); color:var(--cc-fg);
	\\             border-radius:6px; resize:none; }
	\\.docs-preview { border:1px solid var(--cc-border); border-radius:8px; background:var(--cc-card-bg);
	\\                padding:14px 18px; overflow-y:auto; min-width:0; min-height:0;
	\\                overflow-wrap:anywhere; }
	\\.docs-preview p:first-child { margin-top:0; }
	\\.docs-preview pre { background:var(--cc-code-bg); padding:8px; border-radius:4px;
	\\                    overflow-x:auto; }
	\\.docs-preview img { max-width:100%; border-radius:6px; }
	\\.docs-preview a.msg-ref { font-family:ui-monospace,Menlo,Consolas,monospace;
	\\                          font-size:0.9em; background:var(--cc-accent-soft-bg); color:var(--cc-accent);
	\\                          padding:0 4px; border-radius:3px; text-decoration:none;
	\\                          cursor:default; }
	\\.docs-hint { margin-top:30px; text-align:center; }
	\\@media (max-width: 900px) {
	\\  .docs-layout { grid-template-columns:1fr; grid-auto-rows:minmax(180px, auto); }
	\\}
	\\</style>
	,
)

# reading_list's composeEntry tests, here since its Zig is gone (metal-vmm
# QUEUE 290): the block whole, a blank note's default, a note's line breaks
# flattened, and a fence one longer than the body's.
expect Docs.reading_entry({
	note: "read later",
	from: "apoorva",
	at: "Jun 16",
	url: "/chat/c/1_2/2026-05-28#msg-2026-05-28_5",
	body: "hello",
})
	== Str.join_with(
		[
			"### read later\n\n",
			"apoorva · Jun 16 · [↩ open in chat](/chat/c/1_2/2026-05-28#msg-2026-05-28_5)\n\n",
			"~~~ quote\nhello\n~~~\n\n---\n\n",
		],
		"",
	)
expect Docs.reading_entry({
	note: "   ",
	from: "Steve",
	at: "Jun 16",
	url: "u",
	body: "x",
}).starts_with("### read later\n")
expect Docs.reading_entry({
	note: "line1\nline2",
	from: "Steve",
	at: "Jun 16",
	url: "u",
	body: "x",
}).starts_with("### line1 line2\n")
expect {
	got = Docs.reading_entry({
		note: "n",
		from: "f",
		at: "w",
		url: "u",
		body: "before\n~~~\ncode\n~~~\nafter",
	})
	got.contains("~~~~ quote\n") and got.contains("\n~~~~\n\n---\n\n")
}

# slugifyTitle's: letters lowered, the rest one hyphen, none at the ends,
# "untitled" for none, cut to 80 and trimmed again.
expect Docs.slug_of_title("  Caf\u(e9) Menu: 2026! ") == "caf-menu-2026"
expect Docs.slug_of_title("!!!") == "untitled"
expect Docs.slug_of_title("${Str.repeat("a", 79)} b") == Str.repeat("a", 79)
# title: hyphens to spaces, the first letter up; a digit first stays.
expect Docs.title("reading-list") == "Reading list"
expect Docs.title("2026-plans") == "2026 plans" and Docs.title("") == ""

# The docs list: each entry a link to its slug, the one open marked.
expect (
	Str.from_utf8(
		Html.bytes(
			doc_list(
				["a-b", "c"],
				"c",
			),
		),
	) ?? ""
).contains("<ul class=\"docs-items\"><li class=\"docs-item\"><a href=\"/chat/docs/a-b\">${Docs.title("a-b")}</a></li><li class=\"docs-item active\"><a href=\"/chat/docs/c\">${Docs.title("c")}</a></li></ul>")

# The editor: the open doc's slug in the textarea's data, its markdown escaped.
expect {
	page = Docs.editor({
		src: |_| "/x.js",
		viewer: "v",
		slugs: ["x"],
		open: Doc({
			slug: "x",
			markdown: Str.to_utf8("md & <b>"),
			rendered: Html.trusted(""),
		}),
	})
	(Str.from_utf8(Html.bytes(page)) ?? "").contains("<textarea id=\"docs-body\" data-slug=\"x\" spellcheck=\"true\">md &amp; &lt;b&gt;</textarea>")
}
