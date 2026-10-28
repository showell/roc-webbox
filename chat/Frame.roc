## A TOPIC STREAM'S SSE FRAMES (angry-gopher chat_frame.zig): built once,
## the same for every viewer. The html is the caller's, rendered from the
## markdown; this module only lays the frame out.
import JsonOut
import Uid

Frame := [].{

	## One message as its frame carries it: `index` 0-based (the SSE `id:`),
	## the author's account `from_uid`, `cid` empty when there is none.
	Message : {
		index : U64,
		from : Str,
		from_uid : Uid,
		at : Str,
		html : Str,
		markdown : Str,
		id : Str,
		cid : Str,
	}

	## messageFrame: `id: <index>`, then one `data:` line of JSON;
	## `from_uid` after `from`, `cid` last when there is one.
	message : Message -> List(U8)
	message = |m| {
		data = JsonOut.object(
			List.join([
				[
					("index", JsonOut.number(m.index)),
					("from", JsonOut.string(m.from)),
					("from_uid", JsonOut.string(m.from_uid.to_str())),
					("at", JsonOut.string(m.at)),
					("html", JsonOut.string(m.html)),
					("markdown", JsonOut.string(m.markdown)),
					("id", JsonOut.string(m.id)),
				],
				if m.cid == "" [] else [("cid", JsonOut.string(m.cid))],
			]),
		)
		List.join([
			Str.to_utf8("id: ${U64.to_str(m.index)}\ndata: "),
			data.bytes(),
			Str.to_utf8("\n\n"),
		])
	}

	## reactionFrame: `event: reaction`, its data the sidecar's own line;
	## no `id:`, a reaction is not a message.
	reaction : List(U8) -> List(U8)
	reaction = |line| List.join([
		Str.to_utf8("event: reaction\ndata: "),
		line,
		Str.to_utf8("\n\n"),
	])
}
