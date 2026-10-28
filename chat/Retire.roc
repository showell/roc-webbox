## **THE ADMIN RETIRE'S PLAN** (metal-vmm QUEUE 293; angry-gopher
## chat_retire.zig carries it out): which topics, accounts, DMs, channel
## memberships and kept members' pointers go, under the admin's days and
## keep list. The plan reads only the chat root and the accounts as
## Host.list_accounts! hands them (never auth_root), and changes nothing:
## each step is handed to the host (`carry_out!`), which acts on a confirm
## and only says it on a dry run, and removes the accounts themselves last.
##
## **A DRY RUN THAT LISTS, AND A CONFIRM THAT ACTS**: both plan the same
## steps, the removals projected (a pointer into a DM that would go reads
## as dangling), so a second confirm finds nothing.
import pf.Chat
import pf.Host
import Accounts
import Members
import Bytes
import Files
import Paths
import Time
import Transcript
import Uid
import ZigText

Retire := [].{

	## How the admin asked: topics quieter than `days` go, and every account
	## whose name is not one of `keep`, as of `now` (unix seconds).
	Asked : {
		days : U64,
		keep : List(List(U8)),
		now : I64,
	}

	## A step of the plan, as the host is handed it: said for the report, a
	## file or a folder removed, a file written whole, or a member retired
	## outside the chat.
	Step : [
		Note(Kind, Str),
		Remove(Paths.ChatPath, [File, Tree]),
		Replace(Paths.ChatPath, List(U8)),
		Retired(Uid),
	]

	## What a step removes, as the report counts it.
	Kind : [
		ChannelMember,
		Dm,
		RefLastConv,
		RefLastSession,
		RefPinned,
		Topic,
		User,
	]

	## Host.retire_asked!'s answer, its names one to a line, blank lines
	## dropped (the admin's form drops blank names too).
	asked! : {} => Asked
	asked! = |{}| {
		got = Host.retire_asked!({})
		{
			days: got.days,
			keep: List.drop_if(List.split_on(got.keep, '\n'), |n| n == []),
			now: got.now,
		}
	}

	## **THE KEEP LIST NAMES REAL ACCOUNTS, AND EVERY ACCOUNT HAS A NAME**
	## (keepProblem): every account not kept is removed, so a keep name that
	## matches no account (a typo) would keep no one by it, and an account
	## with no name could not be kept at all. Either refuses the whole plan,
	## the dry run too, in words; a name that would not read fails it.
	refused : List(Accounts.Account),
	List(List(U8)) -> Try(
		{},
		[Unreadable(Accounts.Unreadable), Refused(Str)],
	)
	refused = |accounts, keep|
		match List.find_first(accounts, |a| a.name_read == Unreadable) {
			Ok(a) => Err(Unreadable(NameUnreadable(a.id)))
			Err(_) =>
				match List.find_first(accounts, |a| a.name == "") {
					Ok(a) => Err(Refused(nameless(a.id)))
					Err(_) =>
						match List.find_first(
							keep,
							|k| !List.any(accounts, |a| a.name.to_utf8() == k),
						) {
							Ok(k) => Err(Refused(no_such(k)))
							Err(_) => Ok({})
						}
				}
		}

	## **THE PLAN**, in the order it is carried out: old topics, the
	## accounts not kept, their DMs, their channel lines, then a kept
	## member's pointers into a conversation now gone. **THE ACCOUNTS GO
	## LAST**, after every step (the host's): a refusal part way leaves
	## the member listed, and the next confirm finishes. `Failed` when a
	## read failed (the host has its error).
	plan! : List(Accounts.Account), Asked => Try(List(Step), [Failed])
	plan! = |accounts, asked| {
		cutoff = asked.now - asked.days.to_i64_wrap() * 86400
		topics = old_topics!(
			conversations!({})?,
			cutoff,
			[],
		)?
		removed = List.drop_if(accounts, |a| List.contains(asked.keep, a.name.to_utf8()))
		ids = List.map(removed, |a| a.id.to_str())
		users = List.join(
			List.map(
				removed,
				|a| [Note(User, "${a.name} (uid ${a.id.to_str()})"), Retired(a.id)],
			),
		)
		dms = gone_dms!(ids)?
		channels = pruned_channels!(ids)?
		pointers = dangling!(
			accounts,
			asked.keep,
			ids,
			List.map(dms, |d| d.key),
		)?
		Ok(
			List.join([
				topics,
				users,
				List.join(List.map(dms, |d| d.steps)),
				channels,
				pointers,
			]),
		)
	}

	## **THE ADMIN RETIRE'S ANSWER** (metal-vmm QUEUE 293), asked in its own
	## area by the admin page behind its password, before any of the chat's
	## prelude (no member, no presence): the keep list checked against the
	## accounts, then the plan made and handed to the host a step at a time.
	## A keep list refused is a 400 in its own words; a plan carried out, an
	## empty 200.
	answer! : {} => Chat.Answer
	answer! = |{}| {
		got = asked!({})
		match Members.load_accounts!(Unasked) {
			Err(Failed) => Chat.answered
			Ok(accounts) =>
				match refused(accounts, got.keep) {
					Err(Unreadable(why)) => {
						Members.fail_unreadable!(why)
						Chat.answered
					}
					Err(Refused(why)) => Chat.respond(400, [], why.to_utf8())
					Ok({}) =>
						match plan!(accounts, got) {
							Err(Failed) => Chat.answered
							Ok(steps) =>
								match carry_out!(steps) {
									Ok({}) => Chat.respond(200, [], [])
									Err(Failed) => Chat.answered
								}
						}
				}
		}
	}

	## Each step handed to the host, in order; the first that failed ends
	## the confirm there (`Failed`: the host has its error).
	carry_out! : List(Step) => Try({}, [Failed])
	carry_out! = |steps|
		match steps {
			[] => Ok({})
			[step, .. as more] => {
				done = match step {
					Note(kind, label) => {
						Host.retire_note!(kind, label.to_utf8())
						Ok({})
					}
					Remove(path, what) => Host.retire_remove!(path.bytes(), what)
					Replace(path, bytes) => Host.retire_replace!(path.bytes(), bytes)
					Retired(uid) => Host.retire_user!(uid.to_str().to_utf8())
				}
				match done {
					Ok({}) => carry_out!(more)
					Err(Failed) => Err(Failed)
				}
			}
		}
}

## The refusal of an account with no name, which no keep list can name.
nameless : Uid -> Str
nameless = |id| {
	uid = id.to_str()
	"Account ${uid} has no name; give it one before retiring."
}

## The refusal of a keep name no account has.
no_such : List(U8) -> Str
no_such = |keep| {
	name = Str.from_utf8_lossy(keep)
	"The keep list names \"${name}\", which is no account's name."
}

## A conversation as the walk finds it: its folder under the chat root, and
## its name in the report (`channel/<name>` for a channel's).
Conv : { folder : List(Str), key : Str }

## Every conversation folder (listConvDirs): each folder under the chat
## root but `users`, and each under `channels`, in name order. A root not
## there holds none.
conversations! : {} => Try(List(Conv), [Failed])
conversations! = |{}| {
	top = folders!([])?
	Ok(
		List.join(
			List.map(
				top,
				|name|
					if name == "users" {
						[]
					} else if name == "channels" {
						# A channel's folders, listed when we come to them.
						[{ folder: ["channels"], key: "" }]
					} else {
						[{ folder: [name], key: name }]
					},
			),
		),
	)
		|> expand_channels!
}

## The `channels` mark replaced by each channel's folder.
expand_channels! : Try(List(Conv), [Failed]) => Try(List(Conv), [Failed])
expand_channels! = |got| {
	convs = got?
	match List.find_first_index(convs, |c| c.key == "") {
		Err(_) => Ok(convs)
		Ok(at) => {
			chans = folders!(["channels"])?
			mapped = List.map(chans, |n| { folder: ["channels", n], key: "channel/${n}" })
			Ok(
				List.join([
					List.take_first(convs, at),
					mapped,
					List.drop_first(convs, at + 1),
				]),
			)
		}
	}
}

## The folders listed at `parts` under the chat root, by name; none when it
## is not there.
folders! : List(Str) => Try(List(Str), [Failed])
folders! = |parts|
	match Files.list!(Paths.listed(parts)) {
		Ok(got) => Ok(
			Paths.sort_by_bytes(
				List.keep_oks(
					got.entries,
					|e| if e.kind == Dir Ok(e.name) else Err(NotAFolder),
				),
			),
		)
		Err(Missing) => Ok([])
		Err(Failed) => Err(Failed)
	}

## The files listed at `parts`, by name; none when it is not there.
files! : List(Str) => Try(List(Str), [Failed])
files! = |parts|
	match Files.list!(Paths.listed(parts)) {
		Ok(got) => Ok(
			Paths.sort_by_bytes(
				List.keep_oks(
					got.entries,
					|e| if e.kind == Dir Err(AFolder) else Ok(e.name),
				),
			),
		)
		Err(Missing) => Ok([])
		Err(Failed) => Err(Failed)
	}

## **OLD TOPICS**: each conversation's topics whose newest datable message
## is before `cutoff`, with their sidecars. **A TOPIC WE CANNOT DATE IS
## KEPT** (Steve, 2026-10-04): an empty or hand-damaged transcript may be a
## fresh topic someone just made.
old_topics! : List(Conv), I64, List(Step) => Try(List(Step), [Failed])
old_topics! = |
	convs,
	cutoff,
	steps,
|
	match convs {
		[] => Ok(steps)
		[conv, .. as more] => {
			sessions = List.append(conv.folder, "sessions")
			sids = List.keep_oks(
				files!(sessions)?,
				|f| if f.ends_with(".md") Ok(f.drop_suffix(".md")) else Err(NotATopic),
			)
			gone = old_in!(
				conv,
				sessions,
				sids,
				cutoff,
				[],
			)?
			old_topics!(
				more,
				cutoff,
				List.concat(steps, gone),
			)
		}
	}

old_in! : Conv, List(Str), List(Str), I64, List(Step) => Try(List(Step), [Failed])
old_in! = |
	conv,
	sessions,
	sids,
	cutoff,
	steps,
|
	match sids {
		[] => Ok(steps)
		[sid, .. as more] => {
			at = |suffix| Paths.listed(List.append(sessions, "${sid}${suffix}"))
			old = match Files.read_bytes!(at(".md")) {
				Ok(raw) =>
					match newest(raw) {
						Ok(t) if t < cutoff => Ok(Old)
						_ => Ok(Kept)
					}
				Err(Missing) => Ok(Kept)
				Err(Failed) => Err(Failed)
			}
			these =
				if old? == Old {
					[
						Note(Topic, "${conv.key}/${sid}"),
						Remove(at(".md"), File),
						# Sidecars go with the topic, unlisted; no server writes
						# `.lastauthor` now, but one an older server left goes too.
						Remove(at(".count"), File),
						Remove(at(".lastauthor"), File),
						Remove(at(".reactions.jsonl"), File),
						Remove(at(".uploads"), Tree),
					]
				} else {
					[]
				}
			old_in!(
				conv,
				sessions,
				more,
				cutoff,
				List.concat(steps, these),
			)
		}
	}

## The newest `date:` among a transcript's messages, or `Undated` when none
## carries a date that reads (or the transcript will not decode).
newest : List(U8) -> Try(I64, [Undated])
newest = |raw|
	match Transcript.decode_file(raw) {
		Err(_) => Err(Undated)
		Ok(got) =>
			match List.keep_oks(got.messages, |m| Time.unix_from_rfc3339(m.at)) {
				[] => Err(Undated)
				[first, .. as rest] => Ok(
					List.fold(
						rest,
						first,
						|a, b| if b > a b else a,
					),
				)
			}
	}

## **A REMOVED MEMBER'S DMS**: every folder `a_b` under the chat root, both
## halves uids, that holds one of `ids`: removed whole (the other party's
## messages too: the conversation is gone), its key kept for the sweep.
gone_dms! : List(Str) => Try(List({ key : Str, steps : List(Step) }), [Failed])
gone_dms! = |ids| {
	names = folders!([])?
	Ok(
		List.keep_oks(
			names,
			|name|
				# dmPair: two uids either side of the first `_`, in either order.
				match Str.split_on(name, "_") {
					[a, b] if Uid.from_str(a).is_ok() and Uid.from_str(b).is_ok() and (
						List.contains(
							ids,
							a,
						) or List.contains(ids, b)
					) =>
						Ok({
							key: name,
							steps: [Note(Dm, name), Remove(Paths.listed([name]), Tree)],
						})
					_ => Err(Kept)
				},
		),
	)
}

## **A REMOVED MEMBER'S CHANNEL LINES**: each `channels/*.channel` with a
## line that is one of `ids` written again without it; the channel stays.
pruned_channels! : List(Str) => Try(List(Step), [Failed])
pruned_channels! = |ids| {
	names = List.keep_if(files!(["channels"])?, |n| n.ends_with(".channel"))
	pruned_in!(
		names,
		ids,
		[],
	)
}

pruned_in! : List(Str), List(Str), List(Step) => Try(List(Step), [Failed])
pruned_in! = |
	names,
	ids,
	steps,
|
	match names {
		[] => Ok(steps)
		[name, .. as more] => {
			path = Paths.listed(["channels", name])
			these = match Files.read_bytes!(path) {
				Ok(body) => {
					cut = without(body, ids)
					if cut.dropped == 0 {
						Ok([])
					} else {
						Ok([
							Note(
								ChannelMember,
								"${name.drop_suffix(".channel")} (${cut.dropped.to_str()} dropped)",
							),
							Replace(path, cut.kept),
						])
					}
				}
				Err(Missing) => Ok([])
				Err(Failed) => Err(Failed)
			}
			pruned_in!(
				more,
				ids,
				List.concat(steps, these?),
			)
		}
	}

## A member file without the lines that are one of `ids` (trimmed; blanks
## and `#` comments are never a member's), and how many went. **EVERY
## PIECE BETWEEN NEWLINES IS WRITTEN BACK WITH ONE**, the last (empty
## after a final newline) too, as the Zig wrote it: `1\n2\n9\n` less 9 is
## `1\n2\n\n`.
without : List(U8), List(Str) -> { kept : List(U8), dropped : U64 }
without = |body, ids|
	List.fold(
		List.split_on(body, '\n'),
		{ kept: [], dropped: 0 },
		|got, raw| {
			line = ZigText.trim(raw)
			member = line != [] and List.first(line) != Ok('#') and List.any(
				ids,
				|id| id.to_utf8() == line,
			)
			if member { ..got, dropped: got.dropped + 1 } else {
				..got,
				kept: List.join([
					got.kept,
					raw,
					['\n'],
				]),
			}
		},
	)

## **A KEPT MEMBER'S POINTERS INTO A CONVERSATION NOW GONE**: `last-conv`,
## `last-sessions/<conv>` and `pinned-sessions/<conv>` of each member folder
## under `users` that is a kept account's (a folder can outlive its
## account: nobody's live pointer). Gone is projected: a DM in `gone`, or a
## conversation folder not there.
dangling! : List(Accounts.Account),
List(List(U8)),
List(Str),
List(Str) => Try(
	List(Step),
	[Failed],
)
dangling! = |
	accounts,
	keep,
	ids,
	gone,
| {
	kept = List.keep_oks(
		folders!(["users"])?,
		|uid|
			if List.contains(ids, uid) {
				Err(Removed)
			} else if List.any(
				accounts,
				|a| a.id.to_str() == uid and List.contains(keep, a.name.to_utf8()),
			) {
				Ok(uid)
			} else {
				Err(NotKept)
			},
	)
	swept!(
		kept,
		gone,
		[],
	)
}

swept! : List(Str), List(Str), List(Step) => Try(List(Step), [Failed])
swept! = |
	uids,
	gone,
	steps,
|
	match uids {
		[] => Ok(steps)
		[uid, .. as more] => {
			last = Paths.listed([
				"users",
				uid,
				"last-conv",
			])
			conv = match Files.read_bytes!(last) {
				Ok(raw) => Ok(ZigText.trim(raw))
				Err(Missing) => Ok([])
				Err(Failed) => Err(Failed)
			}
			pointed = conv?
			head =
				if pointed != [] and gone_conv!(Str.from_utf8_lossy(pointed), gone)? == Gone {
					[
						Note(RefLastConv, "${uid} -> ${Str.from_utf8_lossy(pointed)}"),
						Remove(last, File),
					]
				} else {
					[]
				}
			sessions = swept_in!(
				uid,
				"last-sessions",
				RefLastSession,
				gone,
			)?
			pinned = swept_in!(
				uid,
				"pinned-sessions",
				RefPinned,
				gone,
			)?
			swept!(
				more,
				gone,
				List.join([
					steps,
					head,
					sessions,
					pinned,
				]),
			)
		}
	}

## Each file in the member's folder `sub`, named for a conversation now gone.
swept_in! : Str, Str, Kind, List(Str) => Try(List(Step), [Failed])
swept_in! = |
	uid,
	sub,
	kind,
	gone,
| {
	names = files!([
		"users",
		uid,
		sub,
	])?
	dangling_of!(
		names,
		uid,
		sub,
		kind,
		gone,
		[],
	)
}

dangling_of! : List(Str), Str, Str, Kind, List(Str), List(Step) => Try(List(Step), [Failed])
dangling_of! = |
	names,
	uid,
	sub,
	kind,
	gone,
	steps,
|
	match names {
		[] => Ok(steps)
		[name, .. as more] => {
			these =
				if gone_conv!(name, gone)? == Gone {
					[
						Note(kind, "${uid}/${sub}/${name}"),
						Remove(
							Paths.listed([
								"users",
								uid,
								sub,
								name,
							]),
							File,
						),
					]
				} else {
					[]
				}
			dangling_of!(
				more,
				uid,
				sub,
				kind,
				gone,
				List.concat(steps, these),
			)
		}
	}

## Whether conversation `conv` is gone, the removals projected: a DM in
## `gone`, or a folder not there (a DM's under the chat root, a channel's
## under `channels`). **A NAME THAT IS NO ONE PART OF A PATH IS NOT GONE**:
## nothing is swept that the walk cannot name.
gone_conv! : Str, List(Str) => Try([Gone, There], [Failed])
gone_conv! = |conv, gone|
	if List.contains(gone, conv) {
		Ok(Gone)
	} else if conv == "" or conv == "." or conv == ".." or Str.contains(conv, "/") {
		Ok(There)
	} else {
		parts = if Str.contains(conv, "_") [conv] else ["channels", conv]
		match Files.list!(Paths.listed(parts)) {
			Ok(_) => Ok(There)
			Err(Missing) => Ok(Gone)
			Err(Failed) => Err(Failed)
		}
	}

expect without(Str.to_utf8("1\n2\n9\n"), ["9"]) == { kept: Str.to_utf8("1\n2\n\n"), dropped: 1 }
expect without(Str.to_utf8("# 9\n 9 \n19\n"), ["9"]) == {
	kept: Str.to_utf8("# 9\n19\n\n"),
	dropped: 1,
}
expect without(Str.to_utf8("1\n2"), ["3"]) == { kept: Str.to_utf8("1\n2\n"), dropped: 0 }
expect newest(Str.to_utf8("")) == Err(Undated)
