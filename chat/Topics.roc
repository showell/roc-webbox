## A CONVERSATION'S TOPICS, AS /chat'S ROUTES JUDGE THEM (angry-gopher
## chat.zig): a name without case, the `general<N>` a new DM topic is
## announced in, the conversations JSON and the new topic's answer.
import Codec
import ZigText

Topics := [].{
	## std.ascii.eqlIgnoreCase: the same bytes, A-Z as a-z.
	same_name : List(U8), List(U8) -> Bool
	same_name = |a, b| List.map(a, lower) == List.map(b, lower)

	lower : U8 -> U8
	lower = |c| if c >= 65 and c <= 90 c + 32 else c

	## highestGeneralTopic: the `general<N>` with the largest N (an i64, as
	## the Zig reads it), the first of equals; none when there is none.
	highest_general : List(List(U8)) -> Try(List(U8), [None])
	highest_general = |topics| {
		prefix = Str.to_utf8("general")
		(best, _) = List.fold(topics, (Err(None), -1), |(b, n), s|
			if Codec.starts_with(s, prefix) {
				match ZigText.parse_u64(List.drop_first(s, List.len(prefix))) {
					Ok(k) if k <= 9223372036854775807 and U64.to_i128(k) > n => (Ok(s), U64.to_i128(k))
					_ => (b, n)
				}
			} else {
				(b, n)
			})
		best
	}

	## One DM in /chat/conversations: its pair, the partner, where the member
	## resumes it, and its topics.
	Entry : { conv : List(U8), id : List(U8), name : List(U8), default : List(U8), sessions : List(List(U8)) }

	## chatConversations' JSON: the member, then a DM with every other.
	conversations_json : List(U8), List(Entry) -> List(U8)
	conversations_json = |me, entries| {
		j = ZigText.json_string
		one = |e|
			List.join([
				Str.to_utf8("{\"conv\":"),
				j(e.conv),
				Str.to_utf8(",\"partner\":{\"id\":"),
				j(e.id),
				Str.to_utf8(",\"name\":"),
				j(e.name),
				Str.to_utf8("},\"default\":"),
				j(e.default),
				Str.to_utf8(",\"sessions\":["),
				List.join(List.intersperse(List.map(e.sessions, j), [44])),
				Str.to_utf8("]}"),
			])
		List.join([Str.to_utf8("{\"me\":"), j(me), Str.to_utf8(",\"conversations\":["), List.join(List.intersperse(List.map(entries, one), [44])), Str.to_utf8("]}")])
	}

	## newTopic's answer: the conversation and the topic made.
	made_json : List(U8), List(U8) -> List(U8)
	made_json = |conv, sid| List.join([Str.to_utf8("{\"conv\":"), ZigText.json_string(conv), Str.to_utf8(",\"sid\":"), ZigText.json_string(sid), Str.to_utf8("}")])
}
