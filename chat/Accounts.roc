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
## `007`; every id the Roc looks up has passed Paths.canonical_uid first
## (a DM's other half and its partner: Paths.participant), or is the
## member's own (the session's, signed only for an id a counter made).
import Paths
import ZigText

Accounts := [].{
	## One account: its id (its folder's name), its kind, and its `name`
	## file's bytes as stored ("" when it has none). The kind is the host's:
	## which account is the agent is decided there, once.
	Account : { id : List(U8), kind : [Agent, Guest, Member], name : List(U8) }

	## principalExists (userExists): an id empty once trimmed of " \t\r\n"
	## is none; any other is one when it is among `accounts`, whatever its
	## kind (a guest's DM is opened on purpose).
	exists : List(Account), List(U8) -> Bool
	exists = |accounts, id| ZigText.trim(id) != [] and List.any(accounts, |a| a.id == id)

	## getUserName: account `id`'s name, its trailing CRs and LFs cut, or ""
	## when it has no name file or there is no such account. **A MEMBER WITH
	## NO NAME FILE READS "", ON PURPOSE** (metal-vmm QUEUE 156(i)): an
	## account is made name first, so one with a password and no name is a
	## release cut short, and that member must still sign in by cookie to
	## release again. What must not take "" for a name refuses it.
	name : List(Account), List(U8) -> List(U8)
	name = |accounts, id|
		match List.keep_if(accounts, |a| a.id == id) {
			[a, ..] => stored_name(a.name)
			[] => []
		}

	## The name file's bytes as getUserName reads them: trailing CRs and
	## LFs cut, nothing else (inner and leading whitespace kept).
	stored_name : List(U8) -> List(U8)
	stored_name = |bytes| List.drop_last(bytes, ZigText.count_back_while(bytes, |c| c == 13 or c == 10, 0))

	## **LISTAUTHORIZED**: every member and the agent, never a guest, each
	## with its name, by numeric id as std.mem.sort orders them: the id
	## parsed as an i64, one too big for it counting as 0 (`catch 0`), so it
	## sorts first; a tie (only such ids) kept in the host's order, the
	## disk's, as a stable sort keeps it.
	authorized : List(Account) -> List({ id : List(U8), name : List(U8) })
	authorized = |accounts|
		List.keep_if(accounts, |a| a.kind != Guest)
		|> List.map_with_index(|a, i| { a, i, n: Paths.atoi_or0(a.id) })
		|> List.sort_with(|x, y|
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
			})
		|> List.map(|x| { id: x.a.id, name: stored_name(x.a.name) })
}
