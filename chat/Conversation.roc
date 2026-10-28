## WHICH CONVERSATION A ROUTE NAMES, AND WHAT IT IS CALLED (angry-gopher
## chat.zig `findConv`, `convTitle`, `findTopic`): who a DM's other half is
## when the member is one of the pair, its members, a conversation's URL
## base and title, a topic's title, whether a topic is there, the
## `general<N>` a new DM topic is announced in, the conversations JSON and
## a new topic's answer (once Topics.roc, metal-vmm QUEUE 300). Pure: the
## host reads whether an account exists, a name, a channel's members and
## the topics; angry-gopher's chat_twin_test.zig holds each to its Zig.
import JsonOut
import Paths
import Uid
import ZigText

Conversation := [].{

	## dmOther: the other of DM pair `key` when `me` is one of the pair, by
	## chatKeyParticipant's rule (PairKey.is_participant; the pair is canonical
	## by its type); `NotAParticipant` otherwise.
	dm_other : Paths.PairKey, Uid -> Try(Uid, [NotAParticipant])
	dm_other = |key, me| if key.is_participant(me) Ok(key.partner(me)) else Err(NotAParticipant)

	## ConvMeta.dm's members: the pair's two uids, or one in the DM with
	## yourself, so no one is sent a notice twice.
	dm_members : List(U8) -> List(List(U8))
	dm_members = |key|
		match List.split_first(key, '_') {
			Ok({ before: a, after: b }) => if a == b [a] else [a, b]
			Err(NotFound) => [key]
		}

	## A DM's URL base.
	dm_base : List(U8) -> List(U8)
	dm_base = |key| List.concat(Str.to_utf8("/chat/c/"), key)

	## A channel's URL base.
	channel_base : List(U8) -> List(U8)
	channel_base = |name| List.concat(Str.to_utf8("/channel/"), name)

	## A DM's title: "Chat w/" and the partner's name, or their id when the
	## account has no name (getUserName's "").
	dm_title : Str, Uid -> Str
	dm_title = |name, other| "Chat w/${if name == "" other.to_str() else name}"

	## A channel's title: "#" and its name.
	channel_title : Paths.ChannelName -> Str
	channel_title = |name| "#${name.to_str()}"

	## A topic's title: its conversation's, ": ", its id.
	topic_title : Str, Str -> Str
	topic_title = |title, topic| "${title}: ${topic}"

	## topicExists: a topic named `topic` without case is among `topics` (case
	## does not tell topics apart, on FAT or on Linux): std.ascii.eqlIgnoreCase,
	## A-Z as a-z, anything past ASCII matched exactly.
	has_topic : List(Str), Str -> Bool
	has_topic = |topics, topic| List.any(topics, |s| s.caseless_ascii_equals(topic))

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

# has_topic: case is ASCII's, a character past ASCII matched as it is.
expect Conversation.has_topic(["Plans"], "pLANS")
expect Conversation.has_topic(["Caf\u(e9)"], "cAF\u(e9)")
expect Conversation.has_topic(["ok 👍"], "OK 👍")
expect !Conversation.has_topic(["caf\u(e9)"], "caf\u(c9)")
expect !Conversation.has_topic([], "Plans")

# highest_general: the largest N by the Zig's grammar, the first of equals.
expect Conversation.highest_general([
	"general2",
	"general10",
	"General99",
	"general+5",
	"general1_0",
	"general",
]) == Ok("general10")
expect Conversation.highest_general(["general\u(e9)", "Plans"]) == Err(NoGeneral)
expect Conversation.highest_general(["general007", "general7"]) == Ok("general007")
expect Conversation.highest_general(["general9223372036854775808", "general1"]) == Ok("general1")
