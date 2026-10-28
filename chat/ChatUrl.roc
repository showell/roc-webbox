## **A PATH ON THIS SITE, BUILT OR CHECKED** (the Roc's twin of zig-webbox
## http.Target): opaque (`::`), so a URL the chat writes into a page or an
## event is one this module made from a conversation's key and a topic, or
## one `on_site` passed. **ON SITE** is Target's `internal`: a `/` first, no
## second `/` right after it, no backslash and no control character, since
## a browser reads `/\evil.example` and `/\t/evil.example` as
## `//evil.example`. Pure.
import Paths

ChatUrl :: Str.{

	## A conversation's URL root: `/chat/c/<pair>` or `/channel/<name>`
	## (Conv.base). Its parts are validated keys, so it is on site.
	conv : Paths.ConvKey -> ChatUrl
	conv = |key| ChatUrl.(key.base())

	## A topic's page: its conversation's root, then the topic.
	topic : Paths.TopicAt -> ChatUrl
	topic = |at| ChatUrl.("${at.key.base()}/${at.topic}")

	## chat_fanout `convKeyBaseURL`: a conversation's URL root from the key
	## a feed entry's header names, as stored text (a DM's key holds `_`,
	## a channel's name never does). **ON SITE WHATEVER THE TEXT**: it
	## follows `/chat/c/` or `/channel/`, so no host can start it.
	feed_conv : Str -> ChatUrl
	feed_conv = |text| ChatUrl.(if text.contains("_") "/chat/c/${text}" else "/channel/${text}")

	## `convKeyBaseURL` then images_store `imagesSourceURL`: a feed entry's
	## source message, or its conversation when its id has no topic part
	## (no `_`, or only one at its start).
	source : Str, Str -> ChatUrl
	source = |text, source_id| {
		ChatUrl.(base) = feed_conv(text)
		match source_id.split_last("_") {
			Ok({ before, after: _ }) if !before.is_empty() => ChatUrl.("${base}/${before}#msg-${source_id}")
			_ => ChatUrl.(base)
		}
	}

	## `text`, when it is a path on this site (Target.of's check); never
	## the root in its place: the caller says what refused means.
	on_site : Str -> Try(ChatUrl, [NotOnSite])
	on_site = |text| if is_internal(text.to_utf8()) Ok(ChatUrl.(text)) else Err(NotOnSite)

	## The URL's text.
	to_str : ChatUrl -> Str
	to_str = |ChatUrl.(u)| u
}

## http.zig `internal`.
is_internal : List(U8) -> Bool
is_internal = |p|
	match p {
		['/', '/', ..] => Bool.False
		['/', ..] => List.all(p, |c| c != '\\' and c >= 0x20 and c != 0x7f)
		_ => Bool.False
	}

expect ChatUrl.on_site("/chat/c/1_2").is_ok()
expect ChatUrl.on_site("/").is_ok()
expect ChatUrl.on_site("//evil.example").is_err()
expect ChatUrl.on_site("/\\evil.example").is_err()
expect ChatUrl.on_site("/\t/evil.example").is_err()
expect ChatUrl.on_site("/a\r\nSet-Cookie: x").is_err()
expect ChatUrl.on_site("https://evil.example").is_err()
expect ChatUrl.on_site("").is_err()

# source: the message's link when its id has a topic part.
expect ChatUrl.source("1_2", "Plans_3").to_str() == "/chat/c/1_2/Plans#msg-Plans_3"
expect ChatUrl.source("ops", "_1").to_str() == "/channel/ops"
