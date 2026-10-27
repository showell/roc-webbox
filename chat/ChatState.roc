## A MEMBER'S PLACE IN THE CHAT (angry-gopher chat_state.zig): the topic a
## bare DM resumes at, the bookmarks that say where (the DM last in, the
## topic last viewed in each), and the member's pinned topics in a
## conversation: their files' names under the chat root and their formats.
## Pure: the host reads and writes the bytes (Host.read!, Host.write!,
## Host.remove!) where this names them. angry-gopher's chat_twin_test.zig
## holds each to its Zig.
##
## The member's files, under the chat root:
##   users/<uid>/last-conv                  the DM last in, a line
##   users/<uid>/last-sessions/<conv-key>   the topic last viewed there, a line
##   users/<uid>/pinned-sessions/<conv-key> pinned topics, a line each
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

	## Whether the member wants a topic pinned or unpinned.
	Pin : [Pinned, Unpinned]

	## setTopicPinned's set: the pinned file `stored` (a topic a line) with
	## `sid` pinned or unpinned, sorted by bytes, a line each; `Remove` when
	## no pin is left (the file goes). Only `sid` is de-duplicated: a pin it
	## adds is not added twice, an unpin drops every copy, and a line the
	## file already repeats stays repeated, as the Zig keeps it.
	pinned : List(U8), List(U8), Pin -> [Write(List(U8)), Remove]
	pinned = |stored, sid, pin| {
		cur = parse(stored)
		kept = if pin == Pinned cur else List.drop_if(cur, |s| s == sid)
		next = if pin == Pinned and !List.contains(cur, sid) List.append(kept, sid) else kept
		if next == [] {
			Remove
		} else {
			Write(List.join(List.map(Bytes.sort(next), |s| List.append(s, '\n'))))
		}
	}

	## pinnedTopics: the member's pins in a conversation, as its file
	## `stored` lists them, sorted by bytes. A pin no longer a topic stays:
	## the sidebar shows topics, pinned or not, so it drops out there.
	pins : List(U8) -> List(List(U8))
	pins = |stored| Bytes.sort(parse(stored))

	## parsePinned: the lines, each trimmed of spaces, tabs and CRs (ZigText's
	## trim also takes newlines, which a line split on them has none of),
	## blank ones dropped.
	parse : List(U8) -> List(List(U8))
	parse = |b| List.drop_if(List.map(Bytes.split_byte(b, '\n'), ZigText.trim), |s| s == [])

	## lastUserConv's and lastViewedTopic's reading of a bookmark: the file
	## trimmed of spaces, tabs, CRs and newlines; "" when there is none (or
	## it failed, the request failing with it).
	bookmark : [Found(List(U8)), Missing, Failed] -> List(U8)
	bookmark = |file|
		match file {
			Found(bytes) => ZigText.trim(bytes)
			Missing | Failed => []
		}

	## writeIfChanged's decision: whether `value` is written over the
	## bookmark read. Unchanged only when it reads, within the Zig's bound,
	## as `value` once trimmed. **A BOOKMARK THAT CANNOT BE READ IS WRITTEN
	## AGAIN; THE WRITE SAYS WHETHER IT CAN BE**: a failed read, and one past
	## the bound (which the Zig's bounded read refused), is changed.
	changed : [Found(List(U8)), Missing, Failed], List(U8) -> Bool
	changed = |file, value|
		match file {
			Found(bytes) => List.len(bytes) > bookmark_most or ZigText.trim(bytes) != value
			Missing | Failed => Bool.True
		}

	## The most of a bookmark the Zig read: setLastViewedTopic's
	## `.limited(256)` refuses a file of 256 bytes or more.
	bookmark_most : U64
	bookmark_most = 255

	## A bookmark as written: the value and a newline.
	bookmark_line : List(U8) -> List(U8)
	bookmark_line = |value| List.append(value, '\n')
}
