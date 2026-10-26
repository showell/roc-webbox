## A MEMBER'S PLACE IN THE CHAT (angry-gopher chat_state.zig): the topic a
## bare DM resumes at, and the member's pinned topics in a conversation, as
## the file that holds them. Pure: the host reads the files and writes them
## as this says. angry-gopher's chat_twin_test.zig holds each to its Zig.
import Bytes
import Paths
import Time
import ZigText

ChatState := [].{
	## resumeTopic: the topic the member last viewed (`last`, "" for none)
	## while the conversation still has it; else its first topic
	## (Paths.first_of); else the date of `now_secs`, so a conversation's
	## first post makes today's topic.
	resume_topic : List(List(U8)), List(U8), I64 -> List(U8)
	resume_topic = |topics, last, now_secs|
		if last != [] and List.contains(topics, last) {
			last
		} else {
			first = Paths.first_of(topics)
			if first != [] first else Str.to_utf8(Time.date(now_secs))
		}

	## setTopicPinned's set: the pinned file `stored` (a topic a line) with
	## `sid` pinned or unpinned, sorted by bytes, a line each; `Remove` when
	## no pin is left (the file goes). Only `sid` is de-duplicated: a pin it
	## adds is not added twice, an unpin drops every copy, and a line the
	## file already repeats stays repeated, as the Zig keeps it.
	pinned : List(U8), List(U8), Bool -> [Write(List(U8)), Remove]
	pinned = |stored, sid, pin| {
		cur = parse(stored)
		kept = if pin cur else List.drop_if(cur, |s| s == sid)
		next = if pin and !List.contains(cur, sid) List.append(kept, sid) else kept
		if next == [] {
			Remove
		} else {
			Write(List.join(List.map(Bytes.sort(next), |s| List.append(s, 10))))
		}
	}

	## parsePinned: the lines, each trimmed of spaces, tabs and CRs (ZigText's
	## trim also takes newlines, which a line split on them has none of),
	## blank ones dropped.
	parse : List(U8) -> List(List(U8))
	parse = |b| List.drop_if(List.map(Bytes.split_byte(b, 10), ZigText.trim), |s| s == [])
}
