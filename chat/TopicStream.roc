## **A TOPIC'S STREAM, DECIDED HERE** (the pure-Roc chat plan, item 1): its
## transcript read and decoded, the messages from where the stream resumes
## (Backlog.roc's rules), each framed with its markdown rendered
## (Frame.stored), after the preamble; handed to the host with the topic's
## bus key. The host subscribes in this request's turn, so each message is
## in the backlog or live, never both, never neither (angry-gopher
## chat_stream_turn_test.zig, on Linux); then it holds the connection and
## passes each published frame on as it is.
import pf.Chat
import pf.Host
import Backlog
import BusKey
import Files
import Frame
import Paths
import Transcript

TopicStream := [].{

	## The stream of the topic at `at`, a GET's (its route checked the method).
	answer! : Paths.TopicAt => Chat.Answer
	answer! = |at|
		match backlog!(at) {
			Ok(backlog) => Chat.topic_stream({ key: BusKey.topic(at).bytes(), backlog })
			Err(Failed) => Chat.answered
		}
}

## The preamble and the backlog's frames. A transcript not there is a
## topic with nothing in it yet; one that will not read has failed the
## request, as a render that fails has. Each refused block is counted for
## the operator, as every read of the transcript counts it.
backlog! : Paths.TopicAt => Try(List(U8), [Failed])
backlog! = |at| {
	since = Backlog.resume_at({
		last_event_id: given(Host.read_header!(Str.to_utf8("last-event-id"))),
		since: given(Host.read_query!(Str.to_utf8("since"))),
	})
	raw = match Files.read_bytes!(Paths.transcript_path(at)) {
		Ok(bytes) => Ok(bytes)
		Err(Missing) => Ok([])
		Err(Failed) => Err(Failed)
	}?
	decoded = Transcript.decode_blocks(raw)
	List.for_each!(decoded.refused, Host.count_refused_block!)
	rest = Backlog.from(decoded.blocks, { topic: at.topic.to_utf8(), since })
	frames = List.map_try!(
		rest,
		|m| {
			rendered = Host.render!(m.block.markdown)
			match rendered.status {
				Rendered => Ok(
					Frame.stored({
						index: m.index,
						block: m.block,
						html: rendered.html,
					}),
				)
				Failed => Err(Failed)
			}
		},
	)?
	Ok(List.join(List.prepend(frames, Backlog.preamble(List.len(rest)))))
}

## The first value the host found, or none.
given : List(List(U8)) -> Backlog.Given
given = |values|
	match values {
		[v, ..] => Sent(v)
		[] => Unsent
	}
