## **WHERE A LIVE EVENT IS PUBLISHED** (angry-gopher chat_fanout's bus keys):
## opaque (`::`), so only this module names a key, and every key is one of
## its two shapes. A member's surfaces are namespaced (`ntf:<uid>`,
## `sb:<uid>`, `rec:<uid>`, `img:<uid>`, `code:<uid>`), so none meets a
## topic's `<key>/<topic>`: a namespace holds no `/`, and a conversation's
## key no `:`. The Zig streams that serve them subscribe with the Zig's own,
## held equal by the twins. Pure.
import Paths
import Uid

BusKey :: Str.{

	## The status strip's pings and came-online (notifyBusKey).
	notify : Uid -> BusKey
	notify = |uid| BusKey.("ntf:${uid.to_str()}")

	## The sidebar's topic-added and user-online (sidebarBusKey).
	sidebar : Uid -> BusKey
	sidebar = |uid| BusKey.("sb:${uid.to_str()}")

	## /chat/recent's rows (recentBusKey).
	recent : Uid -> BusKey
	recent = |uid| BusKey.("rec:${uid.to_str()}")

	## The member's images feed (imagesBusKey).
	images : Uid -> BusKey
	images = |uid| BusKey.("img:${uid.to_str()}")

	## The member's code feed (codeBusKey).
	code : Uid -> BusKey
	code = |uid| BusKey.("code:${uid.to_str()}")

	## A topic's messages and reactions: `<key>/<topic>`.
	topic : Paths.TopicAt -> BusKey
	topic = |at| BusKey.("${at.key.to_str()}/${at.topic}")

	## The key's bytes, as the host's bus takes them.
	bytes : BusKey -> List(U8)
	bytes = |BusKey.(k)| k.to_utf8()
}
