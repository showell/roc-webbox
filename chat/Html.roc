## HTML'S TWO SAFETIES (zig-webbox html.zig): text escaped for an element or
## an attribute, and a blob made safe inside an inline `<script>`.
##
## **A PAGE IS AN `Html`, AND AN `Html` IS SAFE BY CONSTRUCTION**: opaque
## (`::`), so outside this module nothing makes one from bytes. The ways in:
## `escape` (text a user or the disk supplied), `trusted` (markup written in
## the code; the roc hunt `html_trusted_nonliteral` holds its argument to a
## string literal), `host_markup` (bytes the host vouches are markup) and
## `json_script` (a script-safe JSON blob inside its `<script>`). The one way
## out is `bytes`, where a page becomes a response body. The host's markdown
## (`render!`) never reaches a page here: it rides a JSON frame (Frame.roc),
## and the curated links the host splices in itself (Pages.links_around).
import Ascii

Html :: List(U8).{

	## Script-safe JSON (`script_safe`): fit only inside a `<script>`, so its
	## one way into a page is `json_script`.
	ScriptJson :: List(U8)

	## htmlEscape: `&`, `'`, `<`, `>` and `"` as entities.
	escape : List(U8) -> Html
	escape = |s| Html.(
		List.join(
			List.map(
				s,
				|c|
					match c {
						'&' => Str.to_utf8("&amp;")
						'\'' => Str.to_utf8("&#39;")
						'<' => Str.to_utf8("&lt;")
						'>' => Str.to_utf8("&gt;")
						'"' => Str.to_utf8("&#34;")
						_ => [c]
					},
			),
		),
	)

	## Text escaped, as `escape` escapes its bytes.
	text : Str -> Html
	text = |s| escape(s.to_utf8())

	## **TRUSTED MARKUP, WRITTEN IN THE CODE**: a string literal only (the
	## hunt `html_trusted_nonliteral`); anything computed goes through `escape`.
	trusted : Str -> Html
	trusted = |markup| Html.(Str.to_utf8(markup))

	## **MARKUP THE HOST VOUCHES FOR**: bytes it built as HTML (the markdown it
	## rendered). Called only where the host's
	## answer arrives (the hunt `html_trusted_nonliteral` names the place).
	host_markup : List(U8) -> Html
	host_markup = |markup| Html.(markup)

	## An attribute: a name and its value, or a name alone (`defer`).
	Attr : [Attr(Str, Str), Bare(Str)]

	## **AN ELEMENT, ITS ATTRIBUTE VALUES ALWAYS ESCAPED** (zulip-flet's
	## `build_tag`): `<name a="v" ...>inner</name>`, every value through
	## `escape`, so no caller can place one raw. Its names (the element's and
	## the attributes') are code, not data: lowercase ASCII letters, digits
	## and `-`, anything else a crash. Never `<name/>`: in HTML5 that does not
	## close the element.
	tag : {
		name : Str,
		attrs : List(Attr),
		inner : Html,
	} -> Html
	tag = |t| {
		name = code_name(t.name)
		Html.(
			List.join([
				['<'],
				name,
				List.join_map(t.attrs, attr_bytes),
				['>'],
				bytes(t.inner),
				['<', '/'],
				name,
				['>'],
			]),
		)
	}

	## No markup: an element with nothing in it.
	empty : Html
	empty = Html.([])

	## The parts, one after another.
	join : List(Html) -> Html
	join = |parts| Html.(List.join_map(parts, |Html.(b)| b))

	## A template with each `{s}` slot filled in turn.
	fill : Html, List(Html) -> Html
	fill = |Html.(template), values| {
		pieces = List.split_on_list(template, Str.to_utf8("{s}"))
		(out, _) = List.fold(
			pieces,
			([], 0),
			|(acc, i), piece|
				if i == 0 {
					(piece, 1)
				} else {
					match List.get(values, i - 1) {
						Ok(value) => (
							List.join([
								acc,
								bytes(value),
								piece,
							]),
							i + 1,
						)
						# Every template here is a literal, filled where it is written.
						Err(_) => crash "Html.fill: a template has more {s} slots than values"
					}
				},
		)
		Html.(out)
	}

	## The page's bytes, for a response body: the one way out.
	bytes : Html -> List(U8)
	bytes = |Html.(b)| b

	## zig-webbox html `scriptSafe`: every `<` as `\u003c`, which JSON reads
	## back as the same `<`. Escaping only `</` was not enough (metal-vmm
	## QUEUE 266): `<!--` then `<script` puts the HTML tokenizer in its
	## double-escaped state, where the page's own `</script>` no longer ends
	## the element. With no `<`, no tag or comment can start. JSON only.
	script_safe : List(U8) -> ScriptJson
	script_safe = |s| ScriptJson.(
		List.join(
			List.intersperse(
				List.split_on_list(s, ['<']),
				Str.to_utf8("\\u003c"),
			),
		),
	)

	## A `<script>` with `attrs`, the script-safe `json` in it.
	json_script : List(Attr), ScriptJson -> Html
	json_script = |attrs, ScriptJson.(json)| tag({
		name: "script",
		attrs,
		inner: Html.(json),
	})

	## **BYTES THE TWINS SAY ARE SCRIPT-SAFE ALREADY**: never called by the
	## chat (the hunt `html_trusted_nonliteral`).
	twin_script_json : List(U8) -> ScriptJson
	twin_script_json = |b| ScriptJson.(b)

	## The script-safe bytes, for the twins.
	script_json_bytes : ScriptJson -> List(U8)
	script_json_bytes = |ScriptJson.(b)| b
}

attr_bytes : Html.Attr -> List(U8)
attr_bytes = |a|
	match a {
		Attr(name, value) => List.join([
			[' '],
			code_name(name),
			['=', '"'],
			Html.bytes(Html.text(value)),
			['"'],
		])
		Bare(name) => List.concat([' '], code_name(name))
	}

## A name the code wrote, an element's or an attribute's: lowercase ASCII
## letters, digits and `-`. Anything else is a bug, so a crash.
code_name : Str -> List(U8)
code_name = |name| {
	b = name.to_utf8()
	if b != [] and List.all(b, |c| (c >= 'a' and c <= 'z') or Ascii.is_digit(c) or c == '-') {
		b
	} else {
		crash "Html.tag: a name that is not lowercase ASCII letters, digits and -"
	}
}

# escape: each of the five as its entity, everything else as it was.
expect Html.bytes(Html.escape(Str.to_utf8("<script>"))) == Str.to_utf8("&lt;script&gt;")
expect Html.bytes(Html.escape(Str.to_utf8("\""))) == Str.to_utf8("&#34;")
expect Html.bytes(Html.escape(Str.to_utf8("'"))) == Str.to_utf8("&#39;")
expect Html.bytes(Html.escape(Str.to_utf8("a & b"))) == Str.to_utf8("a &amp; b")

# join and bytes: the parts' bytes in order, nothing added.
expect Html.bytes(
	Html.join([
		Html.trusted("<p>"),
		Html.escape(Str.to_utf8("x<y")),
		Html.trusted("</p>"),
	]),
) == Str.to_utf8("<p>x&lt;y</p>")
expect Html.bytes(Html.join([])) == []
expect Html.bytes(Html.host_markup(Str.to_utf8("<b>&"))) == Str.to_utf8("<b>&")

# fill: each slot in turn; a slot with no value left empty.
expect Html.bytes(
	Html.fill(
		Html.trusted("a{s}b{s}c"),
		[Html.trusted("1"), Html.trusted("2")],
	),
) == Str.to_utf8("a1b2c")

# json_script: `</` cannot close the element early.
expect Html.bytes(
	Html.json_script(
		[],
		Html.script_safe(Str.to_utf8("\"</script>\"")),
	),
) == Str.to_utf8("<script>\"\\u003c/script>\"</script>")
# The double-escaped state's way in: no `<` is left, so neither starts.
expect Html.bytes(
	Html.json_script(
		[],
		Html.script_safe(Str.to_utf8("\"<!--<script>\"")),
	),
) == Str.to_utf8("<script>\"\\u003c!--\\u003cscript>\"</script>")

# tag: each value escaped, whatever it holds; names as written.
expect Html.bytes(
	Html.tag({
		name: "a",
		attrs: [Attr("title", "&<>\"'")],
		inner: Html.text("x"),
	}),
) == Str.to_utf8("<a title=\"&amp;&lt;&gt;&#34;&#39;\">x</a>")
expect Html.bytes(
	Html.tag({
		name: "p",
		attrs: [],
		inner: Html.text("hi"),
	}),
) == Str.to_utf8("<p>hi</p>")
expect Html.bytes(
	Html.tag({
		name: "div",
		attrs: [Attr("id", "a")],
		inner: Html.tag({
			name: "span",
			attrs: [Attr("class", "b")],
			inner: Html.text("<c>"),
		}),
	}),
) == Str.to_utf8("<div id=\"a\"><span class=\"b\">&lt;c&gt;</span></div>")
expect Html.bytes(
	Html.tag({
		name: "div",
		attrs: [Attr("data-x", "")],
		inner: Html.empty,
	}),
) == Str.to_utf8("<div data-x=\"\"></div>")
expect Html.bytes(
	Html.tag({
		name: "script",
		attrs: [Bare("defer"), Attr("src", "/a.js?v=1")],
		inner: Html.empty,
	}),
) == Str.to_utf8("<script defer src=\"/a.js?v=1\"></script>")
