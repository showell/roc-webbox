## **THE DOCS' READ PAGES** (angry-gopher docs.zig, metal-vmm QUEUE 289):
## the three-pane editor (the member's list, the open doc's textarea, its
## preview) and the list's JSON, each from what the host read. The chrome
## is Chrome.roc's.
import Bytes
import Chrome
import Html
import JsonOut
import Recent
import ZigText

Docs := [].{

	## What the editor has open: nothing, or the doc `slug`, its markdown
	## as stored and that markdown rendered (Chrome.rendered, the host's).
	Open : [
		Nothing,
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
		src : List(U8) -> Html,
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
			Nothing => ""
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
					Nothing =>
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
						Html.text(Recent.doc_title(d.slug)),
						Html.trusted("</span>"),
						Html.trusted("<button type=\"button\" id=\"docs-post-btn\""),
						Html.trusted(" class=\"docs-post-btn\">"),
						Html.trusted("Post to chat</button>"),
						Html.trusted("<span class=\"docs-status\" id=\"docs-status\">"),
						Html.trusted("</span></div>"),
						Html.trusted("<textarea id=\"docs-body\" data-slug=\""),
						Html.text(d.slug),
						Html.trusted("\" spellcheck=\"true\">"),
						Html.escape(d.markdown),
						Html.trusted("</textarea>"),
					])
				},
				Html.trusted("</section><section class=\"docs-preview\" id=\"docs-preview\">"),
				match page.open {
					Nothing => Html.trusted("")
					Doc(d) => d.rendered
				},
				Html.trusted("</section></div>"),
				match page.open {
					Nothing => Html.trusted("")
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
			ZigText.trim_str(title).to_utf8(),
			{ out: [], hyphen: Bool.False },
			|acc, raw| {
				c = if raw >= 'A' and raw <= 'Z' raw + 32 else raw
				if (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') {
					{ out: List.append(acc.out, c), hyphen: Bool.False }
				} else if acc.hyphen or acc.out.is_empty() {
					acc
				} else {
					{ out: List.append(acc.out, '-'), hyphen: Bool.True }
				}
			},
		)
		slug = trim_hyphens(kept.out)
		short = if List.len(slug) > 80 trim_hyphens(List.take_first(slug, 80)) else slug
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
			("title", JsonOut.string(Recent.doc_title(slug))),
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
							("title", JsonOut.string(Recent.doc_title(slug))),
						]),
					),
				),
			),
		]).bytes()
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
						|slug| Html.join([
							if slug == selected {
								Html.trusted("<li class=\"docs-item active\"><a href=\"/chat/docs/")
							} else {
								Html.trusted("<li class=\"docs-item\"><a href=\"/chat/docs/")
							},
							# A slug is lowercase letters, digits and hyphens:
							# escaped, it is itself, as the Zig placed it.
							Html.text(slug),
							Html.trusted("\">"),
							Html.text(Recent.doc_title(slug)),
							Html.trusted("</a></li>"),
						]),
					),
				),
				Html.trusted("</ul>"),
			])
		},
		Html.trusted("</aside>"),
	])

## How many `~` start `line`.
leading_tildes : List(U8) -> U64
leading_tildes = |line|
	match line {
		['~', .. as rest] => 1 + leading_tildes(rest)
		_ => 0
	}

## Hyphens off the end (a slug never ends in one).
trim_hyphens : List(U8) -> List(U8)
trim_hyphens = |bytes|
	match List.last(bytes) {
		Ok('-') => trim_hyphens(List.drop_last(bytes, 1))
		_ => bytes
	}

## oneLine: every line break a space, so a field cannot break the block.
one_line : Str -> Str
one_line = |s|
	match Str.from_utf8(List.map(s.to_utf8(), |c| if c == '\n' or c == '\r' ' ' else c)) {
		Ok(t) => t
		Err(_) => crash "Docs.one_line: a space for an ASCII byte split a codepoint"
	}

## quoteFence: one `~` more than the longest run of three or more that
## starts a line of `body`, and never fewer than three.
quote_fence : Str -> Str
quote_fence = |body| {
	longest = List.fold(
		Bytes.split_byte(body.to_utf8(), '\n'),
		0,
		|most, line| {
			run = leading_tildes(line)
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
