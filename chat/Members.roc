## **WHO IS ASKING, AND THE ACCOUNTS** (metal-vmm QUEUE 300): the member's
## id and name as the host hands them, every account listed once a request,
## and the request failed with an account's own error when a lookup needs a
## read that failed. Every route that names a member asks here: main's, the
## docs', the admin retire's.
import pf.Host
import Accounts
import Uid

Members := [].{

	## **THE DOOR: WHO MAY USE THE CHAT IS DECIDED HERE** (angry-gopher
	## users.zig `principalAuthorized` as the chat asked it): the host says
	## who is asking, its session cookie or API key verified there
	## (Host.identify!), and the accounts listed (`load_accounts!`) say what
	## that one is (Accounts.admits). `Admitted` with every account, **LISTED
	## ONCE FOR THE WHOLE REQUEST**: each route looks up in these, so none
	## asks the host again. `Outsider` for a stranger, a guest or an id that
	## names no account (sent to sign in); `Failed` when identifying or
	## listing failed, or the asker's own kind would not read (the request
	## has failed, with that error).
	admit! : {} => [
		Admitted(List(Accounts.Account)),
		Outsider,
		Failed,
	]
	admit! = |{}| {
		asking = Host.identify!({})
		match asking.status {
			Failed => Failed
			Stranger => Outsider
			Known =>
				match load_accounts!({}) {
					Err(Failed) => Failed
					Ok(all) =>
						match Accounts.admits(all, asking.uid) {
							Ok(Admitted) => Admitted(all)
							Ok(Refused) => Outsider
							Err(why) => {
								fail_unreadable!(why)
								Failed
							}
						}
				}
		}
	}

	## Every account, as the host lists them. `Failed` when they could not be
	## listed: the request has failed, and no lookup is made on nothing. An
	## account that would not read is among them, and fails the request only
	## when a lookup needs it (`fail_if_unreadable!`): never "no such account".
	load_accounts! : {} => Try(List(Accounts.Account), [Failed])
	load_accounts! = |{}| {
		got = Host.list_accounts!({})
		match got.status {
			# **EACH ID AND NAME DECODED HERE, AT THE DOOR**
			# (Accounts.from_host): one that is no uid fails the request
			# (NotAUid, about the account); a name that is not UTF-8 is
			# that account's alone, listed as unreadable.
			Found =>
				match List.map_try(got.accounts, Accounts.from_host) {
					Ok(all) => Ok(all)
					Err(NotAUid(bad)) => {
						Host.fail!(NotAUid, bad)
						Err(Failed)
					}
				}
			Failed => Err(Failed)
		}
	}

	## The member's name (getUserName of their own id), from the accounts.
	## `Failed` when it would not read (the request has failed with its error).
	load_viewer! : List(Accounts.Account) => Try(Str, [Failed])
	load_viewer! = |all| {
		me = load_uid!({})?
		fail_if_unreadable!(Accounts.name(all, me))
	}

	## **THE MEMBER'S ID, DECODED WHERE THE HOST HANDS IT** (Host.read_uid!): a
	## session is signed only for an id a counter made, so one that is no
	## canonical uid fails the request (NotAUid, about the id), and `Failed`.
	load_uid! : {} => Try(Uid, [Failed])
	load_uid! = |{}| {
		bytes = Host.read_uid!({})
		match Uid.from_utf8(bytes) {
			Ok(uid) => Ok(uid)
			Err(NotAUid) => {
				Host.fail!(NotAUid, bytes)
				Err(Failed)
			}
		}
	}

	## A lookup's answer, or, when it needed an account's read that failed, the
	## request failed with that read's error (`fail_unreadable!`) and `Failed`.
	fail_if_unreadable! : Try(a, Accounts.Unreadable) => Try(a, [Failed])
	fail_if_unreadable! = |looked|
		match looked {
			Ok(answer) => Ok(answer)
			Err(why) => {
				fail_unreadable!(why)
				Err(Failed)
			}
		}

	## **THE REQUEST FAILS WITH THE ACCOUNT'S OWN ERROR**: a lookup needed
	## account `id`'s kind or name, which `load_accounts!` listed as unreadable, so
	## the host fails the request with the error that read failed with, as the
	## Zig's own read of it did.
	fail_unreadable! : Accounts.Unreadable => {}
	fail_unreadable! = |why|
		match why {
			KindUnreadable(id) => Host.fail!(KindUnreadable, id.to_str().to_utf8())
			NameUnreadable(id) => Host.fail!(NameUnreadable, id.to_str().to_utf8())
		}

}
