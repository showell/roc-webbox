## **THE ADMIN ACTIONS, AND WHO MAY PERFORM THEM** (the Roc chat's auth
## design, sections 9 and 11): a closed set of named actions, one decision
## for all of them, and an audit record of every attempt, permitted or
## refused, for the host to store and admins to read. An admin manages
## accounts and reads no one's mail: nothing here reaches a resource's
## contents, and an admin's sight is Access's like anyone's. A key acts on
## members' accounts only: acting on an admin, or on an admin's agent or
## bot, or setting a role, takes a human admin's own session, so one stolen
## admin key cannot remove the other admins. Generic over the resource's id
## only because a key is (ApiKey.Key). Pure.
import ApiKey
import Principal
import Session
import Stored

Admin := [].{

	## **THE ACTIONS**, each a pure decision here and a host primitive later.
	Action : [
		## Every account, human, agent and bot.
		ListAccounts,

		## Retire an account, a human's or an agent's or a bot's.
		Retire(Principal.Id),

		## Revoke every key acting as a principal.
		RevokeKeys(Principal.Id),

		## End every sign-in session of a human ("log out everywhere").
		RevokeSessions(Principal.GitHubId),

		## Make a human an admin, or a member. Never one's own role, and
		## only from a session.
		SetRole({ human : Principal.GitHubId, role : Principal.Role }),

		## Read the operator's counters and logs.
		ReadCounters,
	]

	## **HOW THE ACTOR CAME IN**: a browser's session, which must be live
	## now; or an API key.
	Credential(id) : [
		Session(Session),
		Key(ApiKey.Key(id)),
	]

	## Why an admin action is refused.
	Refusal : [
		## The session's human is not among the accounts.
		NoSuchPrincipal,

		## The session is over (idle, or past its week).
		SessionExpired,

		## The session's human is not an admin now.
		NotAdmin,

		## The key may not administer (Admin scope off, not live, or its
		## principal without admin authority).
		KeyRefused(ApiKey.Refusal),

		## The action would retire the actor, or the admin its authority
		## comes from: no admin locks the admins out by one action.
		RetiresOwnAuthority,

		## The action would set the role of the actor's own human.
		SetsOwnRole,

		## A key asked to act on an admin, or on an admin's agent or bot,
		## or to set a role: that takes a human admin's own session.
		NeedsSession,
	]

	## **THE AUDIT RECORD**: who (the principal the credential names), by
	## which session or key (its public id, never a secret), what, when,
	## and the verdict. Made for every attempt, so a surprising refusal is
	## on the record too.
	Audit : {
		who : Principal.Id,
		via : [Session(Principal.SessionId), Key(Principal.KeyId)],
		action : Admin.Action,
		at : I64,
		verdict : [Permitted, Refused(Admin.Refusal)],
	}

	## **MAY THIS CREDENTIAL PERFORM THIS ACTION, NOW?** The actor must
	## have admin authority as the accounts say now: by a session, live and
	## an admin human's; by a key, one ApiKey's `administers` permits (an
	## admin scope, live, acting as an admin human or an agent an admin
	## owns). Then the action must not retire the actor or the admin behind
	## it, nor set their own role; and by a key, it must not touch an admin
	## or an admin's agent or bot, nor set a role. The answer is the audit
	## record, verdict and all.
	decide : {
		credential : Admin.Credential(id),
		action : Admin.Action,
		accounts : List(Principal),
		now : I64,
	} -> Admin.Audit
		where [id.is_eq : id, id -> Bool]
	decide = |
		{
			credential,
			action,
			accounts,
			now,
		},
	| {
		(who, via) =
			match credential {
				Session(s) => (Principal.Id.Human(s.human()), Session(s.id()))
				Key(key) => (key.acts_as(), Key(key.id()))
			}
		verdict =
			match authorized({
				credential,
				accounts,
				now,
			}) {
				Refused(why) => Refused(why)
				Admitted(actor) =>
					if is_own_authority(action, actor) {
						Refused(RetiresOwnAuthority)
					} else if is_own_role(action, actor) {
						Refused(SetsOwnRole)
					} else {
						match credential {
							Session(_) => Permitted
							Key(_) =>
								if is_session_only(action, accounts) {
									Refused(NeedsSession)
								} else {
									Permitted
								}
						}
					}
			}
		{
			who,
			via,
			action,
			at: now,
			verdict,
		}
	}
}

## The actor, when the credential carries admin authority now.
authorized : {
	credential : Admin.Credential(id),
	accounts : List(Principal),
	now : I64,
} -> [Admitted(Principal), Refused(Admin.Refusal)]
	where [id.is_eq : id, id -> Bool]
authorized = |
	{
		credential,
		accounts,
		now,
	},
|
	match credential {
		Session(session) =>
			match session.admit({ accounts, now }) {
				Refused(IdleExpired) | Refused(AbsoluteExpired) => Refused(SessionExpired)
				Refused(NoSuchAccount) => Refused(NoSuchPrincipal)
				Admitted({ principal, write: _ }) =>
					match principal {
						Human(h) =>
							match h.role {
								Admin => Admitted(principal)
								Member => Refused(NotAdmin)
							}
						Agent(_) | Bot(_) => crash "Admin.authorized: a session admits a human"
					}
			}
		Key(key) =>
			match key.administers({ accounts, now }) {
				Refused(why) => Refused(KeyRefused(why))
				Permitted =>
					match Principal.find(accounts, key.acts_as()) {
						Ok(actor) => Admitted(actor)
						Err(NoSuchPrincipal) => crash "Admin.authorized: a key's principal is gone"
					}
			}
	}

## `action` retires `actor` itself, or the human its authority comes from.
is_own_authority : Admin.Action, Principal -> Bool
is_own_authority = |action, actor|
	match action {
		Retire(target) => {
			backer = Principal.Id.Human(Principal.answers_to(actor))
			target == Principal.id(actor) or target == backer
		}
		ListAccounts | RevokeKeys(_) | RevokeSessions(_) | SetRole(_) | ReadCounters => Bool.False
	}

## `action` sets the role of the human `actor` answers to.
is_own_role : Admin.Action, Principal -> Bool
is_own_role = |action, actor|
	match action {
		SetRole({ human, role: _ }) => human == Principal.answers_to(actor)
		ListAccounts | Retire(_) | RevokeKeys(_) | RevokeSessions(_) | ReadCounters => Bool.False
	}

## **`action` TAKES A SESSION**: it sets a role, or acts on an admin, or on
## an agent or a bot an admin owns, as the accounts say now.
is_session_only : Admin.Action, List(Principal) -> Bool
is_session_only = |action, accounts|
	match action {
		SetRole(_) => Bool.True
		Retire(target) | RevokeKeys(target) => is_admins(accounts, target)
		RevokeSessions(human) => is_admins(accounts, Principal.Id.Human(human))
		ListAccounts | ReadCounters => Bool.False
	}

## The principal `target` is an admin, or answers to one, among `accounts`.
## A target no account holds answers to nobody: acting on it touches no
## admin.
is_admins : List(Principal), Principal.Id -> Bool
is_admins = |accounts, target|
	match Principal.find(accounts, target) {
		Err(NoSuchPrincipal) => Bool.False
		Ok(found) =>
			match Principal.find(accounts, Principal.Id.Human(Principal.answers_to(found))) {
				Ok(Human(h)) =>
					match h.role {
						Admin => Bool.True
						Member => Bool.False
					}
				Ok(Agent(_)) | Ok(Bot(_)) => crash "Admin.is_admins: a human's id finds a human"
				Err(NoSuchPrincipal) => Bool.False
			}
	}

# The cast:
#   boss        an admin human
#   ann         a member human
#   cal         another admin human
#   boss_agent  an agent boss owns, with an admin-only key
#   ann_agent   an agent ann owns, with a read-and-post key
#   cal_agent   an agent cal owns
gid : U64 -> Principal.GitHubId
gid = |n|
	match Principal.GitHubId.from_u64(n) {
		Ok(id) => id
		Err(NotAnId) => crash "gid: a test's GitHub id is not 0"
	}

aid : U64 -> Principal.AgentId
aid = |n|
	match Principal.AgentId.from_u64(n) {
		Ok(id) => id
		Err(NotAnId) => crash "aid: a test's agent id is not 0"
	}

kid : U64 -> Principal.KeyId
kid = |n|
	match Principal.KeyId.from_u64(n) {
		Ok(id) => id
		Err(NotAnId) => crash "kid: a test's key id is not 0"
	}

sid : U64 -> Principal.SessionId
sid = |n|
	match Principal.SessionId.from_u64(n) {
		Ok(id) => id
		Err(NotAnId) => crash "sid: a test's session id is not 0"
	}

## A test's human: GitHub id `n`, its role.
person : U64, Principal.Role -> Principal
person = |n, role|
	Principal.Human({
		id: gid(n),
		login: "h${n.to_str()}",
		name: "H${n.to_str()}",
		role,
	})

## A test's agent: its id, and its owner's GitHub id.
agent : { id : U64, owner : U64 } -> Principal
agent = |{ id, owner }|
	Principal.Agent({
		id: aid(id),
		name: "a${id.to_str()}",
		owner: gid(owner),
	})

boss : Principal
boss = person(1, Admin)

boss_demoted : Principal
boss_demoted = person(1, Member)

ann : Principal
ann = person(2, Member)

cal : Principal
cal = person(4, Admin)

boss_agent : Principal
boss_agent = agent({ id: 1, owner: 1 })

ann_agent : Principal
ann_agent = agent({ id: 3, owner: 2 })

cal_agent : Principal
cal_agent = agent({ id: 5, owner: 4 })

accounts : List(Principal)
accounts = [
	boss,
	ann,
	cal,
	boss_agent,
	ann_agent,
	cal_agent,
]

admin_only : ApiKey.Scope(Str)
admin_only = {
	read: Off,
	post: Off,
	admin: On,
}

plain : ApiKey.Scope(Str)
plain = {
	read: On(Everywhere),
	post: On(Everywhere),
	admin: Off,
}

## A test's token hash: every byte `b`.
token : U8 -> Stored.SecretHash
token = |b|
	match Stored.SecretHash.from_bytes(List.repeat(b, 32)) {
		Ok(h) => h
		Err(NotAHash) => crash "token: 32 bytes are a hash"
	}

## Human `who`'s session `n`, signed in at `at`.
session_of : {
	n : U64,
	who : U64,
	at : I64,
} -> Session
session_of = |
	{
		n,
		who,
		at,
	},
|
	Session.start({
		id: sid(n),
		human: gid(who),
		token_hash: token(1),
		now: at,
	})

## Key number `key` acting as `acts_as`, granted from its owner's session,
## expiring at 1000.
key_for : Principal, { scope : ApiKey.Scope(Str), key : U64 } -> ApiKey.Key(Str)
key_for = |acts_as, { scope, key }|
	match ApiKey.Key.issue(
		{
			granter: Session(
				session_of({
					n: 9,
					who: Principal.answers_to(acts_as).to_u64(),
					at: 0,
				}),
			),
			acts_as: Principal.id(acts_as),
			scope,
			accounts,
			now: 0,
		},
		{ key: kid(key), expires: At(1000) },
	) {
		Ok(made) => made
		Err(Refused(_)) => crash "key_for: a test's key is grantable"
	}

# The credentials: sessions signed in at 0, one at 500 less a day (idle
# by 500, when the table is decided).
boss_session : Admin.Credential(Str)
boss_session = Session(
	session_of({
		n: 1,
		who: 1,
		at: 0,
	}),
)

ann_session : Admin.Credential(Str)
ann_session = Session(
	session_of({
		n: 2,
		who: 2,
		at: 0,
	}),
)

boss_idle_session : Admin.Credential(Str)
boss_idle_session = Session(
	session_of({
		n: 3,
		who: 1,
		at: 500 - Session.idle_secs,
	}),
)

boss_agent_key : Admin.Credential(Str)
boss_agent_key = Key(key_for(boss_agent, { scope: admin_only, key: 1 }))

ann_agent_key : Admin.Credential(Str)
ann_agent_key = Key(key_for(ann_agent, { scope: plain, key: 2 }))

boss_revoked_key : Admin.Credential(Str)
boss_revoked_key = Key(key_for(boss, { scope: admin_only, key: 3 }).revoke())

Verdict : [Permitted, Refused(Admin.Refusal)]

## The audit of `credential` attempting `action` at `now`, among `among`.
Attempt : { credential : Admin.Credential(Str), action : Admin.Action }

When : { among : List(Principal), now : I64 }

audited : Attempt, When -> Admin.Audit
audited = |{ credential, action }, { among, now }|
	Admin.decide({
		credential,
		action,
		accounts: among,
		now,
	})

## Among the cast, at time 500.
usually : When
usually = { among: accounts, now: 500 }

## The verdict on `credential` attempting `action`, as usually.
verdict : Admin.Credential(Str), Admin.Action -> Verdict
verdict = |credential, action| audited({ credential, action }, usually).verdict

## The verdict on `credential` listing accounts among `among` at `now`.
lists : Admin.Credential(Str), { among : List(Principal), now : I64 } -> Verdict
lists = |credential, at| audited({ credential, action: ListAccounts }, at).verdict

# The actions.
retire_ann_agent : Admin.Action
retire_ann_agent = Retire(Principal.id(ann_agent))

retire_boss : Admin.Action
retire_boss = Retire(Principal.id(boss))

revoke_ann_keys : Admin.Action
revoke_ann_keys = RevokeKeys(Principal.id(ann))

revoke_ann_sessions : Admin.Action
revoke_ann_sessions = RevokeSessions(gid(2))

promote_ann : Admin.Action
promote_ann = SetRole({ human: gid(2), role: Admin })

retire_cal : Admin.Action
retire_cal = Retire(Principal.id(cal))

revoke_cal_agent_keys : Admin.Action
revoke_cal_agent_keys = RevokeKeys(Principal.id(cal_agent))

# ── THE ADMIN TABLE
# Every credential against every action.

# boss's session: everything but retiring boss, another admin included.
expect verdict(boss_session, ListAccounts) == Permitted
expect verdict(boss_session, retire_ann_agent) == Permitted
expect verdict(boss_session, retire_boss) == Refused(RetiresOwnAuthority)
expect verdict(boss_session, revoke_ann_keys) == Permitted
expect verdict(boss_session, revoke_ann_sessions) == Permitted
expect verdict(boss_session, promote_ann) == Permitted
expect verdict(boss_session, retire_cal) == Permitted
expect verdict(boss_session, revoke_cal_agent_keys) == Permitted
expect verdict(boss_session, ReadCounters) == Permitted

# ann's session: a member, nothing.
expect verdict(ann_session, ListAccounts) == Refused(NotAdmin)
expect verdict(ann_session, retire_ann_agent) == Refused(NotAdmin)
expect verdict(ann_session, retire_boss) == Refused(NotAdmin)
expect verdict(ann_session, revoke_ann_keys) == Refused(NotAdmin)
expect verdict(ann_session, revoke_ann_sessions) == Refused(NotAdmin)
expect verdict(ann_session, promote_ann) == Refused(NotAdmin)
expect verdict(ann_session, retire_cal) == Refused(NotAdmin)
expect verdict(ann_session, revoke_cal_agent_keys) == Refused(NotAdmin)
expect verdict(ann_session, ReadCounters) == Refused(NotAdmin)

# boss's session, a day idle: nothing.
expect verdict(boss_idle_session, ListAccounts) == Refused(SessionExpired)
expect verdict(boss_idle_session, retire_ann_agent) == Refused(SessionExpired)
expect verdict(boss_idle_session, retire_boss) == Refused(SessionExpired)
expect verdict(boss_idle_session, revoke_ann_keys) == Refused(SessionExpired)
expect verdict(boss_idle_session, revoke_ann_sessions) == Refused(SessionExpired)
expect verdict(boss_idle_session, promote_ann) == Refused(SessionExpired)
expect verdict(boss_idle_session, retire_cal) == Refused(SessionExpired)
expect verdict(boss_idle_session, revoke_cal_agent_keys) == Refused(SessionExpired)
expect verdict(boss_idle_session, ReadCounters) == Refused(SessionExpired)

# boss_agent's admin key: as boss on members' accounts, but never retiring
# boss, never another admin or their agent, and never a role.
expect verdict(boss_agent_key, ListAccounts) == Permitted
expect verdict(boss_agent_key, retire_ann_agent) == Permitted
expect verdict(boss_agent_key, retire_boss) == Refused(RetiresOwnAuthority)
expect verdict(boss_agent_key, revoke_ann_keys) == Permitted
expect verdict(boss_agent_key, revoke_ann_sessions) == Permitted
expect verdict(boss_agent_key, promote_ann) == Refused(NeedsSession)
expect verdict(boss_agent_key, retire_cal) == Refused(NeedsSession)
expect verdict(boss_agent_key, revoke_cal_agent_keys) == Refused(NeedsSession)
expect verdict(boss_agent_key, ReadCounters) == Permitted

# ann_agent's key, without admin: nothing.
expect verdict(ann_agent_key, ListAccounts) == Refused(KeyRefused(OutOfScope))
expect verdict(ann_agent_key, retire_ann_agent) == Refused(KeyRefused(OutOfScope))
expect verdict(ann_agent_key, retire_boss) == Refused(KeyRefused(OutOfScope))
expect verdict(ann_agent_key, revoke_ann_keys) == Refused(KeyRefused(OutOfScope))
expect verdict(ann_agent_key, revoke_ann_sessions) == Refused(KeyRefused(OutOfScope))
expect verdict(ann_agent_key, promote_ann) == Refused(KeyRefused(OutOfScope))
expect verdict(ann_agent_key, retire_cal) == Refused(KeyRefused(OutOfScope))
expect verdict(ann_agent_key, revoke_cal_agent_keys) == Refused(KeyRefused(OutOfScope))
expect verdict(ann_agent_key, ReadCounters) == Refused(KeyRefused(OutOfScope))

# boss's own admin key, revoked: nothing.
expect verdict(boss_revoked_key, ListAccounts) == Refused(KeyRefused(Revoked))
expect verdict(boss_revoked_key, retire_ann_agent) == Refused(KeyRefused(Revoked))
expect verdict(boss_revoked_key, retire_boss) == Refused(KeyRefused(Revoked))
expect verdict(boss_revoked_key, revoke_ann_keys) == Refused(KeyRefused(Revoked))
expect verdict(boss_revoked_key, revoke_ann_sessions) == Refused(KeyRefused(Revoked))
expect verdict(boss_revoked_key, promote_ann) == Refused(KeyRefused(Revoked))
expect verdict(boss_revoked_key, retire_cal) == Refused(KeyRefused(Revoked))
expect verdict(boss_revoked_key, revoke_cal_agent_keys) == Refused(KeyRefused(Revoked))
expect verdict(boss_revoked_key, ReadCounters) == Refused(KeyRefused(Revoked))

demoted : List(Principal)
demoted = [boss_demoted, boss_agent]

# The edges: an agent retiring itself; boss's session once boss is
# retired or demoted, and a week on; boss_agent's key once boss is
# demoted, and once expired (it expires at 1000).
expect verdict(boss_agent_key, Retire(Principal.id(boss_agent))) == Refused(RetiresOwnAuthority)
expect lists(boss_session, { among: [ann], now: 500 }) == Refused(NoSuchPrincipal)
expect lists(boss_session, { among: [boss_demoted], now: 500 }) == Refused(NotAdmin)
expect lists(boss_session, { among: accounts, now: 31536000 }) == Refused(SessionExpired)
expect lists(boss_agent_key, { among: demoted, now: 500 }) == Refused(KeyRefused(BeyondPrincipal))
expect lists(boss_agent_key, { among: accounts, now: 999 }) == Permitted
expect lists(boss_agent_key, { among: accounts, now: 1000 }) == Refused(KeyRefused(Expired))

# Setting a role: never one's own, by session or key; a demotion of another
# admin by session is allowed, and by a key is not.
expect verdict(boss_session, SetRole({ human: gid(1), role: Member })) == Refused(SetsOwnRole)
expect verdict(boss_agent_key, SetRole({ human: gid(1), role: Member })) == Refused(SetsOwnRole)
expect verdict(boss_session, SetRole({ human: gid(4), role: Member })) == Permitted
expect verdict(boss_agent_key, SetRole({ human: gid(4), role: Member })) == Refused(NeedsSession)

# A key on an admin's own side touches no admin either: boss's sessions,
# boss's agent's keys (itself included) take boss's session.
expect verdict(boss_agent_key, RevokeSessions(gid(1))) == Refused(NeedsSession)
expect verdict(boss_agent_key, RevokeKeys(Principal.id(boss_agent))) == Refused(NeedsSession)
expect verdict(boss_agent_key, RevokeSessions(gid(4))) == Refused(NeedsSession)
# A target no account holds touches no admin.
expect verdict(boss_agent_key, RevokeKeys(Principal.Id.Agent(aid(9)))) == Permitted

# ── THE AUDIT RECORD
# Who, by which session or key, what, when: for a permitted action and a
# refused one alike.
permitted_audit : Admin.Audit
permitted_audit = audited(
	{ credential: boss_agent_key, action: revoke_ann_keys },
	{ among: accounts, now: 500 },
)

expect permitted_audit.who == Principal.id(boss_agent)
expect permitted_audit.via == Key(kid(1))
expect permitted_audit.action == revoke_ann_keys
expect permitted_audit.at == 500
expect permitted_audit.verdict == Permitted

refused_audit : Admin.Audit
refused_audit = audited(
	{ credential: ann_session, action: retire_boss },
	{ among: accounts, now: 77 },
)

expect refused_audit.who == Principal.id(ann)
expect refused_audit.via == Session(sid(2))
expect refused_audit.action == retire_boss
expect refused_audit.at == 77
expect refused_audit.verdict == Refused(NotAdmin)

role_audit : Admin.Audit
role_audit = audited(
	{ credential: boss_session, action: promote_ann },
	{ among: accounts, now: 600 },
)

expect role_audit.who == Principal.id(boss)
expect role_audit.via == Session(sid(1))
expect role_audit.action == promote_ann
expect role_audit.verdict == Permitted
