## A CONVERSATION'S TOPICS, AS /chat'S ROUTES JUDGE THEM (angry-gopher
## chat.zig): a name without case, the `general<N>` a new DM topic is
## announced in, the conversations JSON and the new topic's answer.
import JsonText
import Paths
import Bytes
import ZigText

Topics := [].{

	## std.ascii.eqlIgnoreCase: the same bytes, A-Z as a-z.
	same_name : List(U8), List(U8) -> Bool
	same_name = |a, b| List.map(a, lower) == List.map(b, lower)

	lower : U8 -> U8
	lower = |c| if c >= 'A' and c <= 'Z' c - 'A' + 'a' else c

	## highestGeneralTopic: the `general<N>` with the largest N (an i64, as
	## the Zig reads it), the first of equals; none when there is none.
	highest_general : List(List(U8)) -> Try(List(U8), [NoGeneral])
	highest_general = |topics| {
		(best, _) = List.fold(
			topics,
			(Err(NoGeneral), -1),
			|(b, n), s|
				match Bytes.strip_prefix(s, Str.to_utf8("general")) {
					Ok(digits) =>
						match ZigText.parse_u64(digits) {
							Ok(k) if k <= 9223372036854775807 and U64.to_i128(k) > n => (Ok(s), U64.to_i128(k))
							_ => (b, n)
						}
					Err(NoMatch) => (b, n)
				},
		)
		best
	}

	## One DM in /chat/conversations: its pair, the partner, where the member
	## resumes it, and its topics.
	Entry : { conv : List(U8), id : List(U8), name : List(U8), default : List(U8), sessions : List(List(U8)) }

	## chatConversations' JSON: the member, then a DM with every other.
	conversations_json : List(U8), List(Entry) -> List(U8)
	conversations_json = |me, entries| {
		one = |e|
			JsonText.obj([
				("conv", JsonText.str(e.conv)),
				("partner", JsonText.obj([("id", JsonText.str(e.id)), ("name", JsonText.str(e.name))])),
				("default", JsonText.str(e.default)),
				("sessions", JsonText.arr(List.map(e.sessions, JsonText.str))),
			])
		JsonText.obj([("me", JsonText.str(me)), ("conversations", JsonText.arr(List.map(entries, one)))])
	}

	## newTopic's answer: the conversation and the topic made.
	made_json : Paths.TopicAt -> List(U8)
	made_json = |{ key, topic }| JsonText.obj([("conv", JsonText.str(Paths.conv_key_bytes(key))), ("sid", JsonText.str(topic))])
}
