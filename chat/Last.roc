## **A TOPIC'S COUNT AND ITS LAST MESSAGE, FROM ITS SIDECAR** (metal-vmm
## QUEUE 300): how many messages it holds (`messages!`, chat_count
## messageCount), and its last message without reading its transcript
## (angry-gopher
## chat_count.zig `lastMessage`, metal-vmm QUEUE 276): the words, when they
## were sent, who sent them and which message it is, for a listing
## (/chat/recent). The `.count` sidecar's second line says where the last
## block begins and who wrote it; a window read there is believed when it
## was not full and its last block is a message of this topic numbered at
## least the count (Count.window_last). Else the whole transcript, the
## record's author kept where it speaks for exactly this transcript.
## **ONE MEMBER, OR NOBODY**: where no record says, the message's own uid,
## else the one member its name names, else nobody; never an older author.
import Files
import Paths
import Count
import Transcript
import Accounts
import pf.Host

Last := [].{

	## The last message as a listing shows it; `uid` empty for nobody.
	Message : {
		markdown : List(U8),
		at : List(U8),
		uid : List(U8),
		number : U64,
	}

	## The topic's last message, `None` for a topic with none (no
	## transcript, or no message in it). `Failed` when the transcript's read
	## failed (the request has, with its error); a cache's never does.
	of! : Paths.TopicAt, List(Accounts.Account) => Try([Some(Message), None], [Failed])
	of! = |at, accounts| {
		counted = sidecar!(at)
		match counted {
			Ok(
				{
					count,
					size: _,
					last: Known(l),
				},
			) if count > 0 =>
				match Files.read_cache!(
					Paths.transcript_path(at),
					{ offset: l.offset, max: tail_window },
				) {
					Ok(window) => {
						fill = if List.len(window) == tail_window Full else Partial
						match Count.window_last(
							count,
							window,
							fill,
							at.topic.to_utf8(),
						) {
							Ok(w) =>
								Ok(
									Some({
										markdown: w.msg.markdown,
										at: w.msg.at,
										# A current record's answer stands, nobody included;
										# a record behind: the newer message's author.
										uid: if w.record == Current l.uid else author(
											w.msg,
											accounts,
										),
										number: w.number,
									}),
								)
							Err(NotBelieved) => whole!(
								at,
								counted,
								accounts,
							)
							Err(CorruptUid(bytes)) => corrupt!(bytes)
						}
					}
					# The record is a cache: a window not there, or not read, is
					# the whole read.
					Err(Miss) => whole!(
						at,
						counted,
						accounts,
					)
				}
			_ => whole!(
				at,
				counted,
				accounts,
			)
		}
	}

	## **HOW MANY MESSAGES A TOPIC HOLDS** (chat_count.messageCount, metal-vmm
	## QUEUE 275, 300): the N that numbers the next one. **THE SIDECAR IS A
	## CACHE; THE TRANSCRIPT IS THE TRUTH**: the `.count` is believed only
	## when the transcript is still the size it was taken at (one stat), else
	## the transcript is read and its blocks counted (Count.count_blocks): a
	## sidecar whose read failed among them, a miss (metal-vmm QUEUE 284). No
	## transcript is no messages; one that will not be looked at or read
	## fails the request, never 0, which would number the next message onto
	## the last. The Roc only reads the sidecar; the host writes it with
	## every message.
	messages! : Paths.TopicAt => Try(U64, [Failed])
	messages! = |at| {
		transcript = Paths.transcript_path(at)
		match Files.stat!(transcript) {
			Err(Missing) => Ok(0)
			Err(Failed) => Err(Failed)
			Ok({ size, mtime: _ }) =>
			# readCount, then believedCount: a sidecar missing, past 1 KiB,
			# that does not parse, or whose read failed is a recount.
				match Count.believed(sidecar!(at), size) {
					Ok(n) => Ok(n)
					Err(NotBelieved) =>
						match Files.read_bytes!(transcript) {
							Ok(raw) => Ok(Count.count_blocks(raw))
							# Gone since the stat: no messages.
							Err(Missing) => Ok(0)
							Err(Failed) => Err(Failed)
						}
				}
		}
	}

	## **THE SIDECAR AS readCount READS IT**: parsed, or `Malformed` for
	## one missing, past 1 KiB, that does not parse, or whose read failed
	## (a recount, never the request's failure: Files.read_cache!): the
	## count's (`messages!`) and the last message's (`of!`).
	sidecar! : Paths.TopicAt => Try(Count.Counted, [Malformed])
	sidecar! = |at|
		match Files.read_cache!(Paths.count_path(at), { offset: 0, max: 1025 }) {
			Ok(raw) if List.len(raw) <= 1024 => Count.parse(raw)
			_ => Err(Malformed)
		}

}

## chat_store `tail_window`: 64 KiB.
tail_window : U64
tail_window = 64 * 1024

## fallbackLast: the transcript read whole and decoded; its blocks are the
## last message's number.
whole! : Paths.TopicAt,
Try(Count.Counted, [Malformed]),
List(Accounts.Account) => Try(
	[Some(Last.Message), None],
	[Failed],
)
whole! = |
	at,
	counted,
	accounts,
|
	match Files.read_bytes!(Paths.transcript_path(at)) {
		Err(Missing) => Ok(None)
		Err(Failed) => Err(Failed)
		Ok(raw) =>
			match Transcript.decode_file(raw) {
				Err(CorruptUid(bytes)) => corrupt!(bytes)
				Ok(file) =>
					match List.last(file.messages) {
						Err(_) => Ok(None)
						Ok(msg) => {
							blocks = Count.count_blocks(raw)
							uid =
								match Count.recorded_author(
									counted,
									{ blocks, size: List.len(raw) },
								) {
									Ok(recorded) => recorded
									Err(NotRecorded) => author(msg, accounts)
								}
							Ok(
								Some({
									markdown: msg.markdown,
									at: msg.at,
									uid,
									number: blocks,
								}),
							)
						}
					}
			}
	}

## A block whose uid is no uid: damaged data, the request's failure.
corrupt! : List(U8) => Try([Some(Last.Message), None], [Failed])
corrupt! = |bytes| {
	Host.fail!(NotAUid, bytes)
	Err(Failed)
}

## authorOf: the message's own uid; else the one member named `from`
## (users.onlyMemberNamed: a member is an account with a password, the
## agent's among them); else nobody. A name two share names neither, and
## an account whose name, or a namesake's kind, would not read makes the
## lookup fail, which is nobody here, as authorOf's catch makes it.
author : Transcript.Msg, List(Accounts.Account) -> List(U8)
author = |msg, accounts|
	match msg.uid {
		By(uid) => uid.to_str().to_utf8()
		Unattributed =>
			if msg.from == [] or List.any(accounts, |acct| acct.name_read == Unreadable) {
				[]
			} else {
				named = List.keep_if(accounts, |acct| acct.name.to_utf8() == msg.from)
				if List.any(named, |acct| acct.kind == Unreadable) {
					[]
				} else {
					match List.keep_if(named, |acct| acct.kind == Member or acct.kind == Agent) {
						[only] => only.id.to_str().to_utf8()
						_ => []
					}
				}
			}
	}
