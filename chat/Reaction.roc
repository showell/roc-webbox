## A REACTION'S FORM, AS THE REACT ROUTE READS IT (angry-gopher
## reactions.zig's parseReactForm): `msg` a message number, `emoji` one
## glyph, `on` "1" (or absent) to add it and anything else to take it back.
import Form
import ZigText
import JsonText

Reaction := [].{

	## **THE ONE PLACE THE SIDECAR'S LINE SHAPE IS WRITTEN** (reactionLine):
	## `{"msg":N,"uid":…,"from":…,"emoji":…,"on":…,"at":…}`, in that order,
	## the strings as the Zig's JSON writes them. `Removed` (`"on":false`) is a
	## retraction: the client folds by last event wins per (msg, uid, emoji),
	## so the file stays append-only.
	line : U64, List(U8), List(U8), List(U8), Change, List(U8) -> List(U8)
	line = |msg, uid, from, emoji, change, at|
		JsonText.obj([
			("msg", Str.to_utf8(U64.to_str(msg))),
			("uid", JsonText.str(uid)),
			("from", JsonText.str(from)),
			("emoji", JsonText.str(emoji)),
			("on", JsonText.bool(is_added(change))),
			("at", JsonText.str(at)),
		])

	## Whether the reactor put the glyph on the message or took it back.
	Change : [Added, Removed]

	## The wire's `on` flag for a change.
	is_added : Change -> Bool
	is_added = |change| match change {
		Added => Bool.True
		Removed => Bool.False
	}

	Answer : [Reacted({ msg : U64, emoji : List(U8), change : Change }), Bad(List(U8)), Malformed]

	## Every field read before any is judged, as the Zig: a malformed one is
	## malformed whichever it is.
	form : List(U8) -> Answer
	form = |body|
		match (Form.field(body, Str.to_utf8("msg")), Form.field(body, Str.to_utf8("emoji")), Form.field(body, Str.to_utf8("on"))) {
			(Malformed, _, _) | (_, Malformed, _) | (_, _, Malformed) => Malformed
			(m, e, o) => {
				msg_s = found_or(m, [])
				emoji = found_or(e, [])
				on_s = found_or(o, ['1'])
				match ZigText.parse_u64(msg_s) {
					Err(None) => Bad(Str.to_utf8("react: msg must be a message number\n"))
					Ok(msg) =>
						if valid_emoji(emoji) {
							Reacted({ msg, emoji, change: if on_s == ['1'] Added else Removed })
						} else {
							Bad(Str.to_utf8("react: emoji must be one glyph\n"))
						}
				}
			}
		}

	found_or : Form.Field, List(U8) -> List(U8)
	found_or = |f, default| match f {
		Found(v) => v
		_ => default
	}

	## validEmoji: the SHAPE of one glyph, 1 to 16 bytes of UTF-8 with no
	## ASCII byte at all (every emoji, its variation selector and ZWJ are
	## above U+2000), so a name, a digit or a quote is never one.
	valid_emoji : List(U8) -> Bool
	valid_emoji = |s|
		List.len(s) >= 1 and List.len(s) <= 16 and List.all(s, |c| c >= 128) and Str.from_utf8(s).is_ok()
}
