## **THE ADMIN ACTIONS, AND WHO MAY PERFORM THEM** (the Roc chat's auth
## design, section 9): a closed set of named actions, one decision for all
## of them, and an audit record of every attempt, permitted or refused, for
## the host to store and admins to read. An admin manages accounts and
## reads no one's mail: nothing here reaches a resource's contents, and an
## admin's sight is Access's like anyone's. Generic over the resource's id
## only because a key is (ApiKey.Key). Pure.
import ApiKey
import Principal

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

		## Read the operator's counters and logs.
		ReadCounters,
	]

	## **HOW THE ACTOR CAME IN**: a browser's session (checked live by the
	## host and the Roc at the door), with the principal it signed in as;
	## or an API key.
	Credential(id) : [
		Session({ id : Principal.SessionId, acts_as : Principal.Id }),
		Key(ApiKey.Key(id)),
	]

	## Why an admin action is refused.
	Refusal : [
		## The session's principal is not among the accounts.
		NoSuchPrincipal,

		## A session acting as an agent or a bot: they never sign in.
		SessionNotHuman,

		## The session's human is not an admin now.
		NotAdmin,

		## The key may not administer (Admin scope off, not live, or its
		## principal without admin authority).
		KeyRefused(ApiKey.Refusal),

		## The action would retire the actor, or the admin its authority
		## comes from: no admin locks the admins out by one action.
		RetiresOwnAuthority,
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
	## have admin authority as the accounts say now: by a session, an
	## admin human; by a key, one ApiKey.decide lets `Administer` (an admin
	## scope, live, acting as an admin human or an agent an admin owns).
	## Then the action must not retire the actor or the admin behind it.
	## The answer is the audit record, verdict and all.
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
				Session(s) => (s.acts_as, Session(s.id))
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
					if is_own_authority(action, actor) Refused(RetiresOwnAuthority) else Permitted
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
		Session(s) =>
			match Principal.find(accounts, s.acts_as) {
				Err(NoSuchPrincipal) => Refused(NoSuchPrincipal)
				Ok(Agent(_)) | Ok(Bot(_)) => Refused(SessionNotHuman)
				Ok(Human(h)) =>
					match h.role {
						Admin => Admitted(Human(h))
						Member => Refused(NotAdmin)
					}
			}
		Key(key) =>
			match key.decide({
				accounts,
				action: Administer,
				now,
			}) {
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
		ListAccounts | RevokeKeys(_) | RevokeSessions(_) | ReadCounters => Bool.False
	}

# The cast:
#   boss        an admin human
#   ann         a member human
#   boss_agent  an agent boss owns, with an admin-only key
#   ann_agent   an agent ann owns, with a read-and-post key
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

boss_agent : Principal
boss_agent = agent({ id: 1, owner: 1 })

ann_agent : Principal
ann_agent = agent({ id: 3, owner: 2 })

accounts : List(Principal)
accounts = [
	boss,
	ann,
	boss_agent,
	ann_agent,
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

## Key number `key` acting as `acts_as`, granted by its owner (or itself,
## a human), expiring at 1000.
key_for : Principal, { scope : ApiKey.Scope(Str), key : U64 } -> ApiKey.Key(Str)
key_for = |acts_as, { scope, key }|
	match Principal.find(accounts, Principal.Id.Human(Principal.answers_to(acts_as))) {
		Err(NoSuchPrincipal) => crash "key_for: a test key's owner is among the accounts"
		Ok(granter) =>
			match ApiKey.Key.issue({
				granter,
				acts_as,
				scope,
				accounts,
				key: kid(key),
				expires: At(1000),
			}) {
				Ok(made) => made
				Err(Refused(_)) => crash "key_for: a test's key is grantable"
			}
	}

# The credentials.
boss_session : Admin.Credential(Str)
boss_session = Session({ id: sid(1), acts_as: Principal.id(boss) })

ann_session : Admin.Credential(Str)
ann_session = Session({ id: sid(2), acts_as: Principal.id(ann) })

agent_session : Admin.Credential(Str)
agent_session = Session({ id: sid(3), acts_as: Principal.id(boss_agent) })

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

# ── THE ADMIN TABLE
# Every credential against every action.

# boss's session: everything but retiring boss.
expect verdict(boss_session, ListAccounts) == Permitted
expect verdict(boss_session, retire_ann_agent) == Permitted
expect verdict(boss_session, retire_boss) == Refused(RetiresOwnAuthority)
expect verdict(boss_session, revoke_ann_keys) == Permitted
expect verdict(boss_session, revoke_ann_sessions) == Permitted
expect verdict(boss_session, ReadCounters) == Permitted

# ann's session: a member, nothing.
expect verdict(ann_session, ListAccounts) == Refused(NotAdmin)
expect verdict(ann_session, retire_ann_agent) == Refused(NotAdmin)
expect verdict(ann_session, retire_boss) == Refused(NotAdmin)
expect verdict(ann_session, revoke_ann_keys) == Refused(NotAdmin)
expect verdict(ann_session, revoke_ann_sessions) == Refused(NotAdmin)
expect verdict(ann_session, ReadCounters) == Refused(NotAdmin)

# A session claiming boss's agent: agents never sign in.
expect verdict(agent_session, ListAccounts) == Refused(SessionNotHuman)
expect verdict(agent_session, retire_ann_agent) == Refused(SessionNotHuman)
expect verdict(agent_session, retire_boss) == Refused(SessionNotHuman)
expect verdict(agent_session, revoke_ann_keys) == Refused(SessionNotHuman)
expect verdict(agent_session, revoke_ann_sessions) == Refused(SessionNotHuman)
expect verdict(agent_session, ReadCounters) == Refused(SessionNotHuman)

# boss_agent's admin key: as boss, but never retiring boss.
expect verdict(boss_agent_key, ListAccounts) == Permitted
expect verdict(boss_agent_key, retire_ann_agent) == Permitted
expect verdict(boss_agent_key, retire_boss) == Refused(RetiresOwnAuthority)
expect verdict(boss_agent_key, revoke_ann_keys) == Permitted
expect verdict(boss_agent_key, revoke_ann_sessions) == Permitted
expect verdict(boss_agent_key, ReadCounters) == Permitted

# ann_agent's key, without admin: nothing.
expect verdict(ann_agent_key, ListAccounts) == Refused(KeyRefused(OutOfScope))
expect verdict(ann_agent_key, retire_ann_agent) == Refused(KeyRefused(OutOfScope))
expect verdict(ann_agent_key, retire_boss) == Refused(KeyRefused(OutOfScope))
expect verdict(ann_agent_key, revoke_ann_keys) == Refused(KeyRefused(OutOfScope))
expect verdict(ann_agent_key, revoke_ann_sessions) == Refused(KeyRefused(OutOfScope))
expect verdict(ann_agent_key, ReadCounters) == Refused(KeyRefused(OutOfScope))

# boss's own admin key, revoked: nothing.
expect verdict(boss_revoked_key, ListAccounts) == Refused(KeyRefused(Revoked))
expect verdict(boss_revoked_key, retire_ann_agent) == Refused(KeyRefused(Revoked))
expect verdict(boss_revoked_key, retire_boss) == Refused(KeyRefused(Revoked))
expect verdict(boss_revoked_key, revoke_ann_keys) == Refused(KeyRefused(Revoked))
expect verdict(boss_revoked_key, revoke_ann_sessions) == Refused(KeyRefused(Revoked))
expect verdict(boss_revoked_key, ReadCounters) == Refused(KeyRefused(Revoked))

demoted : List(Principal)
demoted = [boss_demoted, boss_agent]

# The edges: an agent retiring itself; boss's session once boss is
# retired or demoted; boss_agent's key once boss is demoted, and once
# expired (it expires at 1000).
expect verdict(boss_agent_key, Retire(Principal.id(boss_agent))) == Refused(RetiresOwnAuthority)
expect lists(boss_session, { among: [ann], now: 500 }) == Refused(NoSuchPrincipal)
expect lists(boss_session, { among: [boss_demoted], now: 500 }) == Refused(NotAdmin)
expect lists(boss_agent_key, { among: demoted, now: 500 }) == Refused(KeyRefused(BeyondPrincipal))
expect lists(boss_agent_key, { among: accounts, now: 999 }) == Permitted
expect lists(boss_agent_key, { among: accounts, now: 1000 }) == Refused(KeyRefused(Expired))

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
