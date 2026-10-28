## A CONVERSATION'S TOPICS, AS /chat'S ROUTES JUDGE THEM (angry-gopher
## chat.zig): a name without case, the `general<N>` a new DM topic is
## announced in, the conversations JSON and the new topic's answer.
import JsonOut
import Paths
import Uid
import ZigText

Topics := [].{

	## std.ascii.eqlIgnoreCase: the same text, A-Z as a-z (anything past
	## ASCII must match exactly).
	is_same_name : Str, Str -> Bool
	is_same_name = |a, b| a.caseless_ascii_equals(b)

	## highestGeneralTopic: the `general<N>` with the largest N (an i64, as
	## the Zig reads it), the first of equals; none when there is none.
	highest_general : List(Str) -> Try(Str, [NoGeneral])
	highest_general = |topics| {
		(best, _) = List.fold(
			topics,
			(Err(NoGeneral), -1),
			|(b, n), s|
				if s.starts_with("general") {
					# std.fmt.parseInt's grammar is ZigText's, a byte parser.
					match ZigText.parse_u64(Str.to_utf8(s.drop_prefix("general"))) {
						Ok(k) if k <= 9223372036854775807 and U64.to_i128(k) > n => (
							Ok(s),
							U64.to_i128(k),
						)
						_ => (b, n)
					}
				} else {
					(b, n)
				},
		)
		best
	}

	## One DM in /chat/conversations: its pair, the partner, where the member
	## resumes it, and its topics.
	Entry : {
		conv : Paths.PairKey,
		id : Uid,
		name : Str,
		default : Str,
		sessions : List(Str),
	}

	## chatConversations' JSON: the member, then a DM with every other.
	conversations_json : Uid, List(Entry) -> List(U8)
	conversations_json = |me, entries| {
		one = |e|
			JsonOut.object([
				("conv", JsonOut.string(e.conv.to_str())),
				(
					"partner",
					JsonOut.object([
						("id", JsonOut.string(e.id.to_str())),
						("name", JsonOut.string(e.name)),
					]),
				),
				("default", JsonOut.string(e.default)),
				("sessions", JsonOut.array(List.map(e.sessions, JsonOut.string))),
			])
		JsonOut.object([
			("me", JsonOut.string(me.to_str())),
			("conversations", JsonOut.array(List.map(entries, one))),
		]).bytes()
	}

	## newTopic's answer: the conversation and the topic made.
	made_json : { key : Paths.ConvKey, topic : Str } -> List(U8)
	made_json = |{ key, topic }| JsonOut.object([
		("conv", JsonOut.string(key.to_str())),
		("sid", JsonOut.string(topic)),
	]).bytes()
}

# is_same_name: ASCII case folds, nothing past ASCII does.
expect Topics.is_same_name("New", "nEW")
expect Topics.is_same_name("caf\u(e9)", "CAF\u(e9)")
expect !Topics.is_same_name("caf\u(e9)", "caf\u(c9)")
expect !Topics.is_same_name("new", "new ")

# highest_general: the largest N by the Zig's grammar, the first of equals.
expect Topics.highest_general([
	"general2",
	"general10",
	"General99",
	"general+5",
	"general1_0",
	"general",
]) == Ok("general10")
expect Topics.highest_general(["general\u(e9)", "Plans"]) == Err(NoGeneral)
expect Topics.highest_general(["general007", "general7"]) == Ok("general007")
expect Topics.highest_general(["general9223372036854775808", "general1"]) == Ok("general1")
