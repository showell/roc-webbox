## A TOPIC STREAM'S SSE FRAMES (angry-gopher chat_frame.zig): built once,
## the same for every viewer. The html is the caller's, rendered from the
## markdown; this module only lays the frame out.
import ZigText

Frame := [].{

	## One message as its frame carries it: `index` 0-based (the SSE `id:`),
	## `from_uid` and `cid` empty when there is none.
	Message : { index : U64, from : List(U8), from_uid : List(U8), at : List(U8), html : List(U8), markdown : List(U8), id : List(U8), cid : List(U8) }

	## messageFrame: `id: <index>`, then one `data:` line of JSON;
	## `from_uid` after `from` when known, `cid` last when there is one.
	message : Message -> List(U8)
	message = |m| {
		index = Str.to_utf8(U64.to_str(m.index))
		field = |name, value| List.join([Str.to_utf8(",\"${name}\":"), ZigText.json_string(value)])
		List.join([
			Str.to_utf8("id: "),
			index,
			Str.to_utf8("\ndata: {\"index\":"),
			index,
			Str.to_utf8(",\"from\":"),
			ZigText.json_string(m.from),
			if m.from_uid == [] [] else field("from_uid", m.from_uid),
			field("at", m.at),
			field("html", m.html),
			field("markdown", m.markdown),
			field("id", m.id),
			if m.cid == [] [] else field("cid", m.cid),
			Str.to_utf8("}\n\n"),
		])
	}

	## reactionFrame: `event: reaction`, its data the sidecar's own line;
	## no `id:`, a reaction is not a message.
	reaction : List(U8) -> List(U8)
	reaction = |line| List.join([Str.to_utf8("event: reaction\ndata: "), line, Str.to_utf8("\n\n")])
}
