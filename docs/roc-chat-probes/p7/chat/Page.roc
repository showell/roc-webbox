Page :: [].{
	## Pure: takes already-rendered HTML.
	message_html : Str, Str -> Str
	message_html = |author, html| "<div class=\"m\"><b>${author}</b>${html}</div>"
}

expect Page.message_html("a", "<p>x</p>") == "<div class=\"m\"><b>a</b><p>x</p></div>"
