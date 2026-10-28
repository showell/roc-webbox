## **API KEYS, FIRST-CLASS AND SCOPED** (the Roc chat's auth design,
## sections 3 and 9): a key acts as one principal, with a scope of read,
## post and admin, each on or off, read and post narrowable to listed
## resources. It never exceeds its principal: a read is Access's `can_see`
## of the principal, a post its `can_post`, an admin action the principal's
## authority as the accounts say now. Generic over the resource's id (the
## chat's ConvId), so a database or a file system keys its own resources.
## The key's secret and its hash are the host's; this is the record the Roc
## decides on. Pure.
import Access
import Principal

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

	## What a key is asked to do: read a resource, post to it, or perform
	## an admin action (which one is Admin.roc's to decide).
	Action(id) : [
		Read(Access.Resource(id)),
		Post(Access.Resource(id)),
		Administer,
	]

	## Why a grant is refused.
	GrantRefusal : [
		## Only a human grants keys, from a browser or a key acting as them.
		GranterNotHuman,

		## A human grants for themselves and for the agents and bots they own.
		NotTheGrantersOwn,

		## The principal is not among the accounts (never made, or retired).
		NoSuchPrincipal,

		## Admin only for an admin human, or an agent an admin owns.
		AdminBeyondPrincipal,
	]

	## Why a key may not do what it was asked.
	Refusal : [
		Revoked,
		Expired,

		## The key's principal is not among the accounts any more.
		NoSuchPrincipal,

		## The key's scope does not reach it.
		OutOfScope,

		## The scope reaches it, but the principal itself may not.
		BeyondPrincipal,
	]

	## **MAY `granter` GIVE A KEY ACTING AS `acts_as` THIS SCOPE?** A human
	## may, for themselves and for the agents and bots they own; admin only
	## when `acts_as` has admin authority (Principal.authority: an admin
	## human, or an agent an admin owns). Read and post need no check here:
	## a key's every use is held to its principal.
	may_grant : {
		granter : Principal,
		acts_as : Principal,
		scope : ApiKey.Scope(id),
		accounts : List(Principal),
	} -> [Grantable, Refused(ApiKey.GrantRefusal)]
	may_grant = |
		{
			granter,
			acts_as,
			scope,
			accounts,
		},
	|
		match granter {
			Agent(_) | Bot(_) => Refused(GranterNotHuman)
			Human(human) =>
			# The principal as the accounts have it now: its owner and
			# its authority are theirs, not the caller's copy.
				match Principal.find(accounts, Principal.id(acts_as)) {
					Err(NoSuchPrincipal) => Refused(NoSuchPrincipal)
					Ok(current) =>
						if Principal.answers_to(current) != human.id {
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

		## A new key, active, when `granter` may grant it.
		issue : {
			granter : Principal,
			acts_as : Principal,
			scope : ApiKey.Scope(id),
			accounts : List(Principal),
			key : Principal.KeyId,
			expires : ApiKey.Expiry,
		} -> Try(ApiKey.Key(id), [Refused(ApiKey.GrantRefusal)])
		issue = |
			{
				granter,
				acts_as,
				scope,
				accounts,
				key,
				expires,
			},
		|
			match ApiKey.may_grant({
				granter,
				acts_as,
				scope,
				accounts,
			}) {
				Refused(why) => Err(Refused(why))
				Grantable =>
					Ok(
						ApiKey.Key.(
							{
								id: key,
								acts_as: Principal.id(acts_as),
								scope,
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

		## **MAY THIS KEY DO THIS, NOW?** In order: the key live; its
		## principal among the accounts; the scope reaching the action; the
		## principal itself allowed it (Access for a read or a post,
		## Principal.authority for an admin action).
		decide : ApiKey.Key(id),
		{
			accounts : List(Principal),
			action : ApiKey.Action(id),
			now : I64,
		} -> [Permitted, Refused(ApiKey.Refusal)]
			where [id.is_eq : id, id -> Bool]
		decide = |
			key,
			{
				accounts,
				action,
				now,
			},
		| {
			ApiKey.Key.(k) = key
			match key.liveness(now) {
				Revoked => Refused(Revoked)
				Expired => Refused(Expired)
				Live =>
					match Principal.find(accounts, k.acts_as) {
						Err(NoSuchPrincipal) => Refused(NoSuchPrincipal)
						Ok(principal) => {
							viewer = SignedIn(k.acts_as)
							match action {
								Read(resource) =>
									if !is_reached(k.scope.read, resource.id) {
										Refused(OutOfScope)
									} else if Access.can_see(viewer, resource) {
										Permitted
									} else {
										Refused(BeyondPrincipal)
									}
								Post(resource) =>
									if !is_reached(k.scope.post, resource.id) {
										Refused(OutOfScope)
									} else if Access.can_post(viewer, resource) {
										Permitted
									} else {
										Refused(BeyondPrincipal)
									}
								Administer =>
									match (k.scope.admin, principal.authority(accounts)) {
										(Off, _) => Refused(OutOfScope)
										(On, Admin) => Permitted
										(On, Member) => Refused(BeyondPrincipal)
									}
							}
						}
					}
			}
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

## `granter` asks for a key acting as `acts_as`, among `accounts`.
grant : Principal, { acts_as : Principal, scope : ApiKey.Scope(Str) } -> GrantAnswer
grant = |granter, { acts_as, scope }|
	ApiKey.may_grant({
		granter,
		acts_as,
		scope,
		accounts,
	})

# ── THE GRANT TABLE
# Every granter against every principal a key could act as, without admin
# and with it.

# boss, an admin human: their own and their agent's admin; never their bot's.
expect grant(boss, { acts_as: boss, scope: plain }) == Grantable
expect grant(boss, { acts_as: boss, scope: with_admin }) == Grantable
expect grant(boss, { acts_as: ann, scope: plain }) == Refused(NotTheGrantersOwn)
expect grant(boss, { acts_as: ann, scope: with_admin }) == Refused(NotTheGrantersOwn)
expect grant(boss, { acts_as: boss_agent, scope: plain }) == Grantable
expect grant(boss, { acts_as: boss_agent, scope: with_admin }) == Grantable
expect grant(boss, { acts_as: boss_bot, scope: plain }) == Grantable
expect grant(boss, { acts_as: boss_bot, scope: with_admin }) == Refused(AdminBeyondPrincipal)
expect grant(boss, { acts_as: ann_agent, scope: plain }) == Refused(NotTheGrantersOwn)
expect grant(boss, { acts_as: ann_agent, scope: with_admin }) == Refused(NotTheGrantersOwn)

# ann, a member: her own and her agent's, never admin.
expect grant(ann, { acts_as: boss, scope: plain }) == Refused(NotTheGrantersOwn)
expect grant(ann, { acts_as: boss, scope: with_admin }) == Refused(NotTheGrantersOwn)
expect grant(ann, { acts_as: ann, scope: plain }) == Grantable
expect grant(ann, { acts_as: ann, scope: with_admin }) == Refused(AdminBeyondPrincipal)
expect grant(ann, { acts_as: boss_agent, scope: plain }) == Refused(NotTheGrantersOwn)
expect grant(ann, { acts_as: boss_agent, scope: with_admin }) == Refused(NotTheGrantersOwn)
expect grant(ann, { acts_as: boss_bot, scope: plain }) == Refused(NotTheGrantersOwn)
expect grant(ann, { acts_as: boss_bot, scope: with_admin }) == Refused(NotTheGrantersOwn)
expect grant(ann, { acts_as: ann_agent, scope: plain }) == Grantable
expect grant(ann, { acts_as: ann_agent, scope: with_admin }) == Refused(AdminBeyondPrincipal)

# boss_agent, an agent, even an admin's: grants nothing.
expect grant(boss_agent, { acts_as: boss, scope: plain }) == Refused(GranterNotHuman)
expect grant(boss_agent, { acts_as: boss, scope: with_admin }) == Refused(GranterNotHuman)
expect grant(boss_agent, { acts_as: ann, scope: plain }) == Refused(GranterNotHuman)
expect grant(boss_agent, { acts_as: ann, scope: with_admin }) == Refused(GranterNotHuman)
expect grant(boss_agent, { acts_as: boss_agent, scope: plain }) == Refused(GranterNotHuman)
expect grant(boss_agent, { acts_as: boss_agent, scope: with_admin }) == Refused(GranterNotHuman)
expect grant(boss_agent, { acts_as: boss_bot, scope: plain }) == Refused(GranterNotHuman)
expect grant(boss_agent, { acts_as: boss_bot, scope: with_admin }) == Refused(GranterNotHuman)
expect grant(boss_agent, { acts_as: ann_agent, scope: plain }) == Refused(GranterNotHuman)
expect grant(boss_agent, { acts_as: ann_agent, scope: with_admin }) == Refused(GranterNotHuman)

# The accounts decide, not the caller's copy: a retired agent gets no key,
# though its owner grants it; a copy claiming boss's admin role for ann,
# or boss as the owner of ann's agent, is no admin and no owner.
expect
	ApiKey.may_grant({
		granter: ann,
		acts_as: ann_agent,
		scope: plain,
		accounts: [ann],
	})
		== Refused(NoSuchPrincipal)
ann_as_admin : Principal
ann_as_admin = person(2, Admin)

ann_agent_as_boss : Principal
ann_agent_as_boss = owned(Agent, { id: 3, owner: 1 })

expect grant(ann_as_admin, { acts_as: ann, scope: with_admin }) == Refused(AdminBeyondPrincipal)
expect grant(ann, { acts_as: ann_as_admin, scope: with_admin }) == Refused(AdminBeyondPrincipal)
expect grant(boss, { acts_as: ann_agent_as_boss, scope: plain }) == Refused(NotTheGrantersOwn)

# ── keys for the tables
## A key acting as `acts_as`, granted by its owner (or itself, a human).
issued : { acts_as : Principal, scope : ApiKey.Scope(Str) }, ApiKey.Expiry -> ApiKey.Key(Str)
issued = |{ acts_as, scope }, expires|
	match Principal.find(accounts, Principal.Id.Human(Principal.answers_to(acts_as))) {
		Err(NoSuchPrincipal) => crash "issued: a test key's owner is among the accounts"
		Ok(granter) =>
			match ApiKey.Key.issue({
				granter,
				acts_as,
				scope,
				accounts,
				key: kid(7),
				expires,
			}) {
				Ok(key) => key
				Err(Refused(_)) => crash "issued: a test's key is grantable"
			}
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
	ApiKey.Key.issue({
		granter: ann,
		acts_as: ann,
		scope: with_admin,
		accounts,
		key: kid(7),
		expires: Never,
	}).map_ok(ApiKey.Key.id)
		== Err(Refused(AdminBeyondPrincipal))

# ── THE DECISION TABLE
# Three resources: `a`, private to ann_agent; `b`, private to boss; `c`,
# boss's and public.
res_a : Access.Resource(Str)
res_a = {
	id: "a",
	participants: [Principal.id(ann_agent)],
	visibility: Private,
}

res_b : Access.Resource(Str)
res_b = {
	id: "b",
	participants: [Principal.id(boss)],
	visibility: Private,
}

res_c : Access.Resource(Str)
res_c = {
	id: "c",
	participants: [Principal.id(boss)],
	visibility: Public,
}

Answer : [Permitted, Refused(ApiKey.Refusal)]

## The key's answer to `action` at `now`, among `accounts`.
decided_at : ApiKey.Key(Str), { action : ApiKey.Action(Str), now : I64 } -> Answer
decided_at = |key, { action, now }|
	key.decide({
		accounts,
		action,
		now,
	})

## The key's answer to `action` at time 50, among `accounts`.
decided : ApiKey.Key(Str), ApiKey.Action(Str) -> Answer
decided = |key, action| decided_at(key, { action, now: 50 })

## The key's answer to an admin action at time 50, among `among` instead.
administers_among : ApiKey.Key(Str), List(Principal) -> Answer
administers_among = |key, among|
	key.decide({
		accounts: among,
		action: Administer,
		now: 50,
	})

# ann_agent, reading and posting everywhere: as far as ann_agent may.
ann_agent_plain : ApiKey.Key(Str)
ann_agent_plain = issued({ acts_as: ann_agent, scope: plain }, Never)

expect decided(ann_agent_plain, Read(res_a)) == Permitted
expect decided(ann_agent_plain, Read(res_b)) == Refused(BeyondPrincipal)
expect decided(ann_agent_plain, Read(res_c)) == Permitted
expect decided(ann_agent_plain, Post(res_a)) == Permitted
expect decided(ann_agent_plain, Post(res_b)) == Refused(BeyondPrincipal)
expect decided(ann_agent_plain, Post(res_c)) == Refused(BeyondPrincipal)
expect decided(ann_agent_plain, Administer) == Refused(OutOfScope)

# ann_agent, reading `c` alone.
ann_agent_reads_c : ApiKey.Key(Str)
ann_agent_reads_c = issued({ acts_as: ann_agent, scope: reads_c }, Never)

expect decided(ann_agent_reads_c, Read(res_a)) == Refused(OutOfScope)
expect decided(ann_agent_reads_c, Read(res_b)) == Refused(OutOfScope)
expect decided(ann_agent_reads_c, Read(res_c)) == Permitted
expect decided(ann_agent_reads_c, Post(res_a)) == Refused(OutOfScope)
expect decided(ann_agent_reads_c, Post(res_b)) == Refused(OutOfScope)
expect decided(ann_agent_reads_c, Post(res_c)) == Refused(OutOfScope)
expect decided(ann_agent_reads_c, Administer) == Refused(OutOfScope)

# ann_agent, posting to `a` alone.
ann_agent_posts_a : ApiKey.Key(Str)
ann_agent_posts_a = issued({ acts_as: ann_agent, scope: posts_a }, Never)

expect decided(ann_agent_posts_a, Read(res_a)) == Refused(OutOfScope)
expect decided(ann_agent_posts_a, Read(res_b)) == Refused(OutOfScope)
expect decided(ann_agent_posts_a, Read(res_c)) == Refused(OutOfScope)
expect decided(ann_agent_posts_a, Post(res_a)) == Permitted
expect decided(ann_agent_posts_a, Post(res_b)) == Refused(OutOfScope)
expect decided(ann_agent_posts_a, Post(res_c)) == Refused(OutOfScope)
expect decided(ann_agent_posts_a, Administer) == Refused(OutOfScope)

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
expect decided(boss_all, Administer) == Permitted

# boss_agent, admin alone: reads and posts nothing.
boss_agent_admin : ApiKey.Key(Str)
boss_agent_admin = issued({ acts_as: boss_agent, scope: admin_only }, Never)

expect decided(boss_agent_admin, Read(res_a)) == Refused(OutOfScope)
expect decided(boss_agent_admin, Read(res_b)) == Refused(OutOfScope)
expect decided(boss_agent_admin, Read(res_c)) == Refused(OutOfScope)
expect decided(boss_agent_admin, Post(res_a)) == Refused(OutOfScope)
expect decided(boss_agent_admin, Post(res_b)) == Refused(OutOfScope)
expect decided(boss_agent_admin, Post(res_c)) == Refused(OutOfScope)
expect decided(boss_agent_admin, Administer) == Permitted

# The key never exceeds its principal as the accounts say NOW: boss demoted,
# boss retired, or the agent itself retired.
expect administers_among(boss_agent_admin, [boss_demoted, boss_agent]) == Refused(BeyondPrincipal)
expect administers_among(boss_agent_admin, [boss_agent]) == Refused(BeyondPrincipal)
expect administers_among(boss_agent_admin, [boss]) == Refused(NoSuchPrincipal)
expect administers_among(boss_all, [boss_demoted]) == Refused(BeyondPrincipal)

# Liveness comes first: revoked and expired keys do nothing, even what
# their scope and principal would allow; an expiry at 100 is live at 99.
boss_until_100 : ApiKey.Key(Str)
boss_until_100 = issued({ acts_as: boss, scope: with_admin }, At(100))

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
expect decided(ann_claims_admin, Administer) == Refused(BeyondPrincipal)
expect decided(ann_claims_admin, Read(res_b)) == Refused(BeyondPrincipal)

# A narrowed record loads narrowed.
expect decided(ApiKey.Key.load(ann_agent_reads_c.record()), Read(res_a)) == Refused(OutOfScope)

expect decided(boss_all.revoke(), Read(res_c)) == Refused(Revoked)
expect decided_at(boss_until_100, { action: Read(res_c), now: 99 }) == Permitted
expect decided_at(boss_until_100, { action: Read(res_c), now: 100 }) == Refused(Expired)
expect decided_at(boss_until_100.revoke(), { action: Administer, now: 99 }) == Refused(Revoked)
