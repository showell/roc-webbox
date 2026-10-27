## WHICH CONVERSATION A ROUTE NAMES, AND WHAT IT IS CALLED (angry-gopher
## chat.zig `findConv`, `convTitle`, `findTopic`): who a DM's other half is
## when the member is one of the pair, its members, a conversation's URL
## base and title, a topic's title, and whether a topic is there. Pure: the
## host reads whether an account exists, a name, a channel's members and
## the topics; angry-gopher's chat_twin_test.zig holds each to its Zig.
import Paths
import Topics
import Uid

Conversation := [].{

	## dmOther: the other of DM pair `key` when `me` is one of the pair, by
	## chatKeyParticipant's rule (Paths.is_participant; the pair is canonical
	## by its type); `NotAParticipant` otherwise.
	dm_other : Paths.PairKey, Uid -> Try(Uid, [NotAParticipant])
	dm_other = |key, me| if Paths.is_participant(key, me) Ok(partner(Paths.pair_key_bytes(key), me)) else Err(NotAParticipant)

	## partnerName's half: the side of `key`'s first `_` that is not `me`
	## (the second when the first is `me`, so `1_1`'s partner is `1`); the
	## whole key when it has no `_`.
	partner : List(U8), Uid -> Uid
	partner = |key, me|
		match Paths.cut_first(key, '_') {
			Ok((a, b)) => if Uid.from_bytes(a) == me Uid.from_bytes(b) else Uid.from_bytes(a)
			Err(NoSeparator) => Uid.from_bytes(key)
		}

	## ConvMeta.dm's members: the pair's two uids, or one in the DM with
	## yourself, so no one is sent a notice twice.
	dm_members : List(U8) -> List(List(U8))
	dm_members = |key|
		match Paths.cut_first(key, '_') {
			Ok((a, b)) => if a == b [a] else [a, b]
			Err(NoSeparator) => [key]
		}

	## A DM's URL base.
	dm_base : List(U8) -> List(U8)
	dm_base = |key| List.concat(Str.to_utf8("/chat/c/"), key)

	## A channel's URL base.
	channel_base : List(U8) -> List(U8)
	channel_base = |name| List.concat(Str.to_utf8("/channel/"), name)

	## A DM's title: "Chat w/" and the partner's name, or their id when the
	## account has no name (getUserName's "").
	dm_title : List(U8), List(U8) -> List(U8)
	dm_title = |name, other| List.concat(Str.to_utf8("Chat w/"), if name == [] other else name)

	## A channel's title: "#" and its name.
	channel_title : List(U8) -> List(U8)
	channel_title = |name| List.concat(['#'], name)

	## A topic's title: its conversation's, ": ", its id.
	topic_title : List(U8), List(U8) -> List(U8)
	topic_title = |title, topic| List.join([title, Str.to_utf8(": "), topic])

	## topicExists: a topic named `topic` without case is among `topics` (case
	## does not tell topics apart, on FAT or on Linux).
	has_topic : List(Str), Str -> Bool
	has_topic = |topics, topic| List.any(topics, |s| Topics.same_name(s, topic))
}

# has_topic: case is ASCII's, a character past ASCII matched as it is.
expect Conversation.has_topic(["Plans"], "pLANS")
expect Conversation.has_topic(["Caf\u(e9)"], "cAF\u(e9)")
expect Conversation.has_topic(["ok 👍"], "OK 👍")
expect !Conversation.has_topic(["caf\u(e9)"], "caf\u(c9)")
expect !Conversation.has_topic([], "Plans")
