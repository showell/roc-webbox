## **API KEYS, FIRST-CLASS AND SCOPED** (the Roc chat's auth design,
## sections 3, 9 and 11): a key acts as one principal, with a scope of read,
## post and admin, each on or off, read and post narrowable to listed
## resources. It never exceeds its principal: a read is Access's `can_see`
## of the principal, a post its `can_post`, an admin action the principal's
## authority as the accounts say now. Keys are minted only from a browser
## session, never from a key. Generic over the resource (the chat's
## ConvAccess.Conv) and its id (the chat's ConvId), so a database or a file
## system keys its own resources. The key's secret and its hash are the
## host's; this is the record the Roc decides on. Pure.
import Access
import Principal
import Session
import Stored

ApiKey := [].{

	## Where a read or a post reaches: every resource its principal may
	## reach, or only the listed ones (a bot that posts only to #commits).
	Reach(id) : [Everywhere, Only(List(id))]

	## **WHAT A KEY MAY DO**, each part on or off. Admin is a scope of its
	## own: an admin-only key reads nothing.
	Scope(id) : {
		read : [Off, On(ApiKey.Reach(id))],
		post : [Off, On(ApiKey.Reach(id))],
		admin : [Off, On],
	}

	## When a key stops: never, or at a unix time (seconds), from which on
	## it is expired.
	Expiry : [Never, At(I64)]

	## What a key is asked to do with a resource: read it, or post to it
	## (an admin action is `administers`). The resource is its layer's own
	## value (the chat's opaque ConvAccess.Conv), which makes the
	## Access.Resource itself, from the accounts (its `resource` method):
	## never a record the caller built, which a handler could have made
	## public with `{ ..res, visibility: Public }`.
	Action(r) : [Read(r), Post(r)]

	## **WHO ASKS FOR A KEY**: the credential the request came with. Only a
	## browser's session mints keys; a key asking is refused, whatever its
	## scope, so a stolen key cannot mint a wider one.
	Granter(id) : [Session(Session), Key(ApiKey.Key(id))]

	## A request for a key: who asks, the principal the key would act as,
	## its scope, and the accounts and the time now.
	Grant(id) : {
		granter : ApiKey.Granter(id),
		acts_as : Principal.Id,
		scope : ApiKey.Scope(id),
		accounts : List(Principal),
		now : I64,
	}

	## Why a grant is refused.
	GrantRefusal : [
		## A key asked: keys are minted only from a browser session.
		GrantedByKey,

		## The session is over (idle, or past its week).
		SessionExpired,

		## The session's human has no account now (retired).
		NoSuchGranter,

		## A human grants for themselves and for the agents and bots they own.
		NotTheGrantersOwn,

		## The principal is not among the accounts (never made, or retired).
		NoSuchPrincipal,

		## Admin only for an admin human, or an agent an admin owns.
		AdminBeyondPrincipal,
	]

	## What a key's use is decided against: the accounts, and the time,
	## now.
	AsOf : { accounts : List(Principal), now : I64 }

	## A key's answer.
	Verdict : [Permitted, Refused(ApiKey.Refusal)]

	## Why a key may not do what it was asked.
	Refusal : [
		Revoked,
		Expired,

		## The key's principal, or the human it answers to, is not among the
		## accounts any more.
		NoSuchPrincipal,

		## The key's scope does not reach it.
		OutOfScope,

		## The scope reaches it, but the principal itself may not.
		BeyondPrincipal,
	]

	## **MAY THIS GRANTER GIVE A KEY ACTING AS `acts_as` THIS SCOPE?** Only
	## a live session, of a human with an account now, for themselves and
	## for the agents and bots they own; admin only when `acts_as` has admin
	## authority (Principal.authority: an admin human, or an agent an admin
	## owns). Read and post need no check here: a key's every use is held to
	## its principal.
	may_grant : ApiKey.Grant(id) -> [Grantable, Refused(ApiKey.GrantRefusal)]
	may_grant = |
		{
			granter,
			acts_as,
			scope,
			accounts,
			now,
		},
	|
		match granter {
			Key(_) => Refused(GrantedByKey)
			Session(session) =>
				match session.admit({ accounts, now }) {
					Refused(IdleExpired) | Refused(AbsoluteExpired) => Refused(SessionExpired)
					Refused(NoSuchAccount) => Refused(NoSuchGranter)
					Admitted({ principal: human, write: _ }) =>
					# The principal as the accounts have it now: its owner and
					# its authority are theirs, not the caller's copy.
						match Principal.find(accounts, acts_as) {
							Err(NoSuchPrincipal) => Refused(NoSuchPrincipal)
							Ok(current) =>
								if Principal.answers_to(current) != Principal.answers_to(human) {
									Refused(NotTheGrantersOwn)
								} else {
									match (scope.admin, Principal.authority(current, accounts)) {
										(Off, _) => Grantable
										(On, Admin) => Grantable
										(On, Member) => Refused(AdminBeyondPrincipal)
									}
								}
						}
				}
		}

	## **A KEY'S WHOLE RECORD**, as the store keeps it (KeyCodec).
	Record(id) : {
		id : Principal.KeyId,
		acts_as : Principal.Id,
		scope : ApiKey.Scope(id),
		expires : ApiKey.Expiry,
		revocation : [Active, Revoked],
	}

	## **A KEY, AS A STATE MACHINE**: opaque, so `issue` (which asks
	## `may_grant`) is the one way in, `load` the way back from the store,
	## and `revoke` the one transition.
	Key(id) :: {
		id : Principal.KeyId,
		acts_as : Principal.Id,
		scope : ApiKey.Scope(id),
		expires : ApiKey.Expiry,
		revocation : [Active, Revoked],
	}.{

		## A new key, active, when the grant is grantable.
		issue : ApiKey.Grant(id),
		{ key : Principal.KeyId, expires : ApiKey.Expiry } -> Try(
			ApiKey.Key(id),
			[Refused(ApiKey.GrantRefusal)],
		)
		issue = |grant, { key, expires }|
			match ApiKey.may_grant(grant) {
				Refused(why) => Err(Refused(why))
				Grantable =>
					Ok(
						ApiKey.Key.(
							{
								id: key,
								acts_as: grant.acts_as,
								scope: grant.scope,
								expires,
								revocation: Active,
							},
						),
					)
			}

		## **A KEY AS ITS STORED RECORD HOLDS IT** (KeyCodec.decode): the
		## record's principal, scope, expiry and revocation exactly, nothing
		## added and nothing widened. No grant is asked again: the record
		## was written from a key `issue` granted, and every use is still
		## held to its principal as the accounts say then (`decide`), so a
		## record claiming more than its principal may do does no more.
		load : ApiKey.Record(id) -> ApiKey.Key(id)
		load = |record| ApiKey.Key.(record)

		## The key's whole record, to store.
		record : ApiKey.Key(id) -> ApiKey.Record(id)
		record = |ApiKey.Key.(k)| k

		## The only transition: revoked, for good.
		revoke : ApiKey.Key(id) -> ApiKey.Key(id)
		revoke = |ApiKey.Key.(k)| ApiKey.Key.({ ..k, revocation: Revoked })

		## The key's public id.
		id : ApiKey.Key(id) -> Principal.KeyId
		id = |ApiKey.Key.(k)| k.id

		## The principal it acts as.
		acts_as : ApiKey.Key(id) -> Principal.Id
		acts_as = |ApiKey.Key.(k)| k.acts_as

		## **IS THE KEY LIVE AT `now`?** Revoked is said first, expired or
		## not; an expiry at `t` is live before `t` and expired from `t` on.
		liveness : ApiKey.Key(id),
		I64 -> [
			Live,
			Expired,
			Revoked,
		]
		liveness = |ApiKey.Key.(k), now|
			match (k.revocation, k.expires) {
				(Revoked, _) => Revoked
				(Active, Never) => Live
				(Active, At(t)) => if now < t Live else Expired
			}

		## **MAY THIS KEY READ OR POST HERE, NOW?** In order: the key live;
		## its principal among the accounts, and the human it answers to too
		## (an owner retired takes their agents' keys with them); the scope
		## reaching the resource; the principal itself allowed it (Access, on
		## the resource as its layer makes it from the accounts).
		decide : ApiKey.Key(id),
		{
			accounts : List(Principal),
			action : ApiKey.Action(r),
			now : I64,
		} -> ApiKey.Verdict
			where [
				id.is_eq : id, id -> Bool,
				r.resource : r, List(Principal) -> Access.Resource(id),
			]
		decide = |
			key,
			{
				accounts,
				action,
				now,
			},
		| {
			ApiKey.Key.(k) = key
			match standing(key, { accounts, now }) {
				Refused(why) => Refused(why)
				Standing(_) => {
					viewer = SignedIn(k.acts_as)
					match action {
						Read(held) => {
							resource = held.resource(accounts)
							if !is_reached(k.scope.read, resource.id) {
								Refused(OutOfScope)
							} else if Access.can_see(viewer, resource) {
								Permitted
							} else {
								Refused(BeyondPrincipal)
							}
						}

						Post(held) => {
							resource = held.resource(accounts)
							if !is_reached(k.scope.post, resource.id) {
								Refused(OutOfScope)
							} else if Access.can_post(viewer, resource) {
								Permitted
							} else {
								Refused(BeyondPrincipal)
							}
						}
					}
				}
			}
		}

		## **MAY THIS KEY PERFORM AN ADMIN ACTION, NOW?** The key live and
		## its principal standing, as for `decide`; an admin scope; and the
		## principal's authority Admin as the accounts say now. Which action
		## is Admin.roc's to decide.
		administers : ApiKey.Key(id), ApiKey.AsOf -> ApiKey.Verdict
		administers = |key, { accounts, now }| {
			ApiKey.Key.(k) = key
			match standing(key, { accounts, now }) {
				Refused(why) => Refused(why)
				Standing(principal) =>
					match (k.scope.admin, principal.authority(accounts)) {
						(Off, _) => Refused(OutOfScope)
						(On, Admin) => Permitted
						(On, Member) => Refused(BeyondPrincipal)
					}
			}
		}
	}
}

## **A KEY'S PRINCIPAL, STANDING NOW**: the key live at `now`, and the
## principal it acts as among `accounts`, with the human it answers to
## (a human, itself; an agent or a bot, its owner) among them too.
standing : ApiKey.Key(id), ApiKey.AsOf -> [Standing(Principal), Refused(ApiKey.Refusal)]
standing = |key, { accounts, now }|
	match key.liveness(now) {
		Revoked => Refused(Revoked)
		Expired => Refused(Expired)
		Live =>
			match Principal.find(accounts, key.acts_as()) {
				Err(NoSuchPrincipal) => Refused(NoSuchPrincipal)
				Ok(principal) =>
					if Principal.has_account(accounts, Principal.answers_to(principal)) {
						Standing(principal)
					} else {
						Refused(NoSuchPrincipal)
					}
			}
	}

## A read's or a post's part of a scope reaches the resource `id`.
is_reached : [Off, On(ApiKey.Reach(id))], id -> Bool where [id.is_eq : id, id -> Bool]
is_reached = |part, id|
	match part {
		Off => Bool.False
		On(Everywhere) => Bool.True
		On(Only(ids)) => List.contains(ids, id)
	}

# The cast:
#   boss        an admin human
#   ann         a member human
#   boss_agent  an agent boss owns
#   boss_bot    a bot boss owns
#   ann_agent   an agent ann owns
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

## A test's agent or bot: its id, and its owner's GitHub id.
owned : [Agent, Bot], { id : U64, owner : U64 } -> Principal
owned = |kind, { id, owner }|
	match kind {
		Agent =>
			Principal.Agent({
				id: aid(id),
				name: "a${id.to_str()}",
				owner: gid(owner),
			})

		Bot =>
			Principal.Bot({
				id: aid(id),
				name: "b${id.to_str()}",
				owner: gid(owner),
			})
	}

boss : Principal
boss = person(1, Admin)

boss_demoted : Principal
boss_demoted = person(1, Member)

ann : Principal
ann = person(2, Member)

boss_agent : Principal
boss_agent = owned(Agent, { id: 1, owner: 1 })

boss_bot : Principal
boss_bot = owned(Bot, { id: 2, owner: 1 })

ann_agent : Principal
ann_agent = owned(Agent, { id: 3, owner: 2 })

accounts : List(Principal)
accounts = [
	boss,
	ann,
	boss_agent,
	boss_bot,
	ann_agent,
]

## Human `who`'s browser session `n`, signed in at time 0.
signed_in : { n : U64, who : U64 } -> ApiKey.Granter(Str)
signed_in = |{ n, who }|
	Session(
		Session.start({
			id: sid(n),
			human: gid(who),
			token_hash: token(7),
			now: 0,
		}),
	)

## A test's token hash: every byte `b`.
token : U8 -> Stored.SecretHash
token = |b|
	match Stored.SecretHash.from_bytes(List.repeat(b, 32)) {
		Ok(h) => h
		Err(NotAHash) => crash "token: 32 bytes are a hash"
	}

by_boss : ApiKey.Granter(Str)
by_boss = signed_in({ n: 1, who: 1 })

by_ann : ApiKey.Granter(Str)
by_ann = signed_in({ n: 2, who: 2 })

# The scopes the tables use.
plain : ApiKey.Scope(Str)
plain = {
	read: On(Everywhere),
	post: On(Everywhere),
	admin: Off,
}

with_admin : ApiKey.Scope(Str)
with_admin = {
	read: On(Everywhere),
	post: On(Everywhere),
	admin: On,
}

admin_only : ApiKey.Scope(Str)
admin_only = {
	read: Off,
	post: Off,
	admin: On,
}

reads_c : ApiKey.Scope(Str)
reads_c = {
	read: On(Only(["c"])),
	post: Off,
	admin: Off,
}

posts_a : ApiKey.Scope(Str)
posts_a = {
	read: Off,
	post: On(Only(["a"])),
	admin: Off,
}

GrantAnswer : [Grantable, Refused(ApiKey.GrantRefusal)]

## `granter` asks for a key acting as `acts_as`, among `among`, at `now`.
grant_at : ApiKey.Granter(Str),
{
	acts_as : Principal,
	scope : ApiKey.Scope(Str),
	among : List(Principal),
	now : I64,
} -> GrantAnswer
grant_at = |
	granter,
	{
		acts_as,
		scope,
		among,
		now,
	},
|
	ApiKey.may_grant({
		granter,
		acts_as: Principal.id(acts_as),
		scope,
		accounts: among,
		now,
	})

## `granter` asks for a key acting as `acts_as`, among `accounts`, at 50.
grant : ApiKey.Granter(Str), { acts_as : Principal, scope : ApiKey.Scope(Str) } -> GrantAnswer
grant = |granter, { acts_as, scope }|
	grant_at(
		granter,
		{
			acts_as,
			scope,
			among: accounts,
			now: 50,
		},
	)

# ── THE GRANT TABLE
# Every granter against every principal a key could act as, without admin
# and with it.

# boss's session, an admin's: their own and their agent's admin; never
# their bot's.
expect grant(by_boss, { acts_as: boss, scope: plain }) == Grantable
expect grant(by_boss, { acts_as: boss, scope: with_admin }) == Grantable
expect grant(by_boss, { acts_as: ann, scope: plain }) == Refused(NotTheGrantersOwn)
expect grant(by_boss, { acts_as: ann, scope: with_admin }) == Refused(NotTheGrantersOwn)
expect grant(by_boss, { acts_as: boss_agent, scope: plain }) == Grantable
expect grant(by_boss, { acts_as: boss_agent, scope: with_admin }) == Grantable
expect grant(by_boss, { acts_as: boss_bot, scope: plain }) == Grantable
expect grant(by_boss, { acts_as: boss_bot, scope: with_admin }) == Refused(AdminBeyondPrincipal)
expect grant(by_boss, { acts_as: ann_agent, scope: plain }) == Refused(NotTheGrantersOwn)
expect grant(by_boss, { acts_as: ann_agent, scope: with_admin }) == Refused(NotTheGrantersOwn)

# ann's session, a member's: her own and her agent's, never admin.
expect grant(by_ann, { acts_as: boss, scope: plain }) == Refused(NotTheGrantersOwn)
expect grant(by_ann, { acts_as: boss, scope: with_admin }) == Refused(NotTheGrantersOwn)
expect grant(by_ann, { acts_as: ann, scope: plain }) == Grantable
expect grant(by_ann, { acts_as: ann, scope: with_admin }) == Refused(AdminBeyondPrincipal)
expect grant(by_ann, { acts_as: boss_agent, scope: plain }) == Refused(NotTheGrantersOwn)
expect grant(by_ann, { acts_as: boss_agent, scope: with_admin }) == Refused(NotTheGrantersOwn)
expect grant(by_ann, { acts_as: boss_bot, scope: plain }) == Refused(NotTheGrantersOwn)
expect grant(by_ann, { acts_as: boss_bot, scope: with_admin }) == Refused(NotTheGrantersOwn)
expect grant(by_ann, { acts_as: ann_agent, scope: plain }) == Grantable
expect grant(by_ann, { acts_as: ann_agent, scope: with_admin }) == Refused(AdminBeyondPrincipal)

# A key, even boss's own with admin: grants nothing (bug 3: keys are minted
# only from a browser session).
expect grant(Key(boss_all), { acts_as: boss, scope: plain }) == Refused(GrantedByKey)
expect grant(Key(boss_all), { acts_as: boss, scope: with_admin }) == Refused(GrantedByKey)
expect grant(Key(boss_all), { acts_as: ann, scope: plain }) == Refused(GrantedByKey)
expect grant(Key(boss_all), { acts_as: ann, scope: with_admin }) == Refused(GrantedByKey)
expect grant(Key(boss_all), { acts_as: boss_agent, scope: plain }) == Refused(GrantedByKey)
expect grant(Key(boss_all), { acts_as: boss_agent, scope: with_admin }) == Refused(GrantedByKey)
expect grant(Key(boss_all), { acts_as: boss_bot, scope: plain }) == Refused(GrantedByKey)
expect grant(Key(boss_all), { acts_as: boss_bot, scope: with_admin }) == Refused(GrantedByKey)
expect grant(Key(boss_all), { acts_as: ann_agent, scope: plain }) == Refused(GrantedByKey)
expect grant(Key(boss_all), { acts_as: ann_agent, scope: with_admin }) == Refused(GrantedByKey)

# The accounts decide, not the caller's copy: a retired agent gets no key,
# though its owner grants it; a copy claiming boss's admin role for ann, or
# boss as the owner of ann's agent, is no admin and no owner.
expect
	grant_at(
		by_ann,
		{
			acts_as: ann_agent,
			scope: plain,
			among: [ann],
			now: 50,
		},
	)
		== Refused(NoSuchPrincipal)
ann_as_admin : Principal
ann_as_admin = person(2, Admin)

ann_agent_as_boss : Principal
ann_agent_as_boss = owned(Agent, { id: 3, owner: 1 })

expect grant(by_ann, { acts_as: ann_as_admin, scope: with_admin }) == Refused(AdminBeyondPrincipal)
expect grant(by_boss, { acts_as: ann_agent_as_boss, scope: plain }) == Refused(NotTheGrantersOwn)

# The granter is the accounts' too (bug 2): a retired human's session
# grants nothing for the agent left behind; nor does a session past its
# day idle.
without_ann : List(Principal)
without_ann = [
	boss,
	boss_agent,
	boss_bot,
	ann_agent,
]

expect
	grant_at(
		by_ann,
		{
			acts_as: ann_agent,
			scope: plain,
			among: without_ann,
			now: 50,
		},
	)
		== Refused(NoSuchGranter)
expect
	grant_at(
		by_ann,
		{
			acts_as: ann,
			scope: plain,
			among: accounts,
			now: Session.idle_secs,
		},
	)
		== Refused(SessionExpired)

# ── keys for the tables
## A key acting as `acts_as`, granted by its owner's session.
issued : { acts_as : Principal, scope : ApiKey.Scope(Str) }, ApiKey.Expiry -> ApiKey.Key(Str)
issued = |{ acts_as, scope }, expires|
	match ApiKey.Key.issue(
		{
			granter: signed_in({ n: 9, who: Principal.answers_to(acts_as).to_u64() }),
			acts_as: Principal.id(acts_as),
			scope,
			accounts,
			now: 50,
		},
		{ key: kid(7), expires },
	) {
		Ok(key) => key
		Err(Refused(_)) => crash "issued: a test's key is grantable"
	}

ann_forever : ApiKey.Key(Str)
ann_forever = issued({ acts_as: ann, scope: plain }, Never)

ann_until_100 : ApiKey.Key(Str)
ann_until_100 = issued({ acts_as: ann, scope: plain }, At(100))

# ── THE LIVENESS TABLE
expect ann_forever.liveness(0) == Live
expect ann_forever.liveness(9999999999) == Live
expect ann_until_100.liveness(99) == Live
expect ann_until_100.liveness(100) == Expired
expect ann_until_100.liveness(101) == Expired
expect ann_forever.revoke().liveness(0) == Revoked
expect ann_until_100.revoke().liveness(99) == Revoked
expect ann_until_100.revoke().liveness(101) == Revoked

# An ungrantable key is never issued.
expect
	ApiKey.Key.issue(
		{
			granter: by_ann,
			acts_as: Principal.id(ann),
			scope: with_admin,
			accounts,
			now: 50,
		},
		{ key: kid(7), expires: Never },
	).map_ok(ApiKey.Key.id)
		== Err(Refused(AdminBeyondPrincipal))

# ── THE DECISION TABLE
## **A TEST'S RESOURCE**: a fixed Access.Resource, the accounts not asked.
## The chat's is ConvAccess.Conv, which makes its resource from the
## accounts; this one stands in for it here, where the core is tested
## without the chat.
Held :: Access.Resource(Str).{
	resource : Held, List(Principal) -> Access.Resource(Str)
	resource = |Held.(r), _accounts| r
}

# Three resources: `a`, private to ann_agent (and so to ann, its owner);
# `b`, private to boss; `c`, boss's and public.
res_a : Held
res_a = Held.(
	{
		id: "a",
		participants: [Principal.id(ann_agent)],
		involved: [gid(2)],
		visibility: Private,
	},
)

res_b : Held
res_b = Held.(
	{
		id: "b",
		participants: [Principal.id(boss)],
		involved: [gid(1)],
		visibility: Private,
	},
)

res_c : Held
res_c = Held.(
	{
		id: "c",
		participants: [Principal.id(boss)],
		involved: [gid(1)],
		visibility: Public,
	},
)

Answer : [Permitted, Refused(ApiKey.Refusal)]

## The key's answer to `action` at `now`, among `accounts`.
decided_at : ApiKey.Key(Str), { action : ApiKey.Action(Held), now : I64 } -> Answer
decided_at = |key, { action, now }|
	key.decide({
		accounts,
		action,
		now,
	})

## The key's answer to `action` at time 50, among `accounts`.
decided : ApiKey.Key(Str), ApiKey.Action(Held) -> Answer
decided = |key, action| decided_at(key, { action, now: 50 })

## The key's answer to `action` at time 50, once ann has retired.
decided_after_ann : ApiKey.Key(Str), ApiKey.Action(Held) -> Answer
decided_after_ann = |key, action|
	key.decide({
		accounts: without_ann,
		action,
		now: 50,
	})

## The key's answer to an admin action at time 50, among `accounts`.
administered : ApiKey.Key(Str) -> Answer
administered = |key| key.administers({ accounts, now: 50 })

## The key's answer to an admin action at time 50, among `among` instead.
administers_among : ApiKey.Key(Str), List(Principal) -> Answer
administers_among = |key, among| key.administers({ accounts: among, now: 50 })

# ann_agent, reading and posting everywhere: as far as ann_agent may.
ann_agent_plain : ApiKey.Key(Str)
ann_agent_plain = issued({ acts_as: ann_agent, scope: plain }, Never)

expect decided(ann_agent_plain, Read(res_a)) == Permitted
expect decided(ann_agent_plain, Read(res_b)) == Refused(BeyondPrincipal)
expect decided(ann_agent_plain, Read(res_c)) == Permitted
expect decided(ann_agent_plain, Post(res_a)) == Permitted
expect decided(ann_agent_plain, Post(res_b)) == Refused(BeyondPrincipal)
expect decided(ann_agent_plain, Post(res_c)) == Refused(BeyondPrincipal)
expect administered(ann_agent_plain) == Refused(OutOfScope)

# ann_agent, reading `c` alone.
ann_agent_reads_c : ApiKey.Key(Str)
ann_agent_reads_c = issued({ acts_as: ann_agent, scope: reads_c }, Never)

expect decided(ann_agent_reads_c, Read(res_a)) == Refused(OutOfScope)
expect decided(ann_agent_reads_c, Read(res_b)) == Refused(OutOfScope)
expect decided(ann_agent_reads_c, Read(res_c)) == Permitted
expect decided(ann_agent_reads_c, Post(res_a)) == Refused(OutOfScope)
expect decided(ann_agent_reads_c, Post(res_b)) == Refused(OutOfScope)
expect decided(ann_agent_reads_c, Post(res_c)) == Refused(OutOfScope)
expect administered(ann_agent_reads_c) == Refused(OutOfScope)

# ann_agent, posting to `a` alone.
ann_agent_posts_a : ApiKey.Key(Str)
ann_agent_posts_a = issued({ acts_as: ann_agent, scope: posts_a }, Never)

expect decided(ann_agent_posts_a, Read(res_a)) == Refused(OutOfScope)
expect decided(ann_agent_posts_a, Read(res_b)) == Refused(OutOfScope)
expect decided(ann_agent_posts_a, Read(res_c)) == Refused(OutOfScope)
expect decided(ann_agent_posts_a, Post(res_a)) == Permitted
expect decided(ann_agent_posts_a, Post(res_b)) == Refused(OutOfScope)
expect decided(ann_agent_posts_a, Post(res_c)) == Refused(OutOfScope)
expect administered(ann_agent_posts_a) == Refused(OutOfScope)

# ann herself, reading and posting everywhere: her agent's `a` too, as its
# owner (decision 1).
expect decided(ann_forever, Read(res_a)) == Permitted
expect decided(ann_forever, Read(res_b)) == Refused(BeyondPrincipal)
expect decided(ann_forever, Read(res_c)) == Permitted
expect decided(ann_forever, Post(res_a)) == Permitted
expect decided(ann_forever, Post(res_b)) == Refused(BeyondPrincipal)
expect decided(ann_forever, Post(res_c)) == Refused(BeyondPrincipal)
expect administered(ann_forever) == Refused(OutOfScope)

# boss, everything and admin: an admin still reads no private resource it
# is not in (`a`).
boss_all : ApiKey.Key(Str)
boss_all = issued({ acts_as: boss, scope: with_admin }, Never)

expect decided(boss_all, Read(res_a)) == Refused(BeyondPrincipal)
expect decided(boss_all, Read(res_b)) == Permitted
expect decided(boss_all, Read(res_c)) == Permitted
expect decided(boss_all, Post(res_a)) == Refused(BeyondPrincipal)
expect decided(boss_all, Post(res_b)) == Permitted
expect decided(boss_all, Post(res_c)) == Permitted
expect administered(boss_all) == Permitted

# boss_agent, admin alone: reads and posts nothing.
boss_agent_admin : ApiKey.Key(Str)
boss_agent_admin = issued({ acts_as: boss_agent, scope: admin_only }, Never)

expect decided(boss_agent_admin, Read(res_a)) == Refused(OutOfScope)
expect decided(boss_agent_admin, Read(res_b)) == Refused(OutOfScope)
expect decided(boss_agent_admin, Read(res_c)) == Refused(OutOfScope)
expect decided(boss_agent_admin, Post(res_a)) == Refused(OutOfScope)
expect decided(boss_agent_admin, Post(res_b)) == Refused(OutOfScope)
expect decided(boss_agent_admin, Post(res_c)) == Refused(OutOfScope)
expect administered(boss_agent_admin) == Permitted

# boss_bot, reading everywhere: a bot reads a public resource only when it
# is in it (decision 3).
boss_bot_plain : ApiKey.Key(Str)
boss_bot_plain = issued({ acts_as: boss_bot, scope: plain }, Never)

expect decided(boss_bot_plain, Read(res_c)) == Refused(BeyondPrincipal)

# The key never exceeds its principal as the accounts say NOW: boss demoted,
# boss retired, or the agent itself retired.
expect administers_among(boss_agent_admin, [boss_demoted, boss_agent]) == Refused(BeyondPrincipal)
expect administers_among(boss_agent_admin, [boss_agent]) == Refused(NoSuchPrincipal)
expect administers_among(boss_agent_admin, [boss]) == Refused(NoSuchPrincipal)
expect administers_among(boss_all, [boss_demoted]) == Refused(BeyondPrincipal)

# Bug 1: ann retired, her agent's key reads and posts nothing, even what
# its scope and the resource would allow.
expect decided_after_ann(ann_agent_plain, Read(res_a)) == Refused(NoSuchPrincipal)
expect decided_after_ann(ann_agent_plain, Read(res_c)) == Refused(NoSuchPrincipal)
expect decided_after_ann(ann_agent_plain, Post(res_a)) == Refused(NoSuchPrincipal)

# Liveness comes first: revoked and expired keys do nothing, even what
# their scope and principal would allow; an expiry at 100 is live at 99.
boss_until_100 : ApiKey.Key(Str)
boss_until_100 = issued({ acts_as: boss, scope: with_admin }, At(100))

expect decided(boss_all.revoke(), Read(res_c)) == Refused(Revoked)
expect decided_at(boss_until_100, { action: Read(res_c), now: 99 }) == Permitted
expect decided_at(boss_until_100, { action: Read(res_c), now: 100 }) == Refused(Expired)
expect boss_until_100.revoke().administers({ accounts, now: 99 }) == Refused(Revoked)

# ── LOADING A STORED KEY
# A key's record loads back to the same record, revoked or not.
expect List.all(
	[
		ann_forever,
		boss_until_100,
		ann_agent_reads_c,
		boss_agent_admin.revoke(),
	],
	|key| ApiKey.Key.load(key.record()).record() == key.record(),
)

# A record claiming admin for ann, a member, loads as it says, and the key
# still administers nothing: its use is held to ann.
ann_claims_admin : ApiKey.Key(Str)
ann_claims_admin = ApiKey.Key.load({ ..ann_forever.record(), scope: with_admin })

expect ann_claims_admin.record().scope == with_admin
expect administered(ann_claims_admin) == Refused(BeyondPrincipal)
expect decided(ann_claims_admin, Read(res_b)) == Refused(BeyondPrincipal)

# A narrowed record loads narrowed.
expect decided(ApiKey.Key.load(ann_agent_reads_c.record()), Read(res_a)) == Refused(OutOfScope)
