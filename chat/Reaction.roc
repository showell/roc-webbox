## A REACTION'S FORM, AS THE REACT ROUTE READS IT (angry-gopher
## reactions.zig's parseReactForm): `msg` a message number, `emoji` one
## glyph, `on` "1" (or absent) to add it and anything else to take it back.
import Form
import ZigText
import JsonText
import Uid

Reaction := [].{

	## One reaction as the sidecar keeps it: message number `msg`, the
	## reactor's account `uid` and name `from`, the `emoji`, its `change`,
	## and when (`at`).
	Event : {
		msg : U64,
		uid : Uid,
		from : Str,
		emoji : Str,
		change : Change,
		at : Str,
	}

	## **THE ONE PLACE THE SIDECAR'S LINE SHAPE IS WRITTEN** (reactionLine):
	## `{"msg":N,"uid":…,"from":…,"emoji":…,"on":…,"at":…}`, in that order,
	## the strings as the Zig's JSON writes them. `Removed` (`"on":false`) is a
	## retraction: the client folds by last event wins per (msg, uid, emoji),
	## so the file stays append-only.
	line : Event -> List(U8)
	line = |{ msg, uid, from, emoji, change, at }|
		JsonText.obj([
			("msg", Str.to_utf8(U64.to_str(msg))),
			("uid", JsonText.str(uid.to_str())),
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

	Answer : [Reacted({ msg : U64, emoji : Str, change : Change }), Bad(List(U8)), Malformed]

	## Every field read before any is judged, as the Zig: a malformed one is
	## malformed whichever it is.
	form : List(U8) -> Answer
	form = |body|
		match (Form.field(body, "msg"), Form.field(body, "emoji"), Form.field(body, "on")) {
			(Malformed, _, _) | (_, Malformed, _) | (_, _, Malformed) => Malformed
			(m, e, o) => {
				msg_s = found_or(m, "")
				emoji = found_or(e, "")
				on_s = found_or(o, "1")
				match ZigText.parse_u64(msg_s.to_utf8()) {
					Err(NotANumber) | Err(TooBig) => Bad(Str.to_utf8("react: msg must be a message number\n"))
					Ok(msg) =>
						if is_valid_emoji(emoji) {
							Reacted({ msg, emoji, change: if on_s == "1" Added else Removed })
						} else {
							Bad(Str.to_utf8("react: emoji must be one glyph\n"))
						}
				}
			}
		}

	found_or : Form.Field, Str -> Str
	found_or = |f, default| match f {
		Found(v) => v
		_ => default
	}

	## validEmoji: the SHAPE of one glyph, 1 to 16 bytes (a limit on bytes)
	## with no ASCII byte at all (every emoji, its variation selector and ZWJ are
	## above U+2000), so a name, a digit or a quote is never one.
	is_valid_emoji : Str -> Bool
	is_valid_emoji = |text| {
		s = text.to_utf8()
		List.len(s) >= 1 and List.len(s) <= 16 and List.all(s, |c| c >= 128)
	}
}
