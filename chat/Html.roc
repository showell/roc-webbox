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
import Bytes

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

	## **MARKUP THE HOST VOUCHES FOR**: bytes it built as HTML (a script's
	## src, which the host hashes and names). Called only where the host's
	## answer arrives (the hunt `html_trusted_nonliteral` names the place).
	host_markup : List(U8) -> Html
	host_markup = |markup| Html.(markup)

	## The parts, one after another.
	join : List(Html) -> Html
	join = |parts| Html.(List.join(List.map(parts, |Html.(b)| b)))

	## A template with each `{s}` slot filled in turn.
	fill : Html, List(Html) -> Html
	fill = |Html.(template), values| {
		pieces = Bytes.split_seq(template, Str.to_utf8("{s}"))
		(out, _) = List.fold(pieces, ([], 0), |(acc, i), piece|
			if i == 0 (piece, 1) else (List.join([acc, bytes(List.get(values, i - 1) ?? Html.([])), piece]), i + 1))
		Html.(out)
	}

	## The page's bytes, for a response body: the one way out.
	bytes : Html -> List(U8)
	bytes = |Html.(b)| b

	## scriptSafe: every `</` as `<\/`, the one sequence that could end the
	## element early.
	script_safe : List(U8) -> ScriptJson
	script_safe = |s| ScriptJson.(List.join(List.intersperse(Bytes.split_seq(s, ['<', '/']), ['<', '\\', '/'])))

	## The script element `open` (a trusted `<script ...>`), `json` in it,
	## and its close.
	json_script : Html, ScriptJson -> Html
	json_script = |Html.(open), ScriptJson.(json)| Html.(List.join([open, json, Str.to_utf8("</script>")]))

	## **BYTES THE TWINS SAY ARE SCRIPT-SAFE ALREADY**: never called by the
	## chat (the hunt `html_trusted_nonliteral`).
	twin_script_json : List(U8) -> ScriptJson
	twin_script_json = |b| ScriptJson.(b)

	## The script-safe bytes, for the twins.
	script_json_bytes : ScriptJson -> List(U8)
	script_json_bytes = |ScriptJson.(b)| b
}

# escape: each of the five as its entity, everything else as it was.
expect Html.bytes(Html.escape(Str.to_utf8("<script>"))) == Str.to_utf8("&lt;script&gt;")
expect Html.bytes(Html.escape(Str.to_utf8("\""))) == Str.to_utf8("&#34;")
expect Html.bytes(Html.escape(Str.to_utf8("'"))) == Str.to_utf8("&#39;")
expect Html.bytes(Html.escape(Str.to_utf8("a & b"))) == Str.to_utf8("a &amp; b")

# join and bytes: the parts' bytes in order, nothing added.
expect Html.bytes(Html.join([Html.trusted("<p>"), Html.escape(Str.to_utf8("x<y")), Html.trusted("</p>")])) == Str.to_utf8("<p>x&lt;y</p>")
expect Html.bytes(Html.join([])) == []
expect Html.bytes(Html.host_markup(Str.to_utf8("<b>&"))) == Str.to_utf8("<b>&")

# fill: each slot in turn; a slot with no value left empty.
expect Html.bytes(Html.fill(Html.trusted("a{s}b{s}c"), [Html.trusted("1")])) == Str.to_utf8("a1bc")

# json_script: `</` cannot close the element early.
expect Html.bytes(Html.json_script(Html.trusted("<script>"), Html.script_safe(Str.to_utf8("\"</script>\"")))) == Str.to_utf8("<script>\"<\\/script>\"</script>")
