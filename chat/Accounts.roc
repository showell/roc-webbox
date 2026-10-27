## WHO HAS AN ACCOUNT, AND WHAT THEY ARE CALLED (angry-gopher users.zig
## `principalExists`, `getUserName`, `listAuthorized`): the lookups over
## every account as the host hands them (Host.accounts!, asked at most once
## a request). Pure: angry-gopher's chat_twin_test.zig holds each to its Zig
## over account trees on disk.
##
## **ONLY CANONICAL IDS ARE ACCOUNTS HERE**: the host hands the folders
## named as a counter names one (digits, the first not zero), as
## listAuthorized and listUserIDs keep them. principalExists and getUserName
## took any id and looked for its folder, so a `007` folder answered for
## `007`; every id here is a Uid (canonical by its type), decoded where the
## host hands it (main's accounts! and me!).
import Paths
import Uid
import ZigText

Accounts := [].{

	## One account: its id (its folder's name), its kind, and its `name`
	## file's text as getUserName reads it (`stored_name`; "" when it has
	## none). The kind is the host's:
	## which account is the agent is decided there, once. A kind of
	## `Unreadable` is a password whose stat failed; a `name_read` of
	## `Unreadable` a name that would not read (its `name` empty, and never
	## taken for one).
	Account : { id : Uid, kind : [Agent, Guest, Member, Unreadable], name : Str, name_read : [Found, Unreadable] }

	## **A LOOKUP THAT NEEDED A READ THAT FAILED HAS NO ANSWER**: account
	## `id`'s kind or name would not read, so the request fails with that
	## read's own error (Host.fail!), as the Zig failed it. Never "no such
	## account", never a name of "".
	Unreadable : [KindUnreadable(Uid), NameUnreadable(Uid)]

	## principalExists (userExists): `id` is one when it is among
	## `accounts`, whatever its kind (a guest's DM is opened on purpose).
	## **AN ACCOUNT THAT WILL NOT READ EXISTS**: principalExists looks at the
	## folder alone, and the host listed it.
	exists : List(Account), Uid -> Bool
	exists = |accounts, id| List.any(accounts, |a| a.id == id)

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

	## The name file's bytes as getUserName reads them: trailing CRs and
	## LFs cut, nothing else (inner and leading whitespace kept).
	stored_name : List(U8) -> List(U8)
	stored_name = |bytes| List.drop_last(bytes, ZigText.count_back_while(bytes, |c| c == '\r' or c == '\n', 0))

	## **AN ACCOUNT DECODED WHERE THE HOST HANDS IT**: its id a Uid, its
	## name text (`stored_name`'s cut first). The host lists only folders a
	## counter named, and a name is UTF-8 when it is set (users.zig
	## validateUserName), so either failing is corrupt data: `NotAUid` or
	## `NameNotUtf8`, each with the folder's bytes.
	from_host : { id : List(U8), kind : [Agent, Guest, Member, Unreadable], name : List(U8), name_read : [Found, Unreadable] } -> Try(Account, [NotAUid(List(U8)), NameNotUtf8(List(U8))])
	from_host = |a|
		match (Uid.from_utf8(a.id), Str.from_utf8(stored_name(a.name))) {
			(Ok(id), Ok(text)) => Ok({ id, kind: a.kind, name: text, name_read: a.name_read })
			(Err(_), _) => Err(NotAUid(a.id))
			(Ok(_), Err(_)) => Err(NameNotUtf8(a.id))
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
		match List.keep_if(accounts, |a| a.kind == Unreadable or (a.kind != Guest and a.name_read == Unreadable)) {
			[a, ..] => Err(if a.kind == Unreadable KindUnreadable(a.id) else NameUnreadable(a.id))
			[] => Ok(roster(accounts))
		}

	roster : List(Account) -> List({ id : Uid, name : Str })
	roster = |accounts|
		List.keep_if(accounts, |a| a.kind != Guest)
			|> List.map_with_index(|a, i| { a, i, n: Paths.atoi_or0(a.id.to_str().to_utf8()) })
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

expect Accounts.from_host({ id: Str.to_utf8("7"), kind: Member, name: Str.to_utf8("caf\u(e9)\r\n"), name_read: Found }).map_ok(|a| a.name) == Ok("caf\u(e9)")
expect Accounts.from_host({ id: Str.to_utf8("7"), kind: Member, name: [0x41, 0xff], name_read: Found }) == Err(NameNotUtf8(Str.to_utf8("7")))
expect Accounts.from_host({ id: Str.to_utf8("07"), kind: Member, name: [0xff], name_read: Found }) == Err(NotAUid(Str.to_utf8("07")))
