## A TOPIC STREAM'S SSE FRAMES: built once, the same for every viewer, a
## message's live (`message`, made by the send) and replayed (`stored`, a
## stream's backlog) laid out alike. The html is the caller's, rendered
## from the markdown; this module only lays the frame out.
import JsonOut
import Transcript
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
	message = |m| frame(
		m.index,
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

	## A stored message's frame, as a stream's backlog sends it: each field
	## the bytes the transcript holds, as std.json writes bytes
	## (JsonOut.zig_bytes); `from_uid` only when the block has a `uid:`, and
	## no `cid` (a backlog frame never has one). `html` is its markdown
	## rendered.
	stored : {
		index : U64,
		block : Transcript.Block,
		html : List(U8),
	} -> List(U8)
	stored = |
		{
			index,
			block: b,
			html,
		},
	| frame(
		index,
		List.join([
			[
				("index", JsonOut.number(index)),
				("from", JsonOut.zig_bytes(b.from)),
			],
			if b.uid == [] [] else [("from_uid", JsonOut.zig_bytes(b.uid))],
			[
				("at", JsonOut.zig_bytes(b.at)),
				("html", JsonOut.zig_bytes(html)),
				("markdown", JsonOut.zig_bytes(b.markdown)),
				("id", JsonOut.zig_bytes(b.id)),
			],
		]),
	)

	## reactionFrame: `event: reaction`, its data the sidecar's own line;
	## no `id:`, a reaction is not a message.
	reaction : List(U8) -> List(U8)
	reaction = |line| List.join([
		Str.to_utf8("event: reaction\ndata: "),
		line,
		Str.to_utf8("\n\n"),
	])
}

## `id: <index>`, then the fields as one `data:` line of JSON (its escapes
## keep every newline inside it).
frame : U64, List((Str, JsonOut)) -> List(U8)
frame = |index, fields| List.join([
	Str.to_utf8("id: ${U64.to_str(index)}\ndata: "),
	JsonOut.object(fields).bytes(),
	Str.to_utf8("\n\n"),
])
