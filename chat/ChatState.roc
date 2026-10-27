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
import Paths
import Time
import ZigText

ChatState := [].{

	## resumeTopic: the topic the member last viewed (`last`, "" for none)
	## while the conversation still has it; else its first topic
	## (Paths.first_of); else the date of `now_secs`, so a conversation's
	## first post makes today's topic.
	resume_topic : List(Str), Str, I64 -> Str
	resume_topic = |topics, last, now_secs|
		match List.keep_if(topics, |t| !last.is_empty() and t == last) {
			[t, ..] => t
			[] => {
				first = Paths.first_of(topics)
				if !first.is_empty() first else Time.date(now_secs)
			}
		}

	## Whether the member wants a topic pinned or unpinned.
	Pin : [Pinned, Unpinned]

	## setTopicPinned's set: the pinned file `stored` (a topic a line) with
	## `topic` pinned or unpinned, sorted by bytes, a line each; `Remove` when
	## no pin is left (the file goes). Only `topic` is de-duplicated: a pin it
	## adds is not added twice, an unpin drops every copy, and a line the
	## file already repeats stays repeated, as the Zig keeps it.
	pinned : Str, Str, Pin -> [Write(List(U8)), Remove]
	pinned = |stored, topic, pin| {
		cur = parse(stored)
		kept = if pin == Pinned cur else List.drop_if(cur, |s| s == topic)
		next = if pin == Pinned and !List.contains(cur, topic) List.append(kept, topic) else kept
		if next == [] {
			Remove
		} else {
			Write(Str.join_with(List.map(Paths.sort_by_bytes(next), |s| "${s}\n"), "").to_utf8())
		}
	}

	## pinnedTopics: the member's pins in a conversation, as its file
	## `stored` lists them, sorted by bytes. A pin no longer a topic stays:
	## the sidebar shows topics, pinned or not, so it drops out there.
	pins : Str -> List(Str)
	pins = |stored| Paths.sort_by_bytes(parse(stored))

	## parsePinned: the lines, each trimmed of spaces, tabs and CRs (ZigText's
	## trim also takes newlines, which a line split on them has none of),
	## blank ones dropped.
	parse : Str -> List(Str)
	parse = |s| List.drop_if(List.map(s.split_on("\n"), ZigText.trim_str), |line| line.is_empty())

	## lastUserConv's and lastViewedTopic's reading of a bookmark: the file
	## trimmed of spaces, tabs, CRs and newlines; "" when there is none (or
	## it failed, the request failing with it).
	bookmark : Try(Str, [Missing, Failed]) -> Str
	bookmark = |file|
		match file {
			Ok(text) => ZigText.trim_str(text)
			Err(Missing) | Err(Failed) => ""
		}

	## writeIfChanged's decision: whether `value` is written over the
	## bookmark read. Unchanged only when it reads, within the Zig's bound,
	## as `value` once trimmed. **A BOOKMARK THAT CANNOT BE READ IS WRITTEN
	## AGAIN; THE WRITE SAYS WHETHER IT CAN BE**: a failed read, and one past
	## the bound (which the Zig's bounded read refused), is changed.
	is_changed : Try(Str, [Missing, Failed]), Str -> Bool
	is_changed = |file, value|
		match file {
			Ok(text) => text.count_utf8_bytes() > bookmark_most or ZigText.trim_str(text) != value
			Err(Missing) | Err(Failed) => Bool.True
		}

	## The most of a bookmark the Zig read: setLastViewedTopic's
	## `.limited(256)` refuses a file of 256 bytes or more.
	bookmark_most : U64
	bookmark_most = 255

	## A bookmark as written: the value and a newline.
	bookmark_line : Str -> List(U8)
	bookmark_line = |value| "${value}\n".to_utf8()
}

# pins: each line trimmed, blank ones dropped, sorted by bytes; text past
# ASCII kept whole.
expect ChatState.pins("b \r\n\n caf\u(e9)\t\na\n") == ["a", "b", "caf\u(e9)"]
