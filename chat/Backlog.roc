## A TOPIC'S BACKLOG, AS ITS STREAM SENDS IT FIRST: where the stream
## resumes (a twin of webbox's sse.resumeAt), which of the transcript's
## messages go from there, and the event before them. Pure; the read, the
## render and the frames are main.roc's `replay!`.
import Bytes
import Count
import Transcript
import ZigText

Backlog := [].{

	## A resume source as the request carries it: a Last-Event-ID header's
	## value, or a `?since=` field's as written.
	Given : [Sent(List(U8)), Unsent]

	## sse.resumeAt: a Last-Event-ID that parses (std's parseInt, spaces
	## and tabs trimmed) resumes after that frame, at n+1, **SATURATING**:
	## the header is the client's, and its largest resumes past everything;
	## else a `?since=` that parses resumes at it; else 0. A source that
	## does not parse falls through to the next.
	resume_at : { last_event_id : Given, since : Given } -> U64
	resume_at = |{ last_event_id, since }|
		match parsed(last_event_id, [' ', '\t']) {
			Ok(n) => if n == u64_most n else n + 1
			Err(_) => parsed(since, []) ?? 0
		}

	## One message of the backlog: its index (the SSE `id:`) and its block.
	Numbered : { index : U64, block : Transcript.Block }

	## backlogFrom: the topic's message blocks from the first whose index is
	## at least `since`, and every one after it. **AN INDEX, NOT A
	## POSITION**: a message's index is its id's number less one
	## (Count.index_of), so a refused block before it leaves the positions
	## behind the indexes; an id that is not this topic's is its place
	## among the blocks.
	from : List(Transcript.Block), { topic : List(U8), since : U64 } -> List(Numbered)
	from = |blocks, { topic, since }| {
		numbered = List.map_with_index(
			blocks,
			|block, i| { index: Count.index_of(block.id, topic) ?? i, block },
		)
		match List.find_first_index(numbered, |m| m.index >= since) {
			Ok(first) => List.drop_first(numbered, first)
			Err(_) => []
		}
	}

	## The event before the backlog: how many messages it holds.
	preamble : U64 -> List(U8)
	preamble = |n| Str.to_utf8("event: backlog-size\ndata: ${U64.to_str(n)}\n\n")
}

## A source's number, `trimmed` taken off both its ends first.
parsed : Backlog.Given, List(U8) -> Try(U64, [NotANumber, TooBig, Unsent])
parsed = |given, trimmed|
	match given {
		Sent(v) => ZigText.std_parse_u64(Bytes.trim(v, trimmed))
		Unsent => Err(Unsent)
	}

## The largest U64: a Last-Event-ID of it resumes at it, past everything.
u64_most : U64
u64_most = 18446744073709551615

# sse.resumeAt's own table: Last-Event-ID resumes after n, ?since at n,
# junk falls through, and the largest never overflows.
expect Backlog.resume_at({ last_event_id: Sent(Str.to_utf8("5")), since: Unsent }) == 6
expect Backlog.resume_at({ last_event_id: Sent(Str.to_utf8("  5 ")), since: Unsent }) == 6
expect Backlog.resume_at({ last_event_id: Unsent, since: Sent(Str.to_utf8("5")) }) == 5
expect Backlog.resume_at({ last_event_id: Unsent, since: Unsent }) == 0
expect Backlog.resume_at({ last_event_id: Sent(Str.to_utf8("5")), since: Sent(Str.to_utf8("99")) }) == 6
expect Backlog.resume_at({ last_event_id: Sent(Str.to_utf8("garbage")), since: Sent(Str.to_utf8("5")) }) == 5
expect Backlog.resume_at({ last_event_id: Sent(Str.to_utf8("x")), since: Sent(Str.to_utf8("y")) }) == 0
expect Backlog.resume_at({ last_event_id: Sent(Str.to_utf8("18446744073709551614")), since: Unsent }) == u64_most
expect Backlog.resume_at({ last_event_id: Sent(Str.to_utf8("18446744073709551615")), since: Unsent }) == u64_most
expect Backlog.resume_at({ last_event_id: Sent(Str.to_utf8("18446744073709551616")), since: Sent(Str.to_utf8("5")) }) == 5

# A reconnect past a refused block misses nothing: t_2 was refused, so the
# blocks are t_1, t_3, t_4, and a client that saw t_3 (index 2) asks from 3.
expect {
	block = |id| { id: Str.to_utf8(id), from: ['a'], at: ['d'], uid: [], markdown: ['x'] }
	blocks = [block("t_1"), block("t_3"), block("t_4")]
	ids = |since| List.map(Backlog.from(blocks, { topic: ['t'], since }), |m| m.index)
	ids(3) == [3] and ids(0) == [0, 2, 3] and ids(1) == [2, 3] and ids(4) == []
}
