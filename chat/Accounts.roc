## WHO HAS AN ACCOUNT, WHO MAY USE THE CHAT, AND WHAT THEY ARE CALLED
## (angry-gopher users.zig `principalExists`, `principalAuthorized`,
## `getUserName`, `listAuthorized`): the lookups over
## every account as the host hands them (Host.list_accounts!, asked once a
## request). Pure: angry-gopher's chat_twin_test.zig holds the lookups to
## their Zig over account trees on disk, and its identityRun freezes the
## door (`admits`) to the Zig's principalAuthorized.
##
## **ONLY CANONICAL IDS ARE ACCOUNTS HERE**: the host hands the folders
## named as a counter names one (digits, the first not zero), as
## listAuthorized and listUserIDs keep them. principalExists and getUserName
## took any id and looked for its folder, so a `007` folder answered for
## `007`; every id here is a Uid (canonical by its type), decoded where the
## host hands it (main's load_accounts! and load_uid!).
import Paths
import Uid
import Bytes

Accounts := [].{

	## One account: its id (its folder's name), its kind, and its `name`
	## file's text as getUserName reads it (`stored_name`; "" when it has
	## none). The kind is the host's:
	## which account is the agent is decided there, once. A kind of
	## `Unreadable` is a password whose stat failed; a `name_read` of
	## `Unreadable` a name that would not read (its `name` empty, and never
	## taken for one).
	Account : {
		id : Uid,
		kind : Kind,
		name : Str,
		name_read : [Found, Unreadable],
	}

	## An account's kind as the host lists it.
	Kind : [
		Agent,
		Guest,
		Member,
		Unreadable,
	]

	## **A LOOKUP THAT NEEDED A READ THAT FAILED HAS NO ANSWER**: account
	## `id`'s kind or name would not read, so the request fails with that
	## read's own error (Host.fail!), as the Zig failed it. Never "no such
	## account", never a name of "".
	Unreadable : [KindUnreadable(Uid), NameUnreadable(Uid)]

	## **WHO MAY USE THE CHAT** (angry-gopher users.zig `userIsAuthorized`):
	## a member or the agent, never a guest. The door (`admits`) and the
	## roster (`authorized`) both ask it. Which account is the agent is the
	## host's to say, in its kind.
	can_use_chat : Kind -> Bool
	can_use_chat = |kind| kind == Member or kind == Agent

	## **THE DOOR'S DECISION** (users.zig `principalAuthorized`, which the
	## Zig's chat asked of the id the host verified): `asking`, as the host
	## said it, may use the chat when its account `can_use_chat`. An id that is
	## no canonical uid, or names no account, is `Refused`, as is a guest.
	## **AN ACCOUNT WHOSE KIND WILL NOT READ IS NO ANSWER**: the request fails
	## with that read's error (`KindUnreadable`), as principalAuthorized's
	## stat of the password failed it.
	admits : List(Account), List(U8) -> Try([Admitted, Refused], Unreadable)
	admits = |accounts, asking|
		match Uid.from_utf8(asking) {
			Err(NotAUid) => Ok(Refused)
			Ok(id) =>
				match List.keep_if(accounts, |a| a.id == id) {
					[] => Ok(Refused)
					[a, ..] =>
						if a.kind == Unreadable {
							Err(KindUnreadable(id))
						} else if can_use_chat(a.kind) {
							Ok(Admitted)
						} else {
							Ok(Refused)
						}
				}
		}

	## principalExists (userExists): `id` is one when it is among
	## `accounts`, whatever its kind (a guest's DM is opened on purpose).
	## **AN ACCOUNT THAT WILL NOT READ EXISTS**: principalExists looks at the
	## folder alone, and the host listed it.
	has_account : List(Account), Uid -> Bool
	has_account = |accounts, id| List.any(accounts, |a| a.id == id)

	## getUserName: account `id`'s name, its trailing CRs and LFs cut, or ""
	## when it has no name file or there is no such account; `NameUnreadable`
	## when its name would not read (getUserName's error), whatever its
	## kind. **A MEMBER WITH NO NAME FILE READS "", ON PURPOSE** (metal-vmm
	## QUEUE 156(i)): an account is made name first, so one with a password
	## and no name is a release cut short, and that member must still sign in
	## by cookie to release again. What must not take "" for a name refuses
	## it.
	name : List(Account), Uid -> Try(Str, Unreadable)
	name = |accounts, id|
		match List.keep_if(accounts, |a| a.id == id) {
			[a, ..] =>
				match a.name_read {
					Found => Ok(a.name)
					Unreadable => Err(NameUnreadable(id))
				}
			[] => Ok("")
		}

	## **AN ACCOUNT DECODED WHERE THE HOST HANDS IT**: its id a Uid, its
	## name text (`stored_name`'s cut first). The host lists only folders a
	## counter named, so an id that is not one is corrupt data, `NotAUid`
	## with the folder's bytes, and fails the listing. **A NAME THAT IS NOT
	## UTF-8 IS ONE ACCOUNT'S** (metal-vmm QUEUE 267): the account is listed
	## with its name `Unreadable`, as a name that would not read is, so only
	## a lookup of that name fails, never every member's chat. (The host
	## lists such a name as unreadable itself, with error.NotUtf8 kept.)
	from_host : {
		id : List(U8),
		kind : Kind,
		name : List(U8),
		name_read : [Found, Unreadable],
	} -> Try(Account, [NotAUid(List(U8))])
	from_host = |a|
		match (Uid.from_utf8(a.id), Str.from_utf8(stored_name(a.name))) {
			(Ok(id), Ok(text)) => Ok({
				id,
				kind: a.kind,
				name: text,
				name_read: a.name_read,
			})
			(Ok(id), Err(_)) => Ok({
				id,
				kind: a.kind,
				name: "",
				name_read: Unreadable,
			})
			(Err(_), _) => Err(NotAUid(a.id))
		}

	## **LISTAUTHORIZED**: every member and the agent, never a guest, each
	## with its name, by numeric id as std.mem.sort orders them: the id
	## parsed as an i64, one too big for it counting as 0 (`catch 0`), so it
	## sorts first; a tie (only such ids) kept in the host's order, the
	## disk's, as a stable sort keeps it.
	##
	## **ONE ACCOUNT THAT WILL NOT READ FAILS THE ROSTER, NEVER LEFT OUT**:
	## listAuthorized read, in the disk's order, every account's password
	## (the agent's too), then the name of each member and the agent, and
	## failed on the first read that failed. So the first account, in the
	## host's order, whose kind is unreadable, or whose name is and which is
	## not a guest, is the roster's failure; a guest's name is never read.
	authorized : List(Account) -> Try(List({ id : Uid, name : Str }), Unreadable)
	authorized = |accounts|
		match List.keep_if(
			accounts,
			|a| a.kind == Unreadable or (can_use_chat(a.kind) and a.name_read == Unreadable),
		) {
			[a, ..] => Err(if a.kind == Unreadable KindUnreadable(a.id) else NameUnreadable(a.id))
			[] => Ok(roster(accounts))
		}

	## **A NAME THAT WILL NOT READ IS ITS MEMBER'S ROW ALONE** (/chat/recent,
	## metal-vmm QUEUE 267, 277): the roster as `authorized` orders it, each
	## member's name `Unreadable` where it would not read, so only what is
	## labelled by it is left out; an account whose kind will not read still
	## fails it, as listAuthorized did.
	roster_named : List(Account) -> Try(
		List({ id : Uid, name : Try(Str, [Unreadable]) }),
		Unreadable,
	)
	roster_named = |accounts|
		match List.keep_if(accounts, |a| a.kind == Unreadable) {
			[a, ..] => Err(KindUnreadable(a.id))
			[] => {
				unnamed = List.keep_if(
					accounts,
					|a| a.name_read == Unreadable,
				)
					|> List.map(|a| a.id)
				Ok(
					List.map(
						roster(accounts),
						|u| {
							id: u.id,
							name: if List.contains(unnamed, u.id) Err(Unreadable) else Ok(u.name),
						},
					),
				)
			}
		}

	roster : List(Account) -> List({ id : Uid, name : Str })
	roster = |accounts|
		# Never an unreadable kind: both callers failed on one first.
		List.keep_if(accounts, |a| can_use_chat(a.kind))
			|> List.map_with_index(
				|a, i| {
					a,
					i,
					n: Paths.atoi_or0(a.id.to_str().to_utf8()),
				},
			)
			|> List.sort_with(
				|x, y|
					if x.n < y.n {
						Before
					} else if x.n > y.n {
						After
					} else if x.i < y.i {
						Before
					} else if x.i > y.i {
						After
					} else {
						Same
					},
			)
			|> List.map(|x| { id: x.a.id, name: x.a.name })
}

## The name file's bytes as getUserName reads them: trailing CRs and
## LFs cut, nothing else (inner and leading whitespace kept).
stored_name : List(U8) -> List(U8)
stored_name = |bytes| Bytes.trim_end(bytes, ['\r', '\n'])

expect Accounts.from_host({
	id: Str.to_utf8("7"),
	kind: Member,
	name: Str.to_utf8("caf\u(e9)\r\n"),
	name_read: Found,
}).map_ok(|a| a.name) == Ok("caf\u(e9)")
expect Accounts.from_host({
	id: Str.to_utf8("7"),
	kind: Member,
	name: [0x41, 0xff],
	name_read: Found,
}).map_ok(|a| (a.name, a.name_read)) == Ok(("", Unreadable))
expect Accounts.from_host({
	id: Str.to_utf8("07"),
	kind: Member,
	name: [0xff],
	name_read: Found,
}) == Err(NotAUid(Str.to_utf8("07")))

## The door's decision over a member, the agent, a guest, an account whose
## kind will not read, an id no account has, and one no uid.
expect {
	a = |id, kind| Accounts.from_host({
		id: Str.to_utf8(id),
		kind,
		name: [],
		name_read: Found,
	})
	all = List.keep_oks(
		[
			a("1", Member),
			a("3", Agent),
			a("5", Guest),
			a("7", Unreadable),
		],
		|x| x,
	)
	is = |id| Accounts.admits(all, Str.to_utf8(id))
	let_in = is("1") == Ok(Admitted) and is("3") == Ok(Admitted)
	sent_away = List.all(
		[
			is("5"),
			is("9"),
			is("007"),
			is(""),
		],
		|got| got == Ok(Refused),
	)
	let_in and sent_away and is("7").is_err()
}
