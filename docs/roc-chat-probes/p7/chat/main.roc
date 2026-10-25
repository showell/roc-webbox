app [handle!] { pf: platform "../platform/main.roc" }

import pf.Http
import pf.Host
import ./Codec
import ./ZigText
import ./Page
import ./Store
import "asset.js" as asset : List(U8)
import "asset.js" as asset_text : Str

handle! : Http.Request => Http.Response
handle! = |req| {
	text = Str.from_utf8_lossy(req.body)
	bodies = Codec.blocks(text)
	html = Store.render_all!(bodies)
	html2 = match Store.render_all_try!(bodies) {
		Ok(h) => h
		Err(Nope) => []
	}
	Store.log_each!(req.target |> Str.split_on("/"))
	page = Str.join_with(List.map(html, |h| Page.message_html("me", h)), "")
	n = match ZigText.parse_u64("1__0") {
		Ok(v) => v
		Err(_) => 0
	}
	out = "${page}|${U64.to_str(List.len(html2))}|${U64.to_str(n)}|${U64.to_str(Store.count_blocks(text))}|${asset_text}|${U64.to_str(List.len(asset))}"
	{ kind: 0, status: 200, headers: [], body: Str.to_utf8(out) }
}
