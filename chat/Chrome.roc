## THE CHAT'S PAGE SHELL (angry-gopher chat_chrome.zig): the head and its
## stylesheet, the top bar with its sub-nav, and the open content column;
## `page` wraps a page's body in it, closed. **A COPY, HELD TO THE ZIG'S
## BYTES**: the templates below were cut from chat_chrome.zig, top_bar.zig
## and chat_page.zig, and angry-gopher's chat_twin_test.zig holds every page
## built here to the one the Zig builds, byte for byte, until the Zig's go.
## The scripts' srcs are the host's (`src`): their hash is of bytes it holds.
import Bytes
import Html

Chrome := [].{

	## What a page's chrome says: its tab title, its title, who is looking,
	## the sub-nav's bold one (none for "") and where each script is.
	Shell : { tab : List(U8), title : List(U8), viewer : List(U8), active : List(U8), src : List(U8) -> List(U8) }

	## page() then Page.bytes(): the shell, `body`, and the shell closed.
	page : Shell, List(U8) -> List(U8)
	page = |s, body|
		List.join([
			Str.to_utf8(head_a),
			s.tab,
			Str.to_utf8(head_b1),
			Str.to_utf8(top_bar_css),
			Str.to_utf8(head_b2),
			fill(head_scripts, [(s.src)(Str.to_utf8("colors.js")), (s.src)(Str.to_utf8("viewport.js")), (s.src)(Str.to_utf8("chat_theme.js")), (s.src)(Str.to_utf8("chrome_drawer.js"))]),
			fill(top_a, [Html.escape(s.title)]),
			nav(s.active),
			fill(top_b, [Html.escape(s.viewer)]),
			Str.to_utf8("<div class=\"app-body-wrap\">"),
			body,
			Str.to_utf8("</div></body></html>"),
		])

	## `<script src="..."></script>` for `name`.
	script : Shell, Str -> List(U8)
	script = |s, name| List.join([Str.to_utf8("<script src=\""), (s.src)(Str.to_utf8(name)), Str.to_utf8("\"></script>")])

	## The sub-nav, " · " between, the `active` one bold and not a link.
	nav : List(U8) -> List(U8)
	nav = |active| {
		items = [("/chat", "Chat", "chat"), ("/chat/docs", "Docs", "docs"), ("/chat/recent", "Recent", "recent"), ("/chat/images", "Images", "images"), ("/chat/code", "Code", "code"), ("/chat/links", "Links", "links")]
		links = List.map(items, |(href, label, key)|
			if Str.to_utf8(key) == active Str.to_utf8("<strong>${label}</strong>") else Str.to_utf8("<a href=\"${href}\">${label}</a>"))
		List.join(List.intersperse(links, Str.to_utf8(" · ")))
	}

	## A script's src from the host's `srcs!`. **AN UNKNOWN NAME IS A CRASH**
	## (a 500), never an empty src: a page would link a script that is not there.
	src_in : List({ name : List(U8), src : List(U8) }) -> (List(U8) -> List(U8))
	src_in = |scripts| |name| match List.find_first(scripts, |s| s.name == name) {
		Ok(s) => s.src
		Err(_) => crash "Chrome: no script named <name>"
	}

	## A template with each `{s}` slot filled in turn.
	fill : Str, List(List(U8)) -> List(U8)
	fill = |template, values| {
		pieces = Bytes.split_seq(Str.to_utf8(template), Str.to_utf8("{s}"))
		(out, _) = List.fold(pieces, ([], 0), |(acc, i), piece|
			if i == 0 (piece, 1) else (List.join([acc, List.get(values, i - 1) ?? [], piece]), i + 1))
		out
	}

	## top_bar.zig's `css`, the top bar's style.
	top_bar_css : Str
	top_bar_css =
		\\.app-top { background: var(--cc-top-bar-bg, #f0ede4);
		\\           border-bottom: 1px solid var(--cc-top-bar-border, #c9bfa7);
		\\           padding: 8px 24px;
		\\           font-family: sans-serif; display: flex; justify-content: space-between;
		\\           align-items: baseline;
		\\           position: sticky; top: 0; z-index: 10; }
		\\.app-top-home a { color: var(--cc-accent, #000080); text-decoration: none; font-weight: bold; }
		\\.app-top-home a:hover { text-decoration: underline; }
		\\.app-top-user { font-size: 13px; color: var(--cc-body-muted-fg, #444); }
		\\.app-top-user a { color: var(--cc-accent, #000080); }
		\\.chat-top .chat-top-left { display: flex; align-items: baseline; gap: 14px;
		\\                           flex-wrap: wrap; min-width: 0; }
		\\.chat-top-home { color: var(--cc-accent, #000080); text-decoration: none; font-size: 13px; }
		\\.chat-top-home:hover { text-decoration: underline; }
		\\.chat-top-title { font-weight: bold; color: var(--cc-accent, #000080); }
		\\.chat-top-links { font-size: 13px; }
		\\.chat-top-links a { color: var(--cc-accent, #000080); text-decoration: none; }
		\\.chat-top-links a:hover { text-decoration: underline; }
		\\.chat-notify { font-size:13px; color:var(--cc-notify-fg, #1a5fb4); overflow:hidden; text-overflow:ellipsis;
		\\               white-space:nowrap; min-width:0; }
		\\.chat-notify a { color:inherit; }
		\\.chat-notify a:hover { text-decoration:underline; }

	## `page_head_a`: the doctype to the open `<title>`.
	head_a : Str
	head_a =
		\\<!DOCTYPE html>
		\\<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>

	## `page_head_b` before the top bar's style.
	head_b1 : Str
	head_b1 =
		\\</title>
		\\<style>
		\\body { font-family: sans-serif; margin: 0; padding: 0;
		\\       display: flex; flex-direction: column; min-height: 100vh; }
		\\.app-body-wrap { flex: 1; max-width: 820px; margin: 32px auto; padding: 0 24px 60px;
		\\                 width: 100%; box-sizing: border-box; }
		\\

	## `page_head_b` after it, to the open `<body>`.
	head_b2 : Str
	head_b2 =
		\\
		\\h1 { color: var(--cc-accent, #000080); }
		\\a { color: var(--cc-accent, #000080); }
		\\.muted { color: var(--cc-muted-fg, #888); }
		\\</style>
		\\</head><body>
		\\

	## `head_scripts`, its `{s}` slots cut at "{s}" (`fill`).
	head_scripts : Str
	head_scripts =
		\\<script src="{s}"></script><script>ChatColors.install();</script><script src="{s}"></script><script defer src="{s}"></script><script defer src="{s}"></script>

	## `chrome_top_a`, its `{s}` slots cut at "{s}" (`fill`).
	top_a : Str
	top_a =
		\\<header class="app-top chat-top"><div class="chat-top-left"><a class="chat-top-home" href="/">Home</a><span class="chat-top-title">{s}</span><span class="chat-top-links">

	## `chrome_top_b`, its `{s}` slots cut at "{s}" (`fill`).
	top_b : Str
	top_b =
		\\</span></div><div class="app-top-user"><button id="chat-theme-toggle" type="button" title="Toggle theme" aria-label="Toggle theme" style="background:none;border:none;cursor:pointer;font-size:16px;padding:0 8px;vertical-align:middle">🌙</button> · <strong>{s}</strong> · <a href="/settings">Settings</a> · <a href="/logout">Log out</a></div></header>

	## chat_page.zig's `chat_css`, the conversation page's layout.
	chat_css : Str
	chat_css =
		\\<style>
		\\html, body { height:100%; }
		\\.app-body-wrap { margin:10px auto; padding:0 24px 10px; min-height:0;
		\\                 max-width:none; display:flex; flex-direction:column; }
		\\#chat-root { flex:1; min-height:0; display:flex; flex-direction:column; }
		\\.chat-layout { display:flex; flex-direction:row; align-items:stretch;
		\\               gap:20px; flex:1; min-height:0; }
		\\</style>
}
